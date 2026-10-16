import SwiftUI

struct ClipboardShelfView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var history: ClipboardHistory
    var onClose: (() -> Void)? = nil
    @AppStorage("clipboardShelfExpanded") private var expanded = true
    @State private var copiedID: UUID?
    @State private var copyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { expanded.toggle() } label: {
                    Label(L10n.tr("剪贴板"), systemImage: expanded ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain).font(.headline)
                if !expanded { Text("\(history.images.count) / \(history.texts.count)").monospacedDigit().font(.caption) }
                Text(L10n.tr("本次运行 · 每类最多 50 条")).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if copyFailed { Text(L10n.tr("复制失败，请重试")).font(.caption).foregroundStyle(.red) }
                Button { history.isPaused.toggle() } label: {
                    Label(L10n.tr(history.isPaused ? "继续记录" : "暂停记录"), systemImage: history.isPaused ? "play" : "pause")
                }.controlSize(.small)
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help(L10n.tr("关闭桌面覆盖"))
                }
            }
            if expanded {
                HStack(spacing: 10) {
                    sectionTitle("图片", count: history.images.count, clear: history.clearImages)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                if history.images.isEmpty { emptyHint("尚无复制的图片") }
                                ForEach(history.images) { item in
                                    Button { copied(item.id, success: history.copyImage(item.id)) } label: {
                                        Image(nsImage: item.thumbnail).resizable().scaledToFit()
                                            .frame(width: 116, height: 62).padding(4)
                                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                                            .overlay(alignment: .bottomTrailing) { copiedBadge(item.id) }
                                    }.buttonStyle(.plain).id(item.id)
                                        .help(L10n.tr("点击重新复制，右键删除"))
                                        .accessibilityLabel(L10n.tr("复制图片"))
                                        .contextMenu { Button(L10n.tr("删除"), role: .destructive) { history.removeImage(item.id) } }
                                }
                            }.padding(.bottom, 6)
                        }.onChange(of: history.images.first?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .leading) } }
                    }.frame(height: 80)
                }
                HStack(spacing: 10) {
                    sectionTitle("文字", count: history.texts.count, clear: history.clearTexts)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                if history.texts.isEmpty { emptyHint("尚无复制的文字") }
                                ForEach(history.texts) { item in
                                    Button { copied(item.id, success: history.copyText(item.id)) } label: {
                                        Text(String(item.text.prefix(500))).font(.system(size: 11))
                                            .lineLimit(3).multilineTextAlignment(.leading)
                                            .frame(width: 170, height: 54, alignment: .topLeading).padding(8)
                                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                                            .overlay(alignment: .bottomTrailing) { copiedBadge(item.id) }
                                    }.buttonStyle(.plain).id(item.id)
                                        .help(String(item.text.prefix(2000)))
                                        .contextMenu { Button(L10n.tr("删除"), role: .destructive) { history.removeText(item.id) } }
                                }
                            }.padding(.bottom, 6)
                        }.onChange(of: history.texts.first?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .leading) } }
                    }.frame(height: 80)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: expanded) { _, _ in
            NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            do { try await Task.sleep(for: .seconds(1.5)); copiedID = nil } catch { }
        }
    }

    private func sectionTitle(_ title: String, count: Int, clear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) { Text(L10n.tr(title)); Text("(\(count))").monospacedDigit() }.font(.caption.bold())
            Button(L10n.tr("清空"), role: .destructive, action: clear).controlSize(.mini).disabled(count == 0)
        }.frame(width: 85, alignment: .leading)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(L10n.tr(text)).font(.caption).foregroundStyle(.secondary).frame(height: 70)
    }

    @ViewBuilder private func copiedBadge(_ id: UUID) -> some View {
        if copiedID == id {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(4)
                .accessibilityLabel(L10n.tr("已复制"))
        }
    }

    private func copied(_ id: UUID, success: Bool) { copiedID = success ? id : nil; copyFailed = !success }
}
