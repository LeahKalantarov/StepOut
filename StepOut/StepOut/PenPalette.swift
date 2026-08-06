import SwiftUI

/// The floating pen tray — pencil, eraser, widths, colours, paper.
struct PenPalette: View {
    @Bindable var pen: Pen
    @Bindable var paper: Paper

    var body: some View {
        HStack(spacing: 12) {
            toolPencil
            toolEraser

            divider

            HStack(spacing: 6) {
                ForEach(Pen.widths, id: \.self, content: widthDot)
            }

            divider

            HStack(spacing: 8) {
                ForEach(Pen.paletteColours, id: \.self, content: colourDot)
            }

            divider

            paperMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.paper, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Theme.ink, lineWidth: 2.5)
        )
    }

    // MARK: - Pieces

    private var toolPencil: some View {
        Button {
            pen.isErasing = false
        } label: {
            Text("✏️")
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(
                    !pen.isErasing ? Theme.pink.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: !pen.isErasing ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var toolEraser: some View {
        Button {
            pen.isErasing = true
        } label: {
            Image(systemName: "eraser.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: pen.isErasing ? 2 : 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func widthDot(_ width: CGFloat) -> some View {
        let chosen = pen.width == width && !pen.isErasing
        let size = width + 6

        return Button {
            pen.width = width
            pen.isErasing = false
        } label: {
            Circle()
                .fill(Theme.ink)
                .frame(width: size, height: size)
                .frame(width: 30, height: 30)
                .background(
                    chosen ? Color.clear : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: chosen ? 2 : 0)
                        .frame(width: 28, height: 28)
                )
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
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.ink.opacity(0.2), lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(Theme.ink, lineWidth: 2)
                        .opacity(pen.colour == colour && !pen.isErasing ? 1 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
    }

    private var paperMenu: some View {
        Menu {
            Picker("Ruling", selection: $paper.ruling) {
                ForEach(Paper.Ruling.allCases) { ruling in
                    Label(ruling.name, systemImage: ruling.symbol).tag(ruling)
                }
            }

            Picker("Paper", selection: $paper.shade) {
                ForEach(Paper.Shade.allCases) { shade in
                    Text(shade.name).tag(shade)
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.paper)
                    .frame(width: 28, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.ink, lineWidth: 1.5)
                    )

                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Theme.sky.opacity(0.7))
                            .frame(width: 18, height: 1)
                    }
                }

                Rectangle()
                    .fill(Theme.pink.opacity(0.8))
                    .frame(width: 1, height: 28)
                    .offset(x: -8)
            }
            .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.12))
            .frame(width: 1.5, height: 28)
    }
}

#Preview {
    PenPalette(pen: Pen(), paper: Paper())
        .padding(40)
        .background(Theme.paper)
}
