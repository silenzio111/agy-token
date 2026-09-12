import SwiftUI

struct MetricCardsView: View {
    @ObservedObject var vm: AgyTokenViewModel
    @ObservedObject var live: LiveTelemetry

    var body: some View {
        HStack(spacing: 12) {
            // 卡片 1: 所选时期消耗 (Tokens)
            MetricCardView(
                iconName: "sparkles",
                title: "所选时期总消耗",
                mainValue: Formatters.formatShort(live.displayedPeriodTotal),
                subValue: "共 \(vm.filteredConversations.count) 个会话 · 精确: \(Formatters.formatIntWithComma(live.displayedPeriodTotal))",
                valueColor: .blue,
                isNumberTicker: true
            )

            // 卡片 2: 预估费用
            MetricCardView(
                iconName: "dollarsign.circle.fill",
                title: "所选时期预估费用",
                mainValue: Formatters.formatMoney(usd: live.displayedPeriodCostUSD, showCNY: vm.showCNY),
                subValue: "Prompt 缓存省下: \(Formatters.formatMoney(usd: vm.periodSavedUSD, showCNY: vm.showCNY))",
                valueColor: Color(red: 0.85, green: 0.35, blue: 0.05),
                isNumberTicker: true
            )

            // 卡片 3: 输入/输出分布
            MetricCardView(
                iconName: "arrow.left.arrow.right",
                title: "输入 / 输出分布",
                mainValue: "入: \(Formatters.formatShort(vm.periodPrompt))  出: \(Formatters.formatShort(vm.periodOutput))",
                subValue: "深度思考推理: \(Formatters.formatShort(vm.periodThoughts)) Tokens",
                valueColor: .primary,
                isNumberTicker: false
            )

            // 卡片 4: Prompt 缓存率 (内嵌原生动态进度条)
            MetricCardView(
                iconName: "bolt.horizontal.fill",
                title: "Prompt 缓存率",
                mainValue: String(format: "%.1f %%", vm.cacheRate),
                subValue: "命中缓存 \(Formatters.formatShort(vm.periodCached)) Tokens",
                valueColor: Color(red: 0.1, green: 0.6, blue: 0.3),
                isNumberTicker: false,
                progressValue: vm.cacheRate
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - 单个指标卡片组件 (纯白底精致 macOS 风格)
struct MetricCardView: View {
    let iconName: String
    let title: String
    let mainValue: String
    let subValue: String
    let valueColor: Color
    var isNumberTicker: Bool = false
    var progressValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题行
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()
            }

            // 主数值 (支持数字翻滚动效)
            Text(mainValue)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .modify { view in
                    if isNumberTicker {
                        view.contentTransition(.numericText())
                    } else {
                        view
                    }
                }

            // 辅助副标题
            Text(subValue)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            // 进度条
            if let progress = progressValue {
                ProgressView(value: min(100.0, max(0.0, progress)), total: 100.0)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.1, green: 0.6, blue: 0.3))
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
    }
}

extension View {
    func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}
