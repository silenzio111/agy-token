import SwiftUI

struct HeaderView: View {
    @ObservedObject var vm: AgyTokenViewModel
    @ObservedObject var live: LiveTelemetry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // 1. 左侧：应用标题与状态徽标 (绝对锁定单行，禁止折行)
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue)

                Text("AgyToken")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize()

                Text("v3.0")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.08))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                    .fixedSize()

                // 实时活跃指示徽标
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)

                    Text(statusTitle)
                        .font(.system(size: 10, weight: .medium, design: statusUsesMonospacedFont ? .monospaced : .default))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
                .fixedSize()
            }

            Spacer()

            // 2. 中间：今日最新遥测数据胶囊 (紧凑横向卡片，严禁折行)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("今日消耗:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(Formatters.formatShort(live.displayedTodayTotal))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .contentTransition(.numericText())
                }

                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Text("今日费用:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(Formatters.formatMoney(usd: live.displayedTodayCostUSD, showCNY: vm.showCNY))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.05))
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)

            Spacer()

            // 3. 右侧：工具箱操作按钮组 (每个按钮绝对单行，禁止挤压竖排)
            HStack(spacing: 6) {
                // 走势图切换
                HeaderToolButton(
                    icon: "chart.xyaxis.line",
                    title: "走势图",
                    isActive: vm.showChart,
                    activeColor: .blue
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.showChart.toggle()
                    }
                }

                // 汇率切换
                Button {
                    vm.showCNY.toggle()
                } label: {
                    Text(vm.showCNY ? "¥ CNY" : "$ USD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10))
                        .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .fixedSize()

                // 实时预测开关
                HeaderToolButton(
                    icon: "bolt.fill",
                    title: vm.streamPrediction ? "预测 开" : "预测 关",
                    isActive: vm.streamPrediction,
                    activeColor: .blue
                ) {
                    vm.streamPrediction.toggle()
                }

                // 自动刷新开关
                HeaderToolButton(
                    icon: "arrow.triangle.2.circlepath",
                    title: vm.autoRefresh ? "自动 30s" : "自动关",
                    isActive: vm.autoRefresh,
                    activeColor: Color(red: 0.1, green: 0.6, blue: 0.3)
                ) {
                    vm.autoRefresh.toggle()
                }

                // 立即刷新
                Button {
                    Task { await vm.runScan(silent: false) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(vm.isLoading ? .degrees(360) : .degrees(0))
                            .animation(vm.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isLoading)
                        Text(vm.isLoading ? "扫描中" : "刷新")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var statusTitle: String {
        if vm.isLoading {
            return "扫描中"
        }
        if !vm.streamPrediction {
            return "预测关闭"
        }
        if live.isGeneratingActive && live.liveVelocity > 1.0 {
            return String(format: "LIVE +%d tok/s · %@", Int(live.liveVelocity), live.latestToolName)
        }
        return "待命"
    }

    private var statusColor: Color {
        if vm.isLoading {
            return .orange
        }
        if live.isGeneratingActive && vm.streamPrediction {
            return Color(red: 0.1, green: 0.6, blue: 0.2)
        }
        return .secondary
    }

    private var statusUsesMonospacedFont: Bool {
        live.isGeneratingActive && vm.streamPrediction && live.liveVelocity > 1.0
    }
}

// 辅助子组件：顶部白底防挤压按钮
struct HeaderToolButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    var activeColor: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isActive ? activeColor.opacity(0.10) : Color.white)
            .foregroundColor(isActive ? activeColor : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? activeColor.opacity(0.3) : Color.black.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
