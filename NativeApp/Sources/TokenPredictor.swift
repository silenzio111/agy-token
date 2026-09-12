import Foundation

// MARK: - 活跃任务状态结构体
struct ActiveTaskState: Hashable {
    let cid: String
    var totalGround: Int
    var totalPred: Double
    var outputGround: Int
    var outputPred: Double
    var costGround: Double
    var costPred: Double
    var velocity: Double
    var catchupVelocity: Double
    var rate: Double
    var mtime: Double
    var lastUpdate: Double
    var isActive: Bool
}

// MARK: - 低频流式预测引擎 (500ms Micro-Tick Extrapolator)
final class TokenPredictor {
    var enabled: Bool = true
    private var lastScanTime: Double = 0.0
    private let maxCatchupVelocity: Double = 280.0

    // 今日真值与外推预测值
    private(set) var todayTotalGround: Int = 0
    private(set) var todayCostGround: Double = 0.0
    var todayTotalPred: Double = 0.0
    var todayCostPred: Double = 0.0

    // 所选周期真值与预测值
    private(set) var periodTotalGround: Int = 0
    private(set) var periodCostGround: Double = 0.0
    var periodTotalPred: Double = 0.0
    var periodCostPred: Double = 0.0
    var periodIncludesToday: Bool = true

    // 活跃度与燃烧速率估计 (EMA)
    private(set) var latestMtime: Double = 0.0
    private(set) var latestTool: String = "AI"
    var velocity: Double = 0.0            // Tokens / 秒
    var catchupVelocity: Double = 0.0     // 残差平滑吸收速率 (Tokens / 秒)
    var isActive: Bool = false
    var avgCostRate: Double = 2.5         // 美元 / 1M tokens

    // 活跃任务字典: cid -> ActiveTaskState
    var activeTasks: [String: ActiveTaskState] = [:]

    // 辅助展示缓存
    var count: Int = 0
    var toolDisplay: String = "全工具"
    var periodName: String = "今天"
    var agyT: Int = 0
    var codexT: Int = 0
    var claudeT: Int = 0

    func onPhysicalUpdate(
        summary: OverallSummary,
        toolsSummary: [String: ToolSummaryItem],
        periodTokens: Int,
        periodCostUSD: Double,
        count: Int,
        toolDisplay: String,
        periodName: String,
        periodIncludesToday: Bool,
        latestConv: ConversationItem?,
        allConvs: [ConversationItem]
    ) {
        let now = Date().timeIntervalSince1970
        let selectionChanged = self.periodName != periodName ||
            self.toolDisplay != toolDisplay ||
            self.periodIncludesToday != periodIncludesToday

        self.periodIncludesToday = periodIncludesToday
        self.count = count
        self.toolDisplay = toolDisplay
        self.periodName = periodName
        self.agyT = toolsSummary["Antigravity"]?.todayTotal ?? 0
        self.codexT = toolsSummary["Codex"]?.todayTotal ?? 0
        self.claudeT = toolsSummary["Claude"]?.todayTotal ?? 0

        let actualTodayTotal = summary.todayTotal
        let actualTodayCost = summary.todayCostUSD

        if let latest = latestConv {
            self.latestMtime = latest.mtime
            self.latestTool = latest.tool
            if latest.total > 0 && latest.costUSD > 0 {
                self.avgCostRate = max(0.2, (latest.costUSD / Double(latest.total)) * 1_000_000.0)
            }
        }

        let idleSeconds = self.latestMtime > 0 ? max(0.0, now - self.latestMtime) : 999.0
        self.isActive = (idleSeconds < 45.0)

        // EMA 燃烧流速估计
        if self.lastScanTime > 0 && (now - self.lastScanTime) > 1.0 {
            let dt = now - self.lastScanTime
            let deltaTokens = actualTodayTotal - self.todayTotalGround
            if deltaTokens > 0 {
                let vObs = Double(deltaTokens) / dt
                let vClamped = max(15.0, min(280.0, vObs))
                if self.velocity <= 1.0 {
                    self.velocity = vClamped
                } else {
                    self.velocity = 0.65 * vClamped + 0.35 * self.velocity
                }
            } else if idleSeconds > 25.0 {
                self.velocity *= 0.5
            }
        } else if self.velocity == 0.0 && self.isActive {
            self.velocity = 55.0
        }

        self.lastScanTime = now
        self.todayTotalGround = actualTodayTotal
        self.todayCostGround = actualTodayCost
        self.periodTotalGround = periodTokens
        self.periodCostGround = periodCostUSD

        // 首次更新直接对齐
        if self.todayTotalPred == 0.0 {
            self.todayTotalPred = Double(actualTodayTotal)
            self.todayCostPred = actualTodayCost
            self.periodTotalPred = Double(periodTokens)
            self.periodCostPred = periodCostUSD
        } else {
            // 残差平滑校准 (严禁倒退)
            let todayError = Double(actualTodayTotal) - self.todayTotalPred
            if todayError > 0 {
                self.catchupVelocity = min(maxCatchupVelocity, todayError / 1.5)
            } else {
                self.catchupVelocity = 0.0
                self.velocity = max(0.0, self.velocity * 0.5)
            }

            if selectionChanged {
                // 切换工具或时期后，旧选择的预测总量不能继续沿用，
                // 否则卡片会显示上一个时期的 Token 数。
                self.periodTotalPred = Double(periodTokens)
                self.periodCostPred = periodCostUSD
            } else if !self.periodIncludesToday {
                self.periodTotalPred = Double(periodTokens)
                self.periodCostPred = periodCostUSD
            }
        }

        // 更新具体活跃任务列表 (45 秒内有活动的会话)
        for c in allConvs.prefix(15) {
            guard !c.cid.isEmpty else { continue }
            let cIdle = max(0.0, now - c.mtime)
            if cIdle < 45.0 {
                let cTot = c.total
                let cOut = c.output
                let cCost = c.costUSD
                let cRate = (cTot > 0 && cCost > 0) ? (cCost / Double(cTot) * 1_000_000.0) : self.avgCostRate

                if var task = self.activeTasks[c.cid] {
                    let dTok = cTot - task.totalGround
                    var tV = task.velocity
                    if dTok > 0 {
                        let dt = max(1.0, now - task.lastUpdate)
                        let vObs = Double(dTok) / dt
                        tV = 0.65 * max(15.0, min(250.0, vObs)) + 0.35 * tV
                    } else if cIdle > 25.0 {
                        tV *= 0.5
                    }

                    let err = Double(cTot) - task.totalPred
                    let catchup = err > 0 ? min(maxCatchupVelocity, err / 1.5) : 0.0
                    if err <= 0 {
                        tV = max(0.0, tV * 0.5)
                    }

                    task.totalGround = cTot
                    task.outputGround = cOut
                    task.costGround = cCost
                    task.velocity = tV
                    task.catchupVelocity = catchup
                    task.rate = cRate
                    task.mtime = c.mtime
                    task.lastUpdate = now
                    task.isActive = true
                    self.activeTasks[c.cid] = task
                } else {
                    self.activeTasks[c.cid] = ActiveTaskState(
                        cid: c.cid,
                        totalGround: cTot,
                        totalPred: Double(cTot),
                        outputGround: cOut,
                        outputPred: Double(cOut),
                        costGround: cCost,
                        costPred: cCost,
                        velocity: max(35.0, self.velocity),
                        catchupVelocity: 0.0,
                        rate: cRate,
                        mtime: c.mtime,
                        lastUpdate: now,
                        isActive: true
                    )
                }
            }
        }

        // 清理超时任务 (> 60 秒无更新)
        let expiredKeys = self.activeTasks.keys.filter { (now - (self.activeTasks[$0]?.mtime ?? 0)) > 60.0 }
        for k in expiredKeys {
            self.activeTasks.removeValue(forKey: k)
        }
    }

