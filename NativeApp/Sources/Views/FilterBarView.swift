import SwiftUI

struct FilterBarView: View {
    @ObservedObject var vm: AgyTokenViewModel

    var body: some View {
        VStack(spacing: 8) {
            // 第一行: 明确分开的工具筛选、时期筛选与搜索框。
            HStack(alignment: .bottom, spacing: 10) {
                filterSection(title: "工具") {
                    Picker("工具", selection: $vm.toolMode) {
                        Text("全部").tag("all")
                        Text("Antigravity").tag("Antigravity")
                        Text("Codex").tag("Codex")
                        Text("Claude").tag("Claude")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .fixedSize(horizontal: true, vertical: false)

                Divider()
                    .frame(height: 31)
                    .padding(.horizontal, 2)

                filterSection(title: "时期") {
                    Picker("时期", selection: $vm.periodMode) {
                        Text("今天").tag("today")
                        Text("昨天").tag("yesterday")
                        Text("近 7 天").tag("7d")
                        Text("近 30 天").tag("30d")
                        Text("全部").tag("all")
                        Text("自定义").tag("custom")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                filterSection(title: "搜索") {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        TextField("任务内容 / 会话 ID / 模型...", text: $vm.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)

                        if !vm.searchQuery.isEmpty {
                            Button {
                                vm.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 190)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            // 第二行: 自定义起止时间选择 (条件展开) 与当前统计范围摘要
            HStack(spacing: 12) {
                if vm.periodMode == "custom" {
                    HStack(spacing: 6) {
                        Text("起止时间:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("起始", selection: $vm.customStart) {
                            if vm.customStart.isEmpty {
                                Text("起始日期").tag("")
                            }
                            ForEach(vm.availableDates, id: \.self) { d in
                                Text(d).tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 115)

                        Text("至")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Picker("截止", selection: $vm.customEnd) {
                            if vm.customEnd.isEmpty {
                                Text("截止日期").tag("")
                            }
                            ForEach(vm.availableDates, id: \.self) { d in
                                Text(d).tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 115)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // 当前展示状态摘要
                HStack(spacing: 6) {
                    Text("当前统计:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(vm.periodDisplayName) · [\(vm.toolDisplayName)]")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("·")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("共 \(vm.filteredConversations.count) 个会话")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            content()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
