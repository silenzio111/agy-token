import SwiftUI

struct ConversationTableView: View {
    @ObservedObject var vm: AgyTokenViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头行 (Sticky Header - 经典 macOS 原生浅灰表头)
            HStack(spacing: 0) {
                HeaderCell(title: "更新时间", width: 125, alignment: .center)
                HeaderCell(title: "来源", width: 75, alignment: .center)
                HeaderCell(title: "预估费用", width: 95, alignment: .trailing)
                HeaderCell(title: "总消耗 Token", width: 110, alignment: .trailing)
                HeaderCell(title: "输入 (Prompt)", width: 95, alignment: .trailing)
                HeaderCell(title: "输出 (Ans)", width: 85, alignment: .trailing)
                HeaderCell(title: "缓存 (Cache)", width: 90, alignment: .trailing)
                HeaderCell(title: "轮次", width: 50, alignment: .center)
                HeaderCell(title: "模型", width: 120, alignment: .center)
                HeaderCell(title: "会话提问内容 / 任务概要", width: nil, alignment: .leading)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()
                .background(Color(nsColor: .separatorColor))

            // 表格主体行 (高性能 LazyVStack 虚拟滚动)
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 直接遍历索引，避免每次 ViewModel 更新都复制整份会话数组。
                    ForEach(vm.filteredConversations.indices, id: \.self) { idx in
                        let c = vm.filteredConversations[idx]
                        ConversationRowView(
                            index: idx,
                            conversation: c,
                            activeState: vm.activeTaskMap[c.cid],
                            showCNY: vm.showCNY,
                            onDoubleTap: {
                                vm.selectedConversation = c
                                vm.showingDetailSheet = true
                            }
                        )

                        Divider()
                            .background(Color.black.opacity(0.04))
                    }
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
}

// 辅助子组件：表头单元格
struct HeaderCell: View {
    let title: String
    var width: CGFloat? = nil
    var alignment: Alignment = .leading

    var body: some View {
        Group {
            if let w = width {
                Text(title)
                    .frame(width: w, alignment: alignment)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
}

final class RowHoverState: ObservableObject {
    @Published var isHovered: Bool = false
}

// MARK: - 单行组件 (纯白底 / 极浅交替斑马纹 / 活跃生成态高亮)
struct ConversationRowView: View {
    let index: Int
    let conversation: ConversationItem
    let activeState: ActiveTaskState?
    let showCNY: Bool
    let onDoubleTap: () -> Void

    @StateObject private var hover = RowHoverState()

    var isActive: Bool {
        activeState?.isActive == true && (activeState?.velocity ?? 0) > 1.0
    }

    var displayTotal: Int {
        if let st = activeState, isActive {
            return Int(round(st.totalPred))
        }
        return conversation.total
    }

    var displayOutput: Int {
        if let st = activeState, isActive {
            return Int(round(st.outputPred))
        }
        return conversation.output
    }

    var displayCost: Double {
        if let st = activeState, isActive {
            return st.costPred
        }
        return conversation.costUSD
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. 更新时间
            Text(conversation.time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 125, alignment: .center)

            // 2. 来源 (带活跃闪烁标志)
            HStack(spacing: 3) {
                SourceIcon(source: conversation.source)
                if isActive {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 75, alignment: .center)

            // 3. 预估费用
            Text(Formatters.formatMoney(usd: displayCost, showCNY: showCNY))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.05))
                .frame(width: 95, alignment: .trailing)

            // 4. 总消耗 Token
            Text(Formatters.formatIntWithComma(displayTotal))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 110, alignment: .trailing)

            // 5. 输入 (Prompt)
            Text(Formatters.formatIntWithComma(conversation.prompt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 95, alignment: .trailing)

            // 6. 输出 (Ans)
            Text(Formatters.formatIntWithComma(displayOutput))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.1, green: 0.6, blue: 0.3))
                .frame(width: 85, alignment: .trailing)

            // 7. 缓存 (Cache)
            Text(Formatters.formatIntWithComma(conversation.cached))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)

            // 8. 轮次
            Text("\(conversation.turns)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .center)

            // 9. 模型
            Text(conversation.models)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 120, alignment: .center)

            // 10. 会话提问内容
            Text(conversation.title)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(
            ZStack {
                if isActive {
                    Color.blue.opacity(0.08)
                } else if hover.isHovered {
                    Color.blue.opacity(0.05)
                } else if index % 2 == 1 {
                    Color.black.opacity(0.015)
                } else {
                    Color.white
                }
            }
        )
        .overlay(
            Rectangle()
                .fill(isActive ? Color.blue : Color.clear)
                .frame(width: 3),
            alignment: .leading
        )
        .onHover { h in hover.isHovered = h }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .help("双击查看本会话详细计费与指标分析")
    }
}

// 辅助子组件：来源徽标 (浅色胶囊标签)
struct SourceIcon: View {
    let source: String

    var body: some View {
        if source.contains("AGY") {
            Text("AGY")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.10))
                .foregroundColor(.blue)
                .clipShape(Capsule())
        } else if source.contains("Codex") {
            Text("Codex")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.10))
                .foregroundColor(.purple)
                .clipShape(Capsule())
        } else if source.contains("Claude") {
            Text("Claude")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.10))
                .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.05))
                .clipShape(Capsule())
        } else {
            Text(source)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}