    func tick(dt: Double = 0.1) -> (isActive: Bool, effectiveVelocity: Double) {
        guard self.enabled && self.todayTotalGround > 0 else {
            return (false, 0.0)
        }

        let now = Date().timeIntervalSince1970
        let idleSeconds = self.latestMtime > 0 ? max(0.0, now - self.latestMtime) : 999.0
        self.isActive = (idleSeconds < 45.0)

        if !self.isActive {
            self.velocity *= 0.88
            if self.velocity < 1.0 {
                self.velocity = 0.0
            }
        }

        var effectiveV = self.velocity + self.catchupVelocity
        if self.catchupVelocity > 0 {
            self.catchupVelocity = max(0.0, self.catchupVelocity - (self.catchupVelocity * 0.6 * dt))
        }

        if !self.isActive && self.todayTotalPred >= Double(self.todayTotalGround) {
            self.todayTotalPred = Double(self.todayTotalGround)
            self.todayCostPred = self.todayCostGround
            effectiveV = 0.0
        }

        let deltaT = effectiveV * dt
        let deltaC = (deltaT / 1_000_000.0) * self.avgCostRate

        self.todayTotalPred += deltaT
        self.todayCostPred += deltaC

        if self.periodIncludesToday {
            self.periodTotalPred += deltaT
            self.periodCostPred += deltaC
        }

        // 推进各个具体任务的高频微步外推
        for (cid, var task) in self.activeTasks {
            let tIdle = max(0.0, now - task.mtime)
            task.isActive = (tIdle < 45.0)
            if !task.isActive {
                task.velocity *= 0.88
                if task.velocity < 1.0 {
                    task.velocity = 0.0
                }
            }

            var tEffV = task.velocity + task.catchupVelocity
            if task.catchupVelocity > 0 {
                task.catchupVelocity = max(0.0, task.catchupVelocity - (task.catchupVelocity * 0.6 * dt))
            }

            if !task.isActive && task.totalPred >= Double(task.totalGround) {
                task.totalPred = Double(task.totalGround)
                task.outputPred = Double(task.outputGround)
                task.costPred = task.costGround
                tEffV = 0.0
            }

            let tDelta = tEffV * dt
            task.totalPred += tDelta
            task.outputPred += tDelta
            task.costPred += (tDelta / 1_000_000.0) * task.rate
            self.activeTasks[cid] = task
        }

        return (self.isActive, effectiveV)
    }
}
