import SwiftUI

/// Where everything on a sheet goes.
///
/// Worked out before anything is drawn, because a box has to be tall enough
/// for writing that has not been written yet. So each line is measured and
/// broken to fit the column first, the number of lines that come out of that
/// decides the height of the box, and the boxes are stacked from those
/// heights.
///
/// Two columns, filled by putting each box into whichever side is currently
/// shorter. That is what gives a revision sheet its look — boxes of different
/// sizes packed together rather than a single long ladder — and it costs one
/// comparison per box.
struct SheetLayout {
    struct Placed: Identifiable {
        let card: NoteCard
        let frame: CGRect

        /// The card's lines, already broken to fit its width. Kept from the
        /// measuring pass so the drawing pass does not have to break them
        /// again and risk breaking them differently.
        let lines: [String]

        let graph: CGRect?

        var id: UUID { card.id }
    }

    let title: String
    let titleWidth: CGFloat
    let cards: [Placed]

    /// How far down the page the sheet reaches.
    let height: CGFloat

    // MARK: - Measurements

    static let margin: CGFloat = 24
    static let gap: CGFloat = 16
    static let padding: CGFloat = 16

    /// How far in the sheet starts on the left.
    ///
    /// Wider than the other margins because the round buttons float over the
    /// top-left corner of the page, and a box of notes underneath them cannot
    /// be read. Ruled pages already clear them — writing starts past the red
    /// margin rule — and a sheet has to do the same for itself.
    static let leftMargin: CGFloat = 78

    static let titleHeight: CGFloat = 30
    static let headingHeight: CGFloat = 15
    static let textHeight: CGFloat = 13

    /// Distance from one written line to the next inside a box.
    static let lineGap: CGFloat = 24

    /// How tall a graph is drawn, as a share of the box it sits in. Close to
    /// square, because a parabola in a letterbox does not look like a parabola.
    static let graphAspect: CGFloat = 0.78

    /// Below this a sheet is laid out in one column. Two columns of 150 points
    /// each would break every line into three.
    static let leastForTwoColumns: CGFloat = 620

    // MARK: - Laying out

    static func lay(_ sheet: NoteSheet, into width: CGFloat) -> SheetLayout {
        let left = leftMargin
        let across = width - leftMargin - margin

        let under = margin + titleHeight + gap * 1.5

        // Two columns, each tracking how far down its own side has filled. On
        // a narrow page there is only one, and every box spans it.
        let twoUp = across >= leastForTwoColumns
        let column = twoUp ? (across - gap) / 2 : across
        let rightEdge = left + column + gap

        var filled: [CGFloat] = twoUp ? [under, under] : [under]

        var placed: [Placed] = []

        for card in sheet.cards {
            let wide = !twoUp || card.kind.isWide
            let boxWidth = wide ? across : column

            let lines = card.lines.flatMap {
                StrokeFont.wrap($0, height: textHeight, into: boxWidth - padding * 2)
            }

            var boxHeight = padding + headingHeight + gap
            boxHeight += CGFloat(lines.count) * lineGap

            var graph: CGRect?

            if card.graph != nil {
                let box = CGRect(
                    x: padding,
                    y: boxHeight,
                    width: boxWidth - padding * 2,
                    height: (boxWidth - padding * 2) * graphAspect
                )

                graph = box
                boxHeight += box.height + gap * 0.5
            }

            boxHeight += padding

            // Each box goes into whichever column has filled least far, which
            // is what packs a sheet instead of laddering it. A wide box
            // crosses both, so it waits for the lower of the two and leaves
            // them level underneath it.
            let side = wide ? 0 : (filled[1] < filled[0] ? 1 : 0)
            let boxTop = wide ? (filled.max() ?? under) : filled[side]
            let x = side == 0 ? left : rightEdge

            let frame = CGRect(x: x, y: boxTop, width: boxWidth, height: boxHeight)

            placed.append(
                Placed(
                    card: card,
                    frame: frame,
                    lines: lines,
                    // Held relative to the box while measuring, since the box's
                    // own position was not known then.
                    graph: graph.map { $0.offsetBy(dx: frame.minX, dy: frame.minY) }
                )
            )

            let bottom = frame.maxY + gap

            if wide {
                filled = filled.map { _ in bottom }
            } else {
                filled[side] = bottom
            }
        }

        return SheetLayout(
            title: sheet.title,
            titleWidth: StrokeFont.width(of: sheet.title, height: titleHeight),
            cards: placed,
            height: (filled.max() ?? under) + margin
        )
    }
}

/// A sheet of notes, drawn.
///
/// One `Canvas` rather than a view per line. A full sheet is a couple of
/// hundred separate pen paths, and a couple of hundred SwiftUI views that
/// never change and never take a tap is a great deal of machinery to lay out
/// something that could be painted in one pass.
struct NoteSheetView: View {
    let sheet: NoteSheet
    let width: CGFloat
    let ink: Color

    private let layout: SheetLayout

    init(sheet: NoteSheet, width: CGFloat, ink: Color) {
        self.sheet = sheet
        self.width = width
        self.ink = ink
        self.layout = SheetLayout.lay(sheet, into: width)
    }

    /// How tall the paper needs to be to hold this.
    var height: CGFloat { layout.height }

