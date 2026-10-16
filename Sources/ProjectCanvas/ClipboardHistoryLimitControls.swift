import SwiftUI

struct ClipboardHistoryLimitControls: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var history: ClipboardHistory
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeading { Text(L10n.tr("历史数量上限")).font(.headline) }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.tr("图片"))
                    Picker(L10n.tr("图片"), selection: Binding(get: { history.imageLimit }, set: { history.setLimits(images: $0) })) {
                        limitOptions
                    }.labelsHidden().frame(width: 160)
                }
                GridRow {
                    Text(L10n.tr("文字"))
                    Picker(L10n.tr("文字"), selection: Binding(get: { history.textLimit }, set: { history.setLimits(text: $0) })) {
                        limitOptions
                    }.labelsHidden().frame(width: 160)
                }
            }
            Text(L10n.tr("不限条数仍受内存上限保护。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.tr("降低上限会删除最旧的历史记录，已放入画布的内容不受影响。"))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.tr("恢复默认数量")) { history.setLimits(text: 50, images: 50) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var limitOptions: some View {
        ForEach(ClipboardHistory.limitPresets, id: \.self) { count in
            Text(count == 0 ? L10n.tr("不限条数") : "\(count)").tag(count)
        }
    }

}
