import AppKit
import SwiftUI

extension BackgroundTintColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

private enum BackgroundTintPreset: String, CaseIterable {
    case gray, blue, warm
    var title: String {
        switch self {
        case .gray: L10n.tr("浅灰")
        case .blue: L10n.tr("蓝色")
        case .warm: L10n.tr("暖色")
        }
    }
    var hex: String {
        switch self {
        case .gray: "#D6D8DC"
        case .blue: "#6B9BD2"
        case .warm: "#D8B68C"
        }
    }
}

struct CanvasBackgroundMenu: View {
    @AppStorage(BackgroundTint.colorPreferenceKey) private var colorHex = BackgroundTintColor.default.hex
    @AppStorage(BackgroundTint.opacityPreferenceKey) private var opacity = 0.0
    let onCustomize: () -> Void

    var body: some View {
        Menu(L10n.tr("画布背景")) {
            Button(L10n.tr("无色")) { opacity = 0 }
            ForEach(BackgroundTintPreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    colorHex = preset.hex
                    if opacity == 0 { opacity = 0.25 }
                }
            }
            Divider()
            Button(L10n.tr("自定义颜色…"), action: onCustomize)
        }
    }
}

/// Both backgrounds edit the shared color and intensity.
struct BackgroundTintControls: View {
    @ObservedObject private var language = LanguageController.shared
    @Binding var colorHex: String
    @Binding var opacity: Double

    private var customColor: Binding<Color> {
        Binding(get: { Color(nsColor: (BackgroundTintColor(hex: colorHex) ?? .default).nsColor) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            colorHex = BackgroundTintColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent).hex
            if opacity == 0 { opacity = 0.25 }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(L10n.tr("无色")) { opacity = 0 }
                ForEach(BackgroundTintPreset.allCases, id: \.self) { preset in
                    self.preset(preset.title, hex: preset.hex)
                }
            }.buttonStyle(.bordered).controlSize(.small)
            ColorPicker(L10n.tr("自定义颜色"), selection: customColor, supportsOpacity: false)
            HStack {
                Slider(value: $opacity, in: 0...0.8) { Text(L10n.tr("颜色浓度")) }
                Text("\(Int(BackgroundTint(opacity: opacity).opacity * 100))%")
                    .font(.caption.monospacedDigit()).frame(width: 35, alignment: .trailing)
            }
        }
    }

    private func preset(_ title: String, hex: String) -> some View {
        Button {
            colorHex = hex
            if opacity == 0 { opacity = 0.25 }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: (BackgroundTintColor(hex: hex) ?? .default).nsColor)).frame(width: 10, height: 10)
                Text(title)
            }
        }
    }
}

struct CanvasBackgroundView: View {
    @AppStorage(BackgroundTint.colorPreferenceKey) private var colorHex = BackgroundTintColor.default.hex
    @AppStorage(BackgroundTint.opacityPreferenceKey) private var opacity = 0.0

    var body: some View {
        let tint = BackgroundTint(color: BackgroundTintColor(hex: colorHex) ?? .default, opacity: opacity)
        Color(nsColor: .textBackgroundColor)
            .overlay(Color(nsColor: tint.color.nsColor).opacity(tint.opacity))
            .allowsHitTesting(false)
    }
}