    var body: some View {
        Canvas { context, _ in
            draw(into: &context)
        } symbols: {
            // Anything that is not pen strokes has to be handed to the canvas
            // as a view, so this is where the little kind badges come from.
            ForEach(layout.cards) { placed in
                Image(systemName: placed.card.kind.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.pink)
                    .tag(placed.card.id)
            }
        }
        .frame(width: width, height: layout.height)
        // The sheet is a backdrop to write on, not something to tap. Every
        // touch belongs to the canvas above it.
        .allowsHitTesting(false)
    }

    private func draw(into context: inout GraphicsContext) {
        drawTitle(into: &context)

        for placed in layout.cards {
            draw(placed, into: &context)
        }
    }

    private func drawTitle(into context: inout GraphicsContext) {
        // Centred over the boxes rather than over the page, since the page has
        // more room on one side than the other.
        let middle = (SheetLayout.leftMargin + width - SheetLayout.margin) / 2

        let origin = CGPoint(
            x: middle - layout.titleWidth / 2,
            y: SheetLayout.margin
        )

        write(layout.title, at: origin, height: SheetLayout.titleHeight, weight: 2.6, into: &context)

        // The rule under a title on a hand-made sheet, which is the thing that
        // makes it read as a heading rather than a first line.
        var rule = Path()
        rule.move(to: CGPoint(x: origin.x - 8, y: origin.y + SheetLayout.titleHeight + 8))
        rule.addLine(to: CGPoint(x: origin.x + layout.titleWidth + 8, y: origin.y + SheetLayout.titleHeight + 8))

        context.stroke(rule, with: .color(Theme.pink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    private func draw(_ placed: SheetLayout.Placed, into context: inout GraphicsContext) {
        let box = Path(roundedRect: placed.frame, cornerRadius: 14, style: .continuous)

        context.fill(box, with: .color(placed.card.kind.colour))
        context.stroke(box, with: .color(ink), style: StrokeStyle(lineWidth: 2))

        let left = placed.frame.minX + SheetLayout.padding
        var y = placed.frame.minY + SheetLayout.padding

        // The symbol, then the heading beside it.
        let badge = CGRect(x: left, y: y, width: 16, height: 16)

        if let symbol = context.resolveSymbol(id: placed.card.id) {
            context.draw(symbol, in: badge)
        }

        write(
            placed.card.heading.uppercased(),
            at: CGPoint(x: badge.maxX + 8, y: y),
            height: SheetLayout.headingHeight,
            weight: 2.2,
            into: &context
        )

        y += SheetLayout.headingHeight + SheetLayout.gap

        for line in placed.lines {
            write(line, at: CGPoint(x: left, y: y), height: SheetLayout.textHeight, weight: 1.7, into: &context)
            y += SheetLayout.lineGap
        }

        if let graph = placed.card.graph, let box = placed.graph {
            draw(graph, in: box, into: &context)
        }
    }

    /// Writes text in the stroke font, in the same hand as everything else the
    /// tutor puts on the page.
    private func write(
        _ text: String,
        at origin: CGPoint,
        height: CGFloat,
        weight: CGFloat,
        into context: inout GraphicsContext
    ) {
        context.stroke(
            StrokeFont.path(for: text, from: origin, height: height),
            with: .color(ink),
            style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: - The graph

    private func draw(_ graph: NoteGraph, in box: CGRect, into context: inout GraphicsContext) {
        context.fill(
            Path(roundedRect: box, cornerRadius: 8, style: .continuous),
            with: .color(Theme.paper.opacity(0.7))
        )

        drawAxes(graph, in: box, into: &context)

        context.stroke(
            graph.curve(in: box),
            with: .color(Theme.pink),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )

        drawMarks(graph, in: box, into: &context)
    }

    private func drawAxes(_ graph: NoteGraph, in box: CGRect, into context: inout GraphicsContext) {
        var axes = Path()

        if graph.showsHorizontalAxis {
            let at = graph.place(x: graph.xRange[0], y: 0, in: box)
            axes.move(to: at)
            axes.addLine(to: CGPoint(x: box.maxX, y: at.y))
        }

        if graph.showsVerticalAxis {
            let at = graph.place(x: 0, y: graph.yRange[0], in: box)
            axes.move(to: at)
            axes.addLine(to: CGPoint(x: at.x, y: box.minY))
        }

        context.stroke(axes, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2))
    }

    /// The roots and the turning point, which are the whole reason a student
    /// is looking at the graph at all.
    private func drawMarks(_ graph: NoteGraph, in box: CGRect, into context: inout GraphicsContext) {
        for root in graph.roots {
            let at = graph.place(x: root, y: 0, in: box)

            guard box.insetBy(dx: -2, dy: -2).contains(at) else { continue }

            context.fill(dot(at, radius: 4), with: .color(ink))

            write(
                tidy(root),
                at: CGPoint(x: at.x - 8, y: at.y + 10),
                height: 10,
                weight: 1.4,
                into: &context
            )
        }

        guard let turning = graph.turningPoint else { return }

        let at = graph.place(x: turning[0], y: turning[1], in: box)

        guard box.insetBy(dx: -2, dy: -2).contains(at) else { return }

        context.stroke(dot(at, radius: 4.5), with: .color(Theme.pink), style: StrokeStyle(lineWidth: 2))
    }

    private func dot(_ at: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: at.x - radius,
            y: at.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    /// A number as it would be written by hand: 3 rather than 3.0.
    private func tidy(_ number: Double) -> String {
        let rounded = (number * 100).rounded() / 100

        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded)
    }
}