import Foundation
import Combine

@MainActor
final class AgyTokenViewModel: ObservableObject {
    // MARK: - 基础状态
    @Published var isLoading: Bool = false
    @Published var lastSyncTime: String = "--:--:--"
    @Published var statusMessage: String = "正在扫描本地多工具数据..."

    // MARK: - 用户偏好筛选设置
    @Published var toolMode: String = "all" { didSet { applyFilter(); saveState() } }
    @Published var periodMode: String = "today" { didSet { applyFilter(); saveState() } }
    @Published var customStart: String = "" { didSet { applyFilter(); saveState() } }
    @Published var customEnd: String = "" { didSet { applyFilter(); saveState() } }
    @Published var showCNY: Bool = true { didSet { saveState() } }
    @Published var showChart: Bool = true { didSet { saveState() } }
    @Published var autoRefresh: Bool = true { didSet { updateAutoRefreshTimer(); saveState() } }
    @Published var streamPrediction: Bool = true {
        didSet {
            predictor.enabled = streamPrediction
            updatePredictionTimer()
            if !streamPrediction {
                syncLiveTelemetryToGround()
            }
            saveState()
        }
    }
    @Published var searchQuery: String = "" { didSet { applyFilter(); saveState() } }

    // MARK: - 扫描结果缓存与当前筛选数据
    @Published var scanResult: ScanResult?
    @Published var availableDates: [String] = []
    @Published var filteredConversations: [ConversationItem] = []

    // 聚合统计 (针对当前筛选的时期与工具)
    @Published var periodTokens: Int = 0
    @Published var periodPrompt: Int = 0
    @Published var periodOutput: Int = 0
    @Published var periodCached: Int = 0
    @Published var periodThoughts: Int = 0
    @Published var periodCostUSD: Double = 0.0
    @Published var periodSavedUSD: Double = 0.0
    @Published var cacheRate: Double = 0.0
    @Published var periodDisplayName: String = "今天"
    @Published var toolDisplayName: String = "全工具"

    // 行级活跃状态只在物理扫描/筛选时更新，避免随实时预测高频广播。
    @Published var activeTaskMap: [String: ActiveTaskState] = [:]

    // MARK: - 图表数据
    @Published var chartPoints: [ChartPoint] = []
    @Published var chartPeakValM: Double = 0.0
    @Published var chartPeakDate: String = ""
    @Published var chartPeakCostUSD: Double = 0.0
    @Published var chartAverageM: Double = 0.0

    // MARK: - 模态详情
    @Published var selectedConversation: ConversationItem? = nil
    @Published var showingDetailSheet: Bool = false

    // MARK: - 内部组件
    private let predictor = TokenPredictor()
    let liveTelemetry = LiveTelemetry()
    private var predictionCancellable: AnyCancellable?
    private var autoRefreshCancellable: AnyCancellable?
    private var scanInFlight = false

