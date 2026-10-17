import SwiftUI

struct ClipboardShelfView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var history: ClipboardHistory
    var allowsFullScreen = true
    var canvasClotheslineMode = false
    var showsRowControls = true
    var showsSamples = false
    var onAddToCanvas: ((ClipboardCanvasTransfer) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    @AppStorage("clipboardShelfExpanded") private var expanded = true
    @AppStorage("clipboardShelfFullWidth") private var fullWidth = false
    @AppStorage("clipboardShelfFullScreen") private var fullScreen = false
    @AppStorage(ClipboardAppearance.imageScaleKey) private var imageScale = 1.25
    @AppStorage(ClipboardAppearance.textSizeKey) private var textSize = 14.0
    @AppStorage(ClipboardAppearance.textColorKey) private var textColorChoice = ClipboardAppearance.followCardsColor
    @AppStorage(ClipboardAppearance.lastAllCardsColorKey) private var lastAllCardsColor = CardColor.neutral.rawValue
    private var textTint: CardColor { ClipboardAppearance.textCardColor(choice: textColorChoice, lastAllCards: lastAllCardsColor) }
    @State private var showsSizing = false
    @State private var hoveredSection: String?
    @State private var sizingCategory = ""
    private var appearance: ClipboardAppearance { ClipboardAppearance(imageScale: imageScale, textSize: textSize) }
    private static let sampleImageIDs = [UUID(), UUID(), UUID()]
    private static let sampleTextIDs = [UUID(), UUID(), UUID()]
    @State private var copiedID: UUID?
    @State private var copyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: canvasClotheslineMode ? 2 : 8) {
            if !canvasClotheslineMode {
            HStack(spacing: 10) {
                Button { fullScreen = false; expanded.toggle() } label: {
                    Label(L10n.tr("剪贴板"), systemImage: expanded ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain).font(.headline)
                if !expanded { Text("\(history.images.count) / \(history.texts.count)").monospacedDigit().font(.caption) }
                Text(L10n.format("上限：图片 %@ · 文字 %@", limitTitle(history.imageLimit), limitTitle(history.textLimit))).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if copyFailed { Text(L10n.tr("复制失败，请重试")).font(.caption).foregroundStyle(.red) }
                ClipboardDisplayMenu()
                Button { showsSizing.toggle() } label: {
                    Image(systemName: "slider.horizontal.3")
                }.buttonStyle(.plain).help(L10n.tr("剪贴板设置"))
                    .popover(isPresented: $showsSizing) { sizingControls }
                Button { history.isPaused.toggle() } label: {
                    Label(L10n.tr(history.isPaused ? "继续记录" : "暂停记录"), systemImage: history.isPaused ? "play" : "pause")
                }.controlSize(.small)
                Button {
                    fullScreen = false
                    fullWidth.toggle()
                    if fullWidth { expanded = true }
                } label: {
                    Image(systemName: fullWidth ? "arrow.right.and.line.vertical.and.arrow.left" : "arrow.left.and.right")
                }.buttonStyle(.plain).help(L10n.tr(fullWidth ? "恢复默认宽度" : "展开至屏幕宽度"))
                if allowsFullScreen {
                Button {
                    fullScreen.toggle()
                    if fullScreen { expanded = true }
                } label: {
                    Image(systemName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }.buttonStyle(.plain).help(L10n.tr(fullScreen ? "返回顶部剪贴板" : "全屏浏览剪贴板"))
                }
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help(L10n.tr("关闭桌面覆盖"))
                }
            }
            }
            if fullScreen && allowsFullScreen && !showsSamples {
                fullScreenContents
            } else if expanded || canvasClotheslineMode {
                HStack(alignment: .top, spacing: 10) {
                    sectionTitle("图片", count: history.images.count, clear: history.clearImages)
                    ScrollViewReader { proxy in
                        ClipboardClothesline {
                            if showsSamples {
                                sampleImageCards
                            } else {
                                if history.images.isEmpty { emptyHint("尚无复制的图片") }
                                ForEach(history.images) { item in
                                    Button { copied(item.id, success: history.copyImage(item.id)) } label: {
                                        Image(nsImage: item.thumbnail).resizable().scaledToFit()
                                            .frame(width: 116 * appearance.imageScale, height: 62 * appearance.imageScale).padding(4)
                                            .hangingClipboardCard(id: item.id)
                                            .overlay(alignment: .bottomTrailing) { copiedBadge(item.id) }
                                            .overlay(alignment: .topTrailing) { pinBadge(item.isPinned) }
                                    }.buttonStyle(.plain).id(item.id)
                                        .help(L10n.tr("点击复制；拖入画布，或右键放入画布"))
                                        .accessibilityLabel(L10n.tr("复制图片"))
                                        .draggable(ClipboardCanvasTransfer(id: item.id, kind: .image))
                                        .contextMenu {
                                            if let onAddToCanvas { Button(L10n.tr("放入当前画布")) { onAddToCanvas(ClipboardCanvasTransfer(id: item.id, kind: .image)) } }
                                            Button(L10n.tr(item.isPinned ? "取消固定" : "固定")) { withAnimation { history.togglePin(image: item.id) } }
                                            Button(L10n.tr("删除"), role: .destructive) { history.removeImage(item.id) }
                                        }
                                }
                            }
                        }.onChange(of: history.images.first?.id) { _, id in if !showsSamples, let id { proxy.scrollTo(id, anchor: .leading) } }
                    }.frame(height: appearance.imageRowHeight)
                }
                HStack(alignment: .top, spacing: 10) {
                    sectionTitle("文字", count: history.texts.count, clear: history.clearTexts)
                    ScrollViewReader { proxy in
                        ClipboardClothesline {
                            if showsSamples {
                                sampleTextCards
                            } else {
                                if history.texts.isEmpty { emptyHint("尚无复制的文字") }
                                ForEach(history.texts) { item in
                                    Button { copied(item.id, success: history.copyText(item.id)) } label: {
                                        Text(String(item.text.prefix(500))).font(.system(size: appearance.textSize))
                                            .lineLimit(3).multilineTextAlignment(.leading)
                                            .frame(width: 170 * appearance.textSize / 11, height: 54 * appearance.textSize / 11, alignment: .topLeading).padding(8)
                                            .hangingClipboardCard(id: item.id, tint: textTint)
                                            .overlay(alignment: .bottomTrailing) { copiedBadge(item.id) }
                                            .overlay(alignment: .topTrailing) { pinBadge(item.isPinned) }
                                    }.buttonStyle(.plain).id(item.id)
                                        .help(String(item.text.prefix(2000)))
                                        .draggable(ClipboardCanvasTransfer(id: item.id, kind: .text))
                                        .contextMenu {
                                            if let onAddToCanvas { Button(L10n.tr("放入当前画布")) { onAddToCanvas(ClipboardCanvasTransfer(id: item.id, kind: .text)) } }
                                            ClipboardTextColorMenu()
                                            Button(L10n.tr(item.isPinned ? "取消固定" : "固定")) { withAnimation { history.togglePin(text: item.id) } }
                                            Button(L10n.tr("删除"), role: .destructive) { history.removeText(item.id) }
                                        }
                                }
                            }
                        }.onChange(of: history.texts.first?.id) { _, id in if !showsSamples, let id { proxy.scrollTo(id, anchor: .leading) } }
                    }.frame(height: appearance.textRowHeight)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, canvasClotheslineMode ? 4 : 10)
        .background {
            if canvasClotheslineMode {
                Color.clear
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: canvasClotheslineMode ? nil : .infinity, alignment: .topLeading)
        .onChange(of: expanded) { _, _ in
            NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
        }
        .onChange(of: fullWidth) { _, _ in
            NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
        }
        .onChange(of: fullScreen) { _, _ in
            NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
        }
        .onChange(of: imageScale) { _, _ in notifySizeChange() }
        .onChange(of: textSize) { _, _ in notifySizeChange() }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            do { try await Task.sleep(for: .seconds(1.5)); copiedID = nil } catch { }
        }
    }

    private var sampleImageCards: some View {
        ForEach(0..<3, id: \.self) { index in
            let colors: [Color] = [.blue, .teal, .orange]
            let symbols = ["mountain.2.fill", "photo.on.rectangle.angled", "sparkles"]
            Image(systemName: symbols[index])
                .resizable().scaledToFit().padding(18 * appearance.imageScale)
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 116 * appearance.imageScale, height: 62 * appearance.imageScale)
                .background(LinearGradient(colors: [colors[index].opacity(0.45), colors[index]],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(4)
                .hangingClipboardCard(id: Self.sampleImageIDs[index])
                .accessibilityLabel(L10n.tr("示例图片"))
                .help(L10n.tr("仅用于预览，桌面模式显示真实剪贴板内容。"))
        }
    }

    private var sampleTextCards: some View {
        ForEach(0..<3, id: \.self) { index in
            let samples = [L10n.tr("记录一个想法，稍后继续。"),
                           L10n.tr("待办事项：整理项目、查看文档。"),
                           L10n.tr("常用片段会挂在这里，方便随时取用。")]
            Text(samples[index]).font(.system(size: appearance.textSize))
                .lineLimit(3).multilineTextAlignment(.leading)
                .frame(width: 170 * appearance.textSize / 11, height: 54 * appearance.textSize / 11, alignment: .topLeading)
                .padding(8)
                .hangingClipboardCard(id: Self.sampleTextIDs[index], tint: textTint)
                .contextMenu { ClipboardTextColorMenu() }
                .help(L10n.tr("仅用于预览，桌面模式显示真实剪贴板内容。"))
        }
    }

    private func limitTitle(_ count: Int) -> String {
        count == 0 ? L10n.tr("不限条数") : "\(count)"
    }

    private var sizingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("剪贴板设置")).font(.headline)
            HStack {
                Text(L10n.tr("图片预览大小"))
                Spacer()
                Text("\(Int(appearance.imageScale * 100))%").monospacedDigit()
            }
            Slider(value: $imageScale, in: 1...2, step: 0.05)
                .accessibilityLabel(L10n.tr("图片预览大小"))
            HStack {
                Text(L10n.tr("文字字号"))
                Spacer()
                Text("\(Int(appearance.textSize)) pt").monospacedDigit()
            }
            Slider(value: $textSize, in: 11...24, step: 1)
                .accessibilityLabel(L10n.tr("文字字号"))
            Button(L10n.tr("恢复默认大小")) { imageScale = 1.25; textSize = 14 }
            Divider()
            ClipboardHistoryLimitControls(history: history)
        }.padding(18).frame(width: 280)
    }

    private func notifySizeChange() {
        NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
    }

    private var fullScreenContents: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("图片", count: history.images.count, clear: history.clearImages)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160 * appearance.imageScale))], spacing: 24) {
                        ForEach(history.images) { item in
                            Button { copied(item.id, success: history.copyImage(item.id)) } label: {
                                Image(nsImage: item.thumbnail).resizable().scaledToFit()
                                    .frame(maxWidth: .infinity).frame(height: 140 * appearance.imageScale).padding(8)
                                    .hangingClipboardCard(id: item.id)
                                    .overlay(alignment: .bottomTrailing) { copiedBadge(item.id) }
                                            .overlay(alignment: .topTrailing) { pinBadge(item.isPinned) }
                            }.buttonStyle(.plain)
                                .help(L10n.tr("点击复制；拖入画布，或右键放入画布"))
                                .accessibilityLabel(L10n.tr("复制图片"))
                                .draggable(ClipboardCanvasTransfer(id: item.id, kind: .image))
                                        .contextMenu {
                                            if let onAddToCanvas { Button(L10n.tr("放入当前画布")) { onAddToCanvas(ClipboardCanvasTransfer(id: item.id, kind: .image)) } }
                                            Button(L10n.tr(item.isPinned ? "取消固定" : "固定")) { withAnimation { history.togglePin(image: item.id) } }
                                            Button(L10n.tr("删除"), role: .destructive) { history.removeImage(item.id) }
                                        }
                        }
                    }
                    if history.images.isEmpty { emptyHint("尚无复制的图片") }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("文字", count: history.texts.count, clear: history.clearTexts)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200 * appearance.textSize / 14))], spacing: 24) {
                        ForEach(history.texts) { item in
                            Button { copied(item.id, success: history.copyText(item.id)) } label: {
                                Text(String(item.text.prefix(2000))).font(.system(size: appearance.textSize))
                                    .lineLimit(8).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 140 * appearance.textSize / 14, alignment: .topLeading).padding(8)
                                    .hangingClipboardCard(id: item.id, tint: textTint)
                                    .overlay(alignment: .bottomTrailing) { copiedBadge(item.id) }
                                            .overlay(alignment: .topTrailing) { pinBadge(item.isPinned) }
                            }.buttonStyle(.plain).help(String(item.text.prefix(2000)))
                                .draggable(ClipboardCanvasTransfer(id: item.id, kind: .text))
                                        .contextMenu {
                                            if let onAddToCanvas { Button(L10n.tr("放入当前画布")) { onAddToCanvas(ClipboardCanvasTransfer(id: item.id, kind: .text)) } }
                                            ClipboardTextColorMenu()
                                            Button(L10n.tr(item.isPinned ? "取消固定" : "固定")) { withAnimation { history.togglePin(text: item.id) } }
                                            Button(L10n.tr("删除"), role: .destructive) { history.removeText(item.id) }
                                        }
                        }
                    }
                    if history.texts.isEmpty { emptyHint("尚无复制的文字") }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func sectionTitle(_ title: String, count: Int, clear: @escaping () -> Void) -> some View {
        if showsRowControls {
            if canvasClotheslineMode {
                // A borderless menu label renders only one text run, so title and count are concatenated.
                HStack(spacing: 4) {
                    Menu {
                        if !showsSamples {
                            Button(L10n.tr("清空"), role: .destructive, action: clear).disabled(count == 0)
                            Divider()
                            Button(L10n.tr(history.isPaused ? "继续记录" : "暂停记录")) { history.isPaused.toggle() }
                        }
                        Button(L10n.tr("剪贴板设置")) { sizingCategory = title; showsSizing = true }
                    } label: {
                        Text(L10n.tr(title)).fontWeight(.medium)
                            + Text("  " + (showsSamples ? L10n.tr("示例") : "\(count)")).foregroundColor(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                        .opacity(hoveredSection == title ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .onHover { hoveredSection = $0 ? title : (hoveredSection == title ? nil : hoveredSection) }
                .frame(width: 110, alignment: .leading)
                // Vertically centred on the rope (ClipboardClotheslineGeometry.ropeTop plus row padding).
                .padding(.top, 9)
                .popover(isPresented: Binding(get: { showsSizing && sizingCategory == title }, set: { showsSizing = $0 })) {
                    sizingControls
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) { Text(L10n.tr(title)); Text("(\(count))").monospacedDigit() }.font(.caption.bold())
                    Button(L10n.tr("清空"), role: .destructive, action: clear).controlSize(.mini).disabled(count == 0)
                }.frame(width: 85, alignment: .leading)
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(L10n.tr(text)).font(.caption).foregroundStyle(.secondary).frame(height: canvasClotheslineMode ? 32 : 70)
    }

    @ViewBuilder private func pinBadge(_ pinned: Bool) -> some View {
        if pinned {
            Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
                .rotationEffect(.degrees(30)).padding(6)
                .transition(.symbolEffect(.drawOn))
                .accessibilityLabel(L10n.tr("已固定"))
        }
    }

    @ViewBuilder private func copiedBadge(_ id: UUID) -> some View {
        if copiedID == id {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(4)
                .transition(.symbolEffect(.drawOn))
                .accessibilityLabel(L10n.tr("已复制"))
        }
    }

    private func copied(_ id: UUID, success: Bool) {
        withAnimation { copiedID = success ? id : nil }
        copyFailed = !success
    }
}
