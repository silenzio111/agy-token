import SwiftUI
import AppKit

final class DetailSheetState: ObservableObject {
    @Published var copied: Bool = false
}

struct ConversationDetailSheet: View {
    let conversation: ConversationItem
    let showCNY: Bool
    let onDismiss: () -> Void

    @StateObject private var sheetState = DetailSheetState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("会话 Token 消耗与费用详情")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Conversation ID: \(conversation.cid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // 详情表格卡片 (浅灰底层，清晰键值对)
            VStack(spacing: 8) {
                Group {
                    DetailRow(label: "所属工具", value: "\(conversation.tool) (\(conversation.source))")
                    DetailRow(label: "提问内容", value: conversation.title)
                    DetailRow(label: "最近交互时间", value: conversation.time)
                    DetailRow(label: "使用模型", value: conversation.models)
                    DetailRow(
                        label: "官方计费单价",
                        value: conversation.rates != nil ?
                            String(format: "入: $%.3f · 出: $%.3f · 缓存: $%.3f (每 1M)", conversation.rates!.in, conversation.rates!.out, conversation.rates!.cache) :
                            "通用基准价格"
                    )
                    DetailRow(label: "计费库匹配", value: conversation.rates?.matched ?? "通用预估")
                    DetailRow(label: "交互轮次", value: "\(conversation.turns) 轮交互")
                }

                Divider()
                    .background(Color.black.opacity(0.06))
                    .padding(.vertical, 2)

                Group {
                    DetailRow(
                        label: "预估 API 费用",
                        value: "\(Formatters.formatMoney(usd: conversation.costUSD, showCNY: showCNY)) (约 $ \(String(format: "%.4f", conversation.costUSD)))",
                        isHighlight: true,
                        highlightColor: Color(red: 0.85, green: 0.35, blue: 0.05)
                    )
                    DetailRow(
                        label: "通过缓存省下",
                        value: "\(Formatters.formatMoney(usd: conversation.savedUSD, showCNY: showCNY)) (约 $ \(String(format: "%.4f", conversation.savedUSD)))",
                        isHighlight: true,
                        highlightColor: Color(red: 0.1, green: 0.6, blue: 0.3)
                    )
                    DetailRow(
                        label: "总计消耗 Token",
                        value: "\(Formatters.formatIntWithComma(conversation.total)) (\(Formatters.formatShort(conversation.total)))"
                    )
                    DetailRow(label: "未缓存输入", value: "\(Formatters.formatIntWithComma(conversation.prompt))")
                    DetailRow(label: "实际生成输出", value: "\(Formatters.formatIntWithComma(conversation.output))")
                    DetailRow(label: "缓存命中", value: "\(Formatters.formatIntWithComma(conversation.cached))")
                    DetailRow(label: "思维推理", value: "\(Formatters.formatIntWithComma(conversation.thoughts))")
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 底部操作按钮
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(conversation.cid, forType: .string)
                    sheetState.copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        sheetState.copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: sheetState.copied ? "checkmark" : "doc.on.doc")
                        Text(sheetState.copied ? "已复制 ID" : "复制会话 ID")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("关闭")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 580)
        .background(Color.white)
    }
}

// 辅助子组件：单行键值
struct DetailRow: View {
    let label: String
    let value: String
    var isHighlight: Bool = false
    var highlightColor: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label + ":")
                .font(.system(size: 11, weight: isHighlight ? .bold : .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: isHighlight ? .bold : .regular, design: isHighlight ? .monospaced : .default))
                .foregroundColor(isHighlight ? highlightColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
