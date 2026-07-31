import SwiftUI

/// A small floating palette: what to write with, and how to take it back.
struct PenPalette: View {
    @Bindable var pen: Pen

    /// Undo and redo belong to the canvas, so it does the work.
    let undo: () -> Void
    let redo: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            tool(.pencil, isOn: !pen.isErasing) { pen.isErasing = false }
            tool(.eraser, isOn: pen.isErasing) { pen.isErasing = true }

            divider

            ForEach(Pen.widths, id: \.self) { width in
                widthDot(width)
            }

            divider

            ForEach(Pen.colours, id: \.self) { colour in
                colourDot(colour)
            }

            divider

            button(.undo, action: undo)
            button(.redo, action: redo)
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    // MARK: - Pieces

    private enum Symbol: String {
        case pencil = "pencil.tip"
        case eraser = "eraser"
        case undo = "arrow.uturn.backward"
        case redo = "arrow.uturn.forward"
    }

    private func tool(_ symbol: Symbol, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol.rawValue)
                .font(.system(size: 15))
                .foregroundStyle(isOn ? Color.white : .primary)
                .frame(width: 30, height: 30)
                .background(isOn ? Color.accentColor : .clear, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func button(_ symbol: Symbol, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol.rawValue)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 30)
        }
        .buttonStyle(.plain)
    }

    /// Thicknesses are drawn at the size they write, so the choice is obvious
    /// without a label.
    private func widthDot(_ width: CGFloat) -> some View {
        Button {
            pen.width = width
            pen.isErasing = false
        } label: {
            Circle()
                .fill(pen.width == width ? Color.primary : .secondary)
                .frame(width: width + 4, height: width + 4)
                .frame(width: 24, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func colourDot(_ colour: Color) -> some View {
        Button {
            pen.colour = colour
            pen.isErasing = false
        } label: {
            Circle()
                .fill(colour)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .strokeBorder(.primary, lineWidth: 2)
                        .opacity(pen.colour == colour && !pen.isErasing ? 1 : 0)
                        .padding(-3)
                )
                .frame(width: 26, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }
}

#Preview {
    PenPalette(pen: Pen(), undo: {}, redo: {})
        .padding(40)
        .background(Color(red: 0.99, green: 0.98, blue: 0.94))
}