    private var stateFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgyToken", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    init() {
        loadState()
        setupTimers()
        Task {
            await runScan(silent: false)
        }
    }

    // MARK: - 定时器配置 (30s 物理扫描 + 500ms 微步外推)
    private func setupTimers() {
        updatePredictionTimer()
        updateAutoRefreshTimer()
    }

    private func updatePredictionTimer() {
        predictionCancellable?.cancel()
        predictionCancellable = nil

        // 关闭实时预测时直接取消定时器，不保留空转回调。
        guard streamPrediction else { return }

        predictionCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.onPredictionTick()
            }
    }

    private func updateAutoRefreshTimer() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil
        if autoRefresh {
            autoRefreshCancellable = Timer.publish(every: 30.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    Task {
                        await self.runScan(silent: true)
                    }
                }
        }
    }

    // MARK: - 500ms 预测微步 Tick
    private func onPredictionTick() {
        guard predictor.enabled && predictor.todayTotalGround > 0 else {
            let summary = scanResult?.summary
            publishLiveTelemetry(
                todayTotal: summary?.todayTotal ?? liveTelemetry.displayedTodayTotal,
                todayCostUSD: summary?.todayCostUSD ?? liveTelemetry.displayedTodayCostUSD,
                periodTotal: periodTokens,
                periodCostUSD: periodCostUSD,
                isActive: false,
                velocity: 0.0,
                latestTool: liveTelemetry.latestToolName
            )
            return
        }

        let (active, v) = predictor.tick(dt: 0.5)
        let displayedPeriodTotal = predictor.periodIncludesToday
            ? Int(round(predictor.periodTotalPred))
            : periodTokens
        let displayedPeriodCostUSD = predictor.periodIncludesToday
            ? predictor.periodCostPred
            : periodCostUSD

        publishLiveTelemetry(
            todayTotal: Int(round(predictor.todayTotalPred)),
            todayCostUSD: predictor.todayCostPred,
            periodTotal: displayedPeriodTotal,
            periodCostUSD: displayedPeriodCostUSD,
            isActive: active,
            velocity: v,
            latestTool: predictor.latestTool
        )
    }

    private func publishLiveTelemetry(
        todayTotal: Int,
        todayCostUSD: Double,
        periodTotal: Int,
        periodCostUSD: Double,
        isActive: Bool,
        velocity: Double,
        latestTool: String
    ) {
        // @Published 即使重复赋同一个值也会发通知，因此只在显示值变化时赋值。
        if liveTelemetry.displayedTodayTotal != todayTotal {
            liveTelemetry.displayedTodayTotal = todayTotal
        }
        if liveTelemetry.displayedTodayCostUSD != todayCostUSD {
            liveTelemetry.displayedTodayCostUSD = todayCostUSD
        }
        if liveTelemetry.displayedPeriodTotal != periodTotal {
            liveTelemetry.displayedPeriodTotal = periodTotal
        }
        if liveTelemetry.displayedPeriodCostUSD != periodCostUSD {
            liveTelemetry.displayedPeriodCostUSD = periodCostUSD
        }
        if liveTelemetry.isGeneratingActive != isActive {
            liveTelemetry.isGeneratingActive = isActive
        }
        if liveTelemetry.liveVelocity != velocity {
            liveTelemetry.liveVelocity = velocity
        }
        if liveTelemetry.latestToolName != latestTool {
            liveTelemetry.latestToolName = latestTool
        }
    }

    private func syncLiveTelemetryToGround() {
        guard let summary = scanResult?.summary else { return }
        publishLiveTelemetry(
            todayTotal: summary.todayTotal,
            todayCostUSD: summary.todayCostUSD,
            periodTotal: periodTokens,
            periodCostUSD: periodCostUSD,
            isActive: false,
            velocity: 0.0,
            latestTool: liveTelemetry.latestToolName
        )
    }

    // MARK: - 核心物理扫描 (调起 Python token_scanner.py --json)
    func runScan(silent: Bool = false) async {
        // 静默刷新也必须占用同一个 in-flight 槽位，避免扫描超过刷新周期时
        // 同时启动多个 Python 进程读取同一批历史日志。
        guard !scanInFlight else { return }
        scanInFlight = true
        defer {
            scanInFlight = false
            isLoading = false
        }

        if !silent {
            isLoading = true
            statusMessage = "正在扫描三大 AI 工具物理日志与价格库..."
        }

        let pythonPath = resolvePython()
        let scannerScript = resolveScannerScript()

        let resultData: ScanResult? = await Task.detached(priority: .userInitiated) { () -> ScanResult? in
            guard let py = pythonPath, let script = scannerScript else {
                print("未找到 Python 或扫描器脚本")
                return nil
            }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: py)
            // 扫描器只使用 Python 标准库。-S 跳过无关的 site-package 初始化，
            // 避免从 macOS 图形应用启动时被用户环境中的 Python 扩展拖住。
            p.arguments = ["-S", script, "--json"]
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            p.standardInput = FileHandle.nullDevice

            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice

            var env = ProcessInfo.processInfo.environment
            env["PYTHONUNBUFFERED"] = "1"
            env["LC_ALL"] = "zh_CN.UTF-8"
            p.environment = env

            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()

                guard p.terminationStatus == 0, !data.isEmpty else {
                    return nil
                }

                let decoder = JSONDecoder()
                return try decoder.decode(ScanResult.self, from: data)
            } catch {
                print("执行 Python 扫描异常: \(error)")
                return nil
            }
        }.value

        if let res = resultData {
            self.scanResult = res

            // 提取所有唯一日期列表
            let allDates = Set(res.conversations.map { String($0.time.prefix(10)) })
            self.availableDates = allDates.sorted()

            // 更新真值并同步至预测引擎
            self.applyFilter()

            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            self.lastSyncTime = f.string(from: Date())
            self.statusMessage = "扫描完成 | 共扫描 \(res.conversations.count) 个会话"
        } else if !silent {
            self.statusMessage = "扫描失败，请确保 Python 环境正常"
        }

    }

    // MARK: - 数据过滤与聚合统计
    func applyFilter() {
        guard let res = scanResult else { return }

        // 1. 工具来源筛选
        var baseConvs: [ConversationItem] = res.conversations
        switch toolMode {
        case "Antigravity":
            baseConvs = res.conversations.filter { $0.tool == "Antigravity" }
            toolDisplayName = "Antigravity"
        case "Codex":
            baseConvs = res.conversations.filter { $0.tool == "Codex" }
            toolDisplayName = "Codex"
        case "Claude":
            baseConvs = res.conversations.filter { $0.tool == "Claude" }
            toolDisplayName = "Claude Code"
        default:
            toolDisplayName = "全工具"
        }

        // 2. 时间段判定
        let todayStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let yesterdayStr = String(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400)).prefix(10))
        let d7Start = String(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400 * 6)).prefix(10))
        let d30Start = String(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400 * 29)).prefix(10))

        var rangeStart = todayStr
        var rangeEnd = todayStr
        var isSingleDay = false
        var chartModeHourly = false

        switch periodMode {
        case "today":
            isSingleDay = true
            chartModeHourly = true
            periodDisplayName = "今天 (\(todayStr))"
            rangeStart = todayStr
            rangeEnd = todayStr
            baseConvs = baseConvs.filter { String($0.time.prefix(10)) == todayStr }
        case "yesterday":
            isSingleDay = true
            chartModeHourly = true
            periodDisplayName = "昨天 (\(yesterdayStr))"
            rangeStart = yesterdayStr
            rangeEnd = yesterdayStr
            baseConvs = baseConvs.filter { String($0.time.prefix(10)) == yesterdayStr }
        case "7d":
            periodDisplayName = "近 7 天"
            rangeStart = d7Start
            rangeEnd = todayStr
            baseConvs = baseConvs.filter {
                let d = String($0.time.prefix(10))
                return d >= d7Start && d <= todayStr
            }
        case "30d":
            periodDisplayName = "近 30 天"
            rangeStart = d30Start
            rangeEnd = todayStr
            baseConvs = baseConvs.filter {
                let d = String($0.time.prefix(10))
                return d >= d30Start && d <= todayStr
            }
        case "custom":
            if !customStart.isEmpty && !customEnd.isEmpty {
                var s = customStart
                var e = customEnd
                if s > e { swap(&s, &e) }
                rangeStart = s
                rangeEnd = e
                isSingleDay = (s == e)
                chartModeHourly = isSingleDay
                periodDisplayName = "\(s) ~ \(e)"
                baseConvs = baseConvs.filter {
                    let d = String($0.time.prefix(10))
                    return d >= s && d <= e
                }
            } else {
                periodDisplayName = "自定义区间"
            }
        default: // "all"
            let allD = baseConvs.map { String($0.time.prefix(10)) }
            rangeStart = allD.min() ?? todayStr
            rangeEnd = allD.max() ?? todayStr
            periodDisplayName = "全部历史"
        }

        // 3. 计算聚合指标
        let count = baseConvs.count
        self.periodTokens = baseConvs.reduce(0) { $0 + $1.total }
        self.periodPrompt = baseConvs.reduce(0) { $0 + $1.prompt }
        self.periodOutput = baseConvs.reduce(0) { $0 + $1.output }
        self.periodCached = baseConvs.reduce(0) { $0 + $1.cached }
        self.periodThoughts = baseConvs.reduce(0) { $0 + $1.thoughts }
        self.periodCostUSD = baseConvs.reduce(0.0) { $0 + $1.costUSD }
        self.periodSavedUSD = baseConvs.reduce(0.0) { $0 + $1.savedUSD }

        let totalIn = periodPrompt + periodCached
        self.cacheRate = totalIn > 0 ? (Double(periodCached) / Double(totalIn) * 100.0) : 0.0

        // 4. 同步注入预测引擎
        let periodIncludesToday = (rangeStart <= todayStr && todayStr <= rangeEnd)
        let latestConv = baseConvs.first
        let selectionChanged = predictor.periodName != periodDisplayName ||
            predictor.toolDisplay != toolDisplayName ||
            predictor.periodIncludesToday != periodIncludesToday
        predictor.onPhysicalUpdate(
            summary: res.summary,
            toolsSummary: res.toolsSummary,
            periodTokens: periodTokens,
            periodCostUSD: periodCostUSD,
            count: count,
            toolDisplay: toolDisplayName,
            periodName: periodDisplayName,
            periodIncludesToday: periodIncludesToday,
            latestConv: latestConv,
            allConvs: baseConvs
        )

        // 筛选条件变化时先把卡片切到新范围的真值，下一次预测 tick 再继续外推。
        // 这样切换“昨天/近 7 天”不会短暂甚至持续显示上一个范围。
        if selectionChanged && streamPrediction {
            syncLivePeriodToGround()
        }

        // 行级活跃状态只在物理扫描或筛选变化时更新，不随实时预测频繁广播。
        if self.activeTaskMap != predictor.activeTasks {
            self.activeTaskMap = predictor.activeTasks
        }

        // 实时预测关闭时没有高频定时器，物理扫描完成后直接同步静态真值，
        // 避免顶部指标停留在初始的 0。
        if !streamPrediction {
            syncLiveTelemetryToGround()
        }

        // 5. 关键词过滤列表
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            self.filteredConversations = baseConvs
        } else {
            self.filteredConversations = baseConvs.filter {
                $0.title.lowercased().contains(query) ||
                $0.cid.lowercased().contains(query) ||
                $0.models.lowercased().contains(query) ||
                $0.tool.lowercased().contains(query) ||
                $0.source.lowercased().contains(query)
            }
        }

        // 6. 构造图表点数据
        buildChartPoints(convs: baseConvs, chartModeHourly: chartModeHourly, startStr: rangeStart, endStr: rangeEnd)
    }

    private func syncLivePeriodToGround() {
        publishLiveTelemetry(
            todayTotal: liveTelemetry.displayedTodayTotal,
            todayCostUSD: liveTelemetry.displayedTodayCostUSD,
            periodTotal: periodTokens,
            periodCostUSD: periodCostUSD,
            isActive: liveTelemetry.isGeneratingActive,
            velocity: liveTelemetry.liveVelocity,
            latestTool: liveTelemetry.latestToolName
        )
    }

    // MARK: - 图表数据构建
    private func buildChartPoints(convs: [ConversationItem], chartModeHourly: Bool, startStr: String, endStr: String) {
        var points: [ChartPoint] = []

        if chartModeHourly {
            let sortedConvs = convs.sorted { $0.time < $1.time }
            for c in sortedConvs {
                let parts = c.time.components(separatedBy: " ")
                let label = parts.count > 1 ? String(parts[1].prefix(5)) : c.time
                points.append(ChartPoint(
                    index: points.count,
                    label: label,
                    dateStr: c.time,
                    totalM: Double(c.total) / 1_000_000.0,
                    outputM: Double(c.output) / 1_000_000.0,
                    rawTotal: c.total,
                    rawCostUSD: c.costUSD,
                    rawPrompt: c.prompt,
                    rawOutput: c.output,
                    rawCached: c.cached,
                    title: c.title,
                    tool: c.tool,
                    count: 1
                ))
            }
        } else {
            var dayMap: [String: (total: Int, output: Int, prompt: Int, cached: Int, cost: Double, count: Int)] = [:]
            for c in convs {
                let d = String(c.time.prefix(10))
                var cur = dayMap[d] ?? (0, 0, 0, 0, 0.0, 0)
                cur.total += c.total
                cur.output += c.output
                cur.prompt += c.prompt
                cur.cached += c.cached
                cur.cost += c.costUSD
                cur.count += 1
                dayMap[d] = cur
            }

            for d in dayMap.keys.sorted() {
                let cur = dayMap[d]!
                let label = String(d.suffix(5)) // MM-dd
                points.append(ChartPoint(
                    index: points.count,
                    label: label,
                    dateStr: d,
                    totalM: Double(cur.total) / 1_000_000.0,
                    outputM: Double(cur.output) / 1_000_000.0,
                    rawTotal: cur.total,
                    rawCostUSD: cur.cost,
                    rawPrompt: cur.prompt,
                    rawOutput: cur.output,
                    rawCached: cur.cached,
                    title: "\(cur.count) 个会话",
                    tool: toolDisplayName,
                    count: cur.count
                ))
            }
        }

        self.chartPoints = points

        if let maxPt = points.max(by: { $0.totalM < $1.totalM }) {
            self.chartPeakValM = maxPt.totalM
            self.chartPeakDate = maxPt.dateStr
            self.chartPeakCostUSD = maxPt.rawCostUSD
            let sumM = points.reduce(0.0) { $0 + $1.totalM }
            self.chartAverageM = points.isEmpty ? 0.0 : (sumM / Double(points.count))
        } else {
            self.chartPeakValM = 0.0
            self.chartPeakDate = ""
            self.chartPeakCostUSD = 0.0
            self.chartAverageM = 0.0
        }
    }

    // MARK: - Python 环境解析
    private func resolvePython() -> String? {
        let preferred = "/opt/homebrew/Caskroom/miniconda/base/bin/python3"
        if FileManager.default.isExecutableFile(atPath: preferred) {
            return preferred
        }

        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/miniconda3/bin/python3",
            "\(home)/anaconda3/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                return c
            }
        }
        return "/usr/bin/python3"
    }

    private func resolveScannerScript() -> String? {
        let bundle = Bundle.main
        if let resPath = bundle.resourcePath {
            let p = (resPath as NSString).appendingPathComponent("token_scanner.py")
            if FileManager.default.fileExists(atPath: p) { return p }
        }

        // 本地源码查找 fallback
        let currentDir = FileManager.default.currentDirectoryPath
        let localPath = (currentDir as NSString).appendingPathComponent("token_scanner.py")
        if FileManager.default.fileExists(atPath: localPath) { return localPath }

        let desktopPath = "/Users/silenzio/Desktop/BrewApps/AgyToken/token_scanner.py"
        if FileManager.default.fileExists(atPath: desktopPath) { return desktopPath }

        return nil
    }

    // MARK: - 状态持久化
    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let saved = try? JSONDecoder().decode(AppState.self, from: data) else {
            return
        }

        self.toolMode = saved.toolMode
        self.periodMode = saved.periodMode
        self.customStart = saved.customStart
        self.customEnd = saved.customEnd
        self.showCNY = saved.showCNY
        self.showChart = saved.showChart
        self.autoRefresh = saved.autoRefresh
        self.streamPrediction = saved.streamPrediction
        self.searchQuery = saved.searchQuery
        self.predictor.enabled = saved.streamPrediction
    }

    func saveState() {
        let state = AppState(
            toolMode: self.toolMode,
            periodMode: self.periodMode,
            customStart: self.customStart,
            customEnd: self.customEnd,
            showCNY: self.showCNY,
            showChart: self.showChart,
            autoRefresh: self.autoRefresh,
            streamPrediction: self.streamPrediction,
            searchQuery: self.searchQuery,
            windowGeometry: "1220x840"
        )

        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }
}
