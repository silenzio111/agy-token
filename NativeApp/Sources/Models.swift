import Foundation

// MARK: - 基础单价信息
struct RatesInfo: Codable, Hashable {
    let `in`: Double
    let out: Double
    let cache: Double
    let matched: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.in = try container.decodeIfPresent(Double.self, forKey: .in) ?? 0.0
        self.out = try container.decodeIfPresent(Double.self, forKey: .out) ?? 0.0
        self.cache = try container.decodeIfPresent(Double.self, forKey: .cache) ?? 0.0
        self.matched = try container.decodeIfPresent(String.self, forKey: .matched) ?? "默认模型"
    }

    enum CodingKeys: String, CodingKey {
        case `in`, out, cache, matched
    }
}

// MARK: - 单个会话详情模型
struct ConversationItem: Codable, Identifiable, Hashable {
    var id: String { cid }
    let cid: String
    let tool: String
    let source: String
    let time: String
    let mtime: Double
    let isToday: Bool
    let turns: Int
    let prompt: Int
    let output: Int
    let cached: Int
    let thoughts: Int
    let total: Int
    let costUSD: Double
    let savedUSD: Double
    let models: String
    let title: String
    let rates: RatesInfo?

    enum CodingKeys: String, CodingKey {
        case cid, tool, source, time, mtime
        case isToday = "is_today"
        case turns, prompt, output, cached, thoughts, total
        case costUSD = "cost_usd"
        case savedUSD = "saved_usd"
        case models, title, rates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.cid = try c.decodeIfPresent(String.self, forKey: .cid) ?? UUID().uuidString
        self.tool = try c.decodeIfPresent(String.self, forKey: .tool) ?? "AI"
        self.source = try c.decodeIfPresent(String.self, forKey: .source) ?? "AI"
        self.time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        self.mtime = try c.decodeIfPresent(Double.self, forKey: .mtime) ?? 0.0
        self.isToday = try c.decodeIfPresent(Bool.self, forKey: .isToday) ?? false
        self.turns = try c.decodeIfPresent(Int.self, forKey: .turns) ?? 1
        self.prompt = try c.decodeIfPresent(Int.self, forKey: .prompt) ?? 0
        self.output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        self.cached = try c.decodeIfPresent(Int.self, forKey: .cached) ?? 0
        self.thoughts = try c.decodeIfPresent(Int.self, forKey: .thoughts) ?? 0
        self.total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0.0
        self.savedUSD = try c.decodeIfPresent(Double.self, forKey: .savedUSD) ?? 0.0
        self.models = try c.decodeIfPresent(String.self, forKey: .models) ?? ""
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? "未命名任务"
        self.rates = try c.decodeIfPresent(RatesInfo.self, forKey: .rates)
    }
}

// MARK: - 工具来源细分汇总
struct ToolSummaryItem: Codable, Hashable {
    let total: Int
    let costUSD: Double
    let count: Int
    let todayTotal: Int
    let todayCostUSD: Double
    let todayCount: Int

    enum CodingKeys: String, CodingKey {
        case total
        case costUSD = "cost_usd"
        case count
        case todayTotal = "today_total"
        case todayCostUSD = "today_cost_usd"
        case todayCount = "today_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0.0
        self.count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.todayTotal = try c.decodeIfPresent(Int.self, forKey: .todayTotal) ?? 0
        self.todayCostUSD = try c.decodeIfPresent(Double.self, forKey: .todayCostUSD) ?? 0.0
        self.todayCount = try c.decodeIfPresent(Int.self, forKey: .todayCount) ?? 0
    }
}

// MARK: - 全局汇总模型
struct OverallSummary: Codable, Hashable {
    let grandTotal: Int
    let grandPrompt: Int
    let grandOutput: Int
    let grandCached: Int
    let grandThoughts: Int
    let grandCostUSD: Double
    let grandSavedUSD: Double
    let todayTotal: Int
    let todayPrompt: Int
    let todayOutput: Int
    let todayCached: Int
    let todayThoughts: Int
    let todayCostUSD: Double
    let todayConvCount: Int
    let totalConvCount: Int
    let usdToCnyRate: Double

