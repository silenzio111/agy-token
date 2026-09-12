import SwiftUI
import AppKit

// MARK: - 主窗口内容视图 (纯正 macOS 白底原生设计)
struct MainContentView: View {
    @ObservedObject var vm: AgyTokenViewModel

    var body: some View {
        VStack(spacing: 10) {
            // 1. 顶部 Header 与 实时遥测数据卡片
            HeaderView(vm: vm, live: vm.liveTelemetry)

            // 2. 筛选器栏 (工具分段 + 时间段分段 + 搜索框)
            FilterBarView(vm: vm)

            // 3. 核心统计卡片组 (4 大指标纯白卡片，支持数字物理滚动)
            MetricCardsView(vm: vm, live: vm.liveTelemetry)

            // 4. 趋势图表区 (纯白底 Swift Charts，折叠展开动画)
            if vm.showChart {
                TokenTrendChartView(vm: vm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 5. 详细会话表格 (经典 macOS 原生表头与虚拟化白底行)
            ConversationTableView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 6. 底部状态栏单独观察实时状态，避免实时数字让整个页面重算。
            StatusBarView(vm: vm, live: vm.liveTelemetry)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.light) // 严格指定白底浅色主题
        .animation(.easeInOut(duration: 0.2), value: vm.showChart)
    }
}

struct StatusBarView: View {
    @ObservedObject var vm: AgyTokenViewModel
    @ObservedObject var live: LiveTelemetry

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.isLoading ? Color.orange : (live.isGeneratingActive ? Color.green : Color.secondary.opacity(0.5)))
                    .frame(width: 7, height: 7)

                Text(vm.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if vm.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                if let summary = vm.scanResult?.summary {
                    Text("汇率: 1 USD = \(String(format: "%.2f", summary.usdToCnyRate)) CNY")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if let latestTime = vm.scanResult?.conversations.first?.time {
                    Text("最新日志: \(latestTime)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text("显示 \(vm.filteredConversations.count) / \(vm.scanResult?.conversations.count ?? 0) 会话")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("最近扫描: \(vm.lastSyncTime)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - 应用程序入口
@main
struct AgyTokenApp: App {
    @StateObject private var vm = AgyTokenViewModel()

    var body: some Scene {
        WindowGroup {
            MainContentView(vm: vm)
                .frame(minWidth: 1140, minHeight: 720)
                .sheet(isPresented: $vm.showingDetailSheet) {
                    if let conv = vm.selectedConversation {
                        ConversationDetailSheet(
                            conversation: conv,
                            showCNY: vm.showCNY,
                            onDismiss: {
                                vm.showingDetailSheet = false
                                vm.selectedConversation = nil
                            }
                        )
                        .preferredColorScheme(.light)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("监控与控制") {
                Button("立即扫描刷新") {
                    Task { await vm.runScan(silent: false) }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Toggle("自动后台轮询 (30秒物理扫描)", isOn: $vm.autoRefresh)
                Toggle("实时微步预测引擎 (500ms微步外推)", isOn: $vm.streamPrediction)
                Toggle("人民币计价 (CNY)", isOn: $vm.showCNY)
                Toggle("显示时段走势图表", isOn: $vm.showChart)
            }
        }
    }
}
