import SwiftUI

/// Geometry shared by the rope, clips and their surrounding scroll area.
enum ClipboardClotheslineGeometry {
    static let hangingClearance = 42.0
    static let ropeTop = 13.0

    static func ropeY(at x: Double, width: Double) -> Double {
        guard width > 0 else { return ropeTop }
        let fraction = min(1, max(0, x / width))
        return ropeTop + 4 * min(8, width * 0.008) * fraction * (1 - fraction)
    }

    static func tilt(for id: UUID) -> Double {
        Double(id.uuid.0 % 5) - 2
    }
}

private struct ClipboardRope: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = ClipboardClotheslineGeometry.ropeTop
        path.move(to: CGPoint(x: 0, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: top),
                          control: CGPoint(x: rect.midX, y: top + 2 * min(8, rect.width * 0.008)))
        return path
    }
}

/// Keeps the rope stationary while its hanging items scroll beneath it.
struct ClipboardClothesline<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var coordinateID = UUID()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ClipboardRope()
                    .stroke(.primary.opacity(0.24), lineWidth: 1.4)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    .allowsHitTesting(false)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        content()
                    }.padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
                }.coordinateSpace(name: coordinateID)
            }
            .environment(\.clipboardRopeSpace, ClipboardRopeSpace(id: coordinateID, width: geometry.size.width))
        }
    }
}

private struct ClipboardRopeSpace: Sendable {
    let id: UUID
    let width: Double
}

private struct ClipboardRopeSpaceKey: EnvironmentKey {
    static let defaultValue: ClipboardRopeSpace? = nil
}

private extension EnvironmentValues {
    var clipboardRopeSpace: ClipboardRopeSpace? {
        get { self[ClipboardRopeSpaceKey.self] }
        set { self[ClipboardRopeSpaceKey.self] = newValue }
    }
}

private struct HangingClipboardCard<Content: View>: View {
    let id: UUID
    let content: Content
    @Environment(\.clipboardRopeSpace) private var ropeSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(spacing: -9) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.58), Color(white: 0.94), Color(white: 0.68)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(alignment: .top) {
                    Capsule().fill(.black.opacity(0.3)).frame(width: 5, height: 1.5).padding(.top, 8)
                }
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.5), lineWidth: 0.5))
                .frame(width: 10, height: 25)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .zIndex(1)
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.45), lineWidth: 0.75))
                .shadow(color: .black.opacity(hovering ? 0.2 : 0.1), radius: hovering ? 6 : 3, y: 3)
        }
        .background(alignment: .top) {
            if ropeSpace == nil {
                Rectangle().fill(.primary.opacity(0.24)).frame(height: 1)
                    .padding(.horizontal, -12).offset(y: 8)
                    .allowsHitTesting(false)
            }
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : (hovering ? 0 : ClipboardClotheslineGeometry.tilt(for: id))), anchor: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.65), value: hovering)
        .onHover { hovering = $0 }
        .visualEffect { [ropeSpace] effect, proxy in
            effect.offset(y: ropeSpace.map {
                ClipboardClotheslineGeometry.ropeY(at: proxy.frame(in: .named($0.id)).midX, width: $0.width)
                    - ClipboardClotheslineGeometry.ropeTop
            } ?? 0)
        }
    }
}

extension View {
    func hangingClipboardCard(id: UUID) -> some View {
        HangingClipboardCard(id: id, content: self)
    }
}
