import SwiftUI

@main
struct ProjectCanvasApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var language = LanguageController.shared

    var body: some Scene {
        WindowGroup("ProjectCanvas") {
            MainWindow(model: model)
                .environment(\.locale, language.locale)
                .environmentObject(language)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 820)
    }
}
