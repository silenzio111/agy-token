import Foundation
import Combine

// 高频实时数据显示单独放在对象中，避免顶部数字变化时让图表和历史表格
// 一起重新计算。它只负责小范围的实时遥测，不保存扫描结果。
@MainActor
final class LiveTelemetry: ObservableObject {
    @Published var displayedTodayTotal: Int = 0
    @Published var displayedTodayCostUSD: Double = 0.0
    @Published var displayedPeriodTotal: Int = 0
    @Published var displayedPeriodCostUSD: Double = 0.0
    @Published var isGeneratingActive: Bool = false
    @Published var liveVelocity: Double = 0.0
    @Published var latestToolName: String = "AI"
}