    enum CodingKeys: String, CodingKey {
        case grandTotal = "grand_total"
        case grandPrompt = "grand_prompt"
        case grandOutput = "grand_output"
        case grandCached = "grand_cached"
        case grandThoughts = "grand_thoughts"
        case grandCostUSD = "grand_cost_usd"
        case grandSavedUSD = "grand_saved_usd"
        case todayTotal = "today_total"
        case todayPrompt = "today_prompt"
        case todayOutput = "today_output"
        case todayCached = "today_cached"
        case todayThoughts = "today_thoughts"
        case todayCostUSD = "today_cost_usd"
        case todayConvCount = "today_conv_count"
        case totalConvCount = "total_conv_count"
        case usdToCnyRate = "usd_to_cny_rate"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.grandTotal = try c.decodeIfPresent(Int.self, forKey: .grandTotal) ?? 0
        self.grandPrompt = try c.decodeIfPresent(Int.self, forKey: .grandPrompt) ?? 0
        self.grandOutput = try c.decodeIfPresent(Int.self, forKey: .grandOutput) ?? 0
        self.grandCached = try c.decodeIfPresent(Int.self, forKey: .grandCached) ?? 0
        self.grandThoughts = try c.decodeIfPresent(Int.self, forKey: .grandThoughts) ?? 0
        self.grandCostUSD = try c.decodeIfPresent(Double.self, forKey: .grandCostUSD) ?? 0.0
        self.grandSavedUSD = try c.decodeIfPresent(Double.self, forKey: .grandSavedUSD) ?? 0.0
        self.todayTotal = try c.decodeIfPresent(Int.self, forKey: .todayTotal) ?? 0
        self.todayPrompt = try c.decodeIfPresent(Int.self, forKey: .todayPrompt) ?? 0
        self.todayOutput = try c.decodeIfPresent(Int.self, forKey: .todayOutput) ?? 0
        self.todayCached = try c.decodeIfPresent(Int.self, forKey: .todayCached) ?? 0
        self.todayThoughts = try c.decodeIfPresent(Int.self, forKey: .todayThoughts) ?? 0
        self.todayCostUSD = try c.decodeIfPresent(Double.self, forKey: .todayCostUSD) ?? 0.0
        self.todayConvCount = try c.decodeIfPresent(Int.self, forKey: .todayConvCount) ?? 0
        self.totalConvCount = try c.decodeIfPresent(Int.self, forKey: .totalConvCount) ?? 0
        self.usdToCnyRate = try c.decodeIfPresent(Double.self, forKey: .usdToCnyRate) ?? 7.2
    }
}

// MARK: - 扫描根返回结果
struct ScanResult: Codable {
    let summary: OverallSummary
    let toolsSummary: [String: ToolSummaryItem]
    let conversations: [ConversationItem]

    enum CodingKeys: String, CodingKey {
        case summary
        case toolsSummary = "tools_summary"
        case conversations
    }
}

// MARK: - 图表数据点模型
struct ChartPoint: Identifiable, Hashable {
    let index: Int
    var id: String { "\(index)-\(dateStr)" }
    let label: String
    let dateStr: String
    let totalM: Double
    let outputM: Double
    let rawTotal: Int
    let rawCostUSD: Double
    let rawPrompt: Int
    let rawOutput: Int
    let rawCached: Int
    let title: String
    let tool: String
    let count: Int
}

// MARK: - 应用持久化状态
struct AppState: Codable {
    var toolMode: String = "all"
    var periodMode: String = "today"
    var customStart: String = ""
    var customEnd: String = ""
    var showCNY: Bool = true
    var showChart: Bool = true
    var autoRefresh: Bool = true
    var streamPrediction: Bool = true
    var searchQuery: String = ""
    var windowGeometry: String = "1220x840"

    enum CodingKeys: String, CodingKey {
        case toolMode = "tool_mode"
        case periodMode = "period_mode"
        case customStart = "custom_start"
        case customEnd = "custom_end"
        case showCNY = "show_cny"
        case showChart = "show_chart"
        case autoRefresh = "auto_refresh"
        case streamPrediction = "stream_prediction"
        case searchQuery = "search_query"
        case windowGeometry = "window_geometry"
    }
}

// MARK: - 格式化辅助工具
enum Formatters {
    static func formatShort(_ n: Int) -> String {
        if n >= 1_000_000_000 {
            return String(format: "%.2f B", Double(n) / 1_000_000_000.0)
        } else if n >= 1_000_000 {
            return String(format: "%.2f M", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1f K", Double(n) / 1_000.0)
        }
        return "\(n)"
    }

    static func formatIntWithComma(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatMoney(usd: Double, showCNY: Bool) -> String {
        if showCNY {
            let cny = usd * 7.2
            if cny >= 100 {
                return String(format: "¥ %.2f", cny)
            } else if cny >= 1 {
                return String(format: "¥ %.2f", cny)
            } else {
                return String(format: "¥ %.3f", cny)
            }
        } else {
            if usd >= 100 {
                return String(format: "$ %.2f", usd)
            } else if usd >= 1 {
                return String(format: "$ %.2f", usd)
            } else {
                return String(format: "$ %.4f", usd)
            }
        }
    }
}
