import SwiftUI

/// Out-of-Pocket-inspired palette: flat, bold, thick outlines.
enum Theme {
    static let sky = Color(red: 0.49, green: 0.83, blue: 0.99)
    static let pink = Color(red: 1.0, green: 0.36, blue: 0.64)
    static let yellow = Color(red: 1.0, green: 0.94, blue: 0.4)
    static let ink = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let paper = Color.white
    static let panel = Color(red: 0.93, green: 0.93, blue: 0.93)

    static let outline: CGFloat = 2
    static let corner: CGFloat = 14
}

/// White fill, thick black border — the default card/button shell.
struct BrutalBorder: ViewModifier {
    var radius: CGFloat = Theme.corner
    var lineWidth: CGFloat = Theme.outline

    func body(content: Content) -> some View {
        content
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: lineWidth)
            )
    }
}

extension View {
    func brutalBorder(radius: CGFloat = Theme.corner, lineWidth: CGFloat = Theme.outline) -> some View {
        modifier(BrutalBorder(radius: radius, lineWidth: lineWidth))
    }
}
