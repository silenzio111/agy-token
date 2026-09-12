import SwiftUI
import Charts
import Combine

final class ChartHoverState: ObservableObject {
    @Published var selectedChartPoint: ChartPoint?
}

struct TokenTrendChartView: View {
    @ObservedObject var vm: AgyTokenViewModel
    @StateObject private var hoverState = ChartHoverState()

    // 使用数值索引作为 X 轴，避免 Swift Charts 把字符串分类轴的所有值
    // 都自动绘制出来。全历史最多展示 8 个日期标签，短区间则展示全部。
    private var sampledXAxisIndices: [Int] {
        let count = vm.chartPoints.count
        guard count > 8 else {
            return Array(0..<count)
        }

        let targetIntervals = 7
        let step = max(1, Int(ceil(Double(count - 1) / Double(targetIntervals))))
        var sampled = Array(stride(from: 0, through: count - 1, by: step))
        if sampled.last != count - 1 {
            sampled.append(count - 1)
        }
        return sampled
    }

    private var chartYAxisUpperBound: Double {
        // 给最高峰留出少量顶部空间，同时避免自动坐标把普通波动压扁。
        max(1.0, vm.chartPeakValM * 1.12)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            topInfoBar

            Divider()
                .background(Color.black.opacity(0.06))

            // 图表主体与悬浮浮层
            ZStack(alignment: .topLeading) {
                if vm.chartPoints.isEmpty {
                    emptyPlaceholder
                } else {
                    chartCanvas
                }
            }
        }
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - 顶部信息摘要栏
    private var topInfoBar: some View {
        HStack {
            HStack(spacing: 12) {
                if !vm.chartPeakDate.isEmpty {
                    Text("🏆 最高峰: \(vm.chartPeakDate) (\(String(format: "%.2f", vm.chartPeakValM))M · \(Formatters.formatMoney(usd: vm.chartPeakCostUSD, showCNY: vm.showCNY)))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)

                    Text("|")
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("📊 时期均值: \(String(format: "%.2f", vm.chartAverageM))M / 时段")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("📈 走势图表")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                    Text("总消耗").font(.system(size: 10)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color(red: 0.1, green: 0.6, blue: 0.3)).frame(width: 7, height: 7)
                    Text("实际生成").font(.system(size: 10)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.orange).frame(width: 10, height: 1)
                    Text("时期均值").font(.system(size: 10)).foregroundColor(.secondary)
                }
                Text("[鼠标悬停查看详情]")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - 空状态提示
    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.3))
            Text("当前筛选范围内暂无 Token 数据")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 核心图表
    private var chartCanvas: some View {
        let hasOutput = vm.chartPoints.contains { $0.outputM > 0.01 }

        return Chart {
            ForEach(vm.chartPoints) { pt in
                // 1. 面积填充
                AreaMark(
                    x: .value("时间", pt.index),
                    y: .value("总消耗 (M)", pt.totalM)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.18),
                            Color.blue.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 2. 总消耗主曲线
                LineMark(
                    x: .value("时间", pt.index),
                    y: .value("总消耗 (M)", pt.totalM)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.2))

                // 3. 输出曲线
                if hasOutput && pt.outputM > 0.005 {
                    LineMark(
                        x: .value("时间", pt.index),
                        y: .value("输出 (M)", pt.outputM)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color(red: 0.1, green: 0.6, blue: 0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }

                // 4. 数据小圆点 (少于14个点时展示)
                if vm.chartPoints.count <= 14 {
                    PointMark(
                        x: .value("时间", pt.index),
                        y: .value("总消耗 (M)", pt.totalM)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(20)
                }
            }

            // 均值虚线
            if vm.chartAverageM > 0.05 {
                RuleMark(y: .value("均值", vm.chartAverageM))
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [5, 4]))
            }

            // 鼠标悬停竖线
            if let sel = hoverState.selectedChartPoint {
                RuleMark(x: .value("选中", sel.index))
                    .foregroundStyle(Color.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            }
        }
        .chartXScale(domain: 0...max(1, vm.chartPoints.count - 1))
        .chartYScale(domain: 0...chartYAxisUpperBound)
        .chartYAxis {
            AxisMarks(position: .leading) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let d = val.as(Double.self) {
                        Text(String(format: "%.1fM", d))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: sampledXAxisIndices) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let index = val.as(Int.self),
                       let point = vm.chartPoints.first(where: { $0.index == index }) {
                        Text(point.label)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 170)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let index: Int = proxy.value(atX: location.x) {
                                    let point = vm.chartPoints.first(where: { $0.index == index })
                                    if hoverState.selectedChartPoint?.index != point?.index {
                                        hoverState.selectedChartPoint = point
                                    }
                                }
                            case .ended:
                                hoverState.selectedChartPoint = nil
                            }
                        }

                    if let point = hoverState.selectedChartPoint,
                       let xPosition = proxy.position(forX: point.index) {
                        ChartTooltipView(pt: point, showCNY: vm.showCNY)
                            .offset(x: tooltipLeading(xPosition: xPosition, chartWidth: geo.size.width), y: 8)
                            .allowsHitTesting(false)
                        }
                }
            }
        }
    }

    private func tooltipLeading(xPosition: CGFloat, chartWidth: CGFloat) -> CGFloat {
        let tooltipWidth: CGFloat = 230
        let margin: CGFloat = 8
        let maxLeading = max(margin, chartWidth - tooltipWidth - margin)
        return min(max(margin, xPosition - tooltipWidth / 2), maxLeading)
    }
}

// MARK: - 悬浮交互信息卡片
struct ChartTooltipView: View {
    let pt: ChartPoint
    let showCNY: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("📅 \(pt.dateStr)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.blue)
                Spacer()
                Text("[\(pt.tool)]")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Divider()
                .padding(.vertical, 1)

            HStack {
                Text("总消耗:")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Formatters.formatIntWithComma(pt.rawTotal)) (\(String(format: "%.2f", pt.totalM))M)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            HStack {
                Text("预估费用:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(Formatters.formatMoney(usd: pt.rawCostUSD, showCNY: showCNY))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.05))
            }

            HStack {
                Text("未缓存输入:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(Formatters.formatShort(pt.rawPrompt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("实际生成输出:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(Formatters.formatShort(pt.rawOutput))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.1, green: 0.6, blue: 0.3))
            }

            HStack {
                Text("Prompt 缓存:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(Formatters.formatShort(pt.rawCached))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if !pt.title.isEmpty {
                Text("💬 \(pt.title)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .font(.system(size: 10))
        .padding(10)
        .frame(width: 230)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
    }
}
