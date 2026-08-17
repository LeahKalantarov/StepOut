import SwiftUI

/// Turns text into the path a pen travels to write it.
///
/// An ordinary font (.ttf, .otf) stores the *outline* of a letter — the border
/// you fill with ink. That is no use for animating handwriting, because an
/// outline has no beginning and no direction. Drawing one looks like a cookie
/// cutter tracing itself, not a hand writing.
///
/// So we use a Hershey font instead. These were drawn in the 1960s at a US Navy
/// lab for pen plotters, machines that held an actual pen, so every character is
/// stored as the line the pen follows. That is exactly what we need, and they
/// are public domain.
///
/// The files are unmodified, from github.com/kamalmostafa/hershey-fonts.
enum StrokeFont {

    /// Which handwriting to use. Three are bundled, so this is the only line
    /// to change:
    ///   futural — neat block printing, the way most people write out maths
    ///   rowmans — much the same, a little narrower
    ///   cursive — joined-up script, prettier but harder to read
    private static let fontName = "futural"

    /// One character: the pen paths that draw it, and where it sits sideways.
    private struct Glyph {
        let strokes: [[CGPoint]]

        // How far in from the pen the drawing starts, and where the next
        // character begins. The gap between them is the character's width.
        let left: CGFloat
        let right: CGFloat
    }

    /// Hershey draws capital letters about 21 units tall. Dividing by that
    /// turns "21 units" into "however many points we asked for".
    private static let capitalHeight: CGFloat = 21

    /// Hershey does not put the baseline at zero: capitals run from -12 up
    /// there to 9 down here, so the line the letters stand on is y = 9. All
    /// three bundled fonts agree on this.
    ///
    /// Only superscripts need to know. They are shrunk and lifted around the
    /// baseline, and shrinking around the wrong line would slide them
    /// sideways of where they belong.
    private static let baselineHeight: CGFloat = 9

    /// How much smaller a superscript is than the text it belongs to. Small
    /// enough to read as a power at a glance, large enough that a 2 written
    /// by a thin pen is still legibly a 2.
    private static let superscriptScale: CGFloat = 0.6

    /// How a stacked fraction is proportioned, all as fractions of the text
    /// height around it: how big its halves are, how far the bar sits above
    /// the baseline, the air between the bar and each half, and the overhang
    /// of the bar past the wider half.
    ///
    /// Chosen so the top of the numerator lands just under the top of a
    /// capital standing beside it. Any taller and a fraction collides with the
    /// ruled line above, which on a page of handwriting looks like a mistake
    /// rather than a fraction.
    private static let fractionScale: CGFloat = 0.68
    private static let fractionBarHeight: CGFloat = 0.35
    private static let fractionGap: CGFloat = 0.17
    private static let fractionOverhang: CGFloat = 0.12

    private static let glyphs = readFontFile()

    /// The path that writes `text`, resting on a baseline starting at `origin`.
    ///
    /// Letters like g and y dip below the baseline, and every letter body sits
    /// above it, which is exactly how the font stores them — so `origin` is the
    /// point where the pen would touch down on a ruled line.
    ///
    /// A `^` raises what follows, so `a^2 - b^2` writes the way it would be
    /// written by hand. See `marks(in:)` for what counts as "what follows".
    ///
    /// A `/` between two simple terms is stacked, so `3/4` is written as a
    /// real fraction rather than typed out sideways. See `pieces(in:)` for
    /// what counts as simple enough.
    static func path(for text: String, from origin: CGPoint, height: CGFloat) -> Path {
        let scale = height / capitalHeight

        // Where the letters actually stand, which is a little below `origin`.
        let baseline = origin.y + baselineHeight * scale

        var path = Path()
        var pen = origin.x

        for piece in pieces(in: text) {
            switch piece {
            case .mark(let mark):
                guard let glyph = glyphs[mark.character] else { continue }

                let markScale = mark.isRaised ? scale * superscriptScale : scale

                // Lift a superscript by exactly the height it lost by
                // shrinking, which puts its top level with the top of a
                // capital letter standing next to it. Any less and it reads as
                // a second digit; any more and it floats away from the line.
                let lift = mark.isRaised
                    ? (capitalHeight - capitalHeight * superscriptScale) * scale
                    : 0

                for stroke in glyph.strokes {
                    path.addLines(stroke.map { point in
                        CGPoint(
                            x: pen + (point.x - glyph.left) * markScale,
                            y: baseline - lift + (point.y - baselineHeight) * markScale
                        )
                    })
                }

                pen += (glyph.right - glyph.left) * markScale

            case .fraction(let over, let under):
                let shape = fractionShape(over: over, under: under, height: height)
                let bar = baseline - height * fractionBarHeight

                // Each half is written by this same function, one size down.
                // Neither can hold another fraction — a half is only ever a
                // simple term — so this goes exactly one level deep.
                path.addPath(StrokeFont.path(
                    for: over,
                    from: penDown(
                        x: pen + (shape.width - shape.overWidth) / 2,
                        // The numerator stands on a line just above the bar.
                        onto: bar - height * fractionGap,
                        height: shape.height
                    ),
                    height: shape.height
                ))

                path.addLines([
                    CGPoint(x: pen, y: bar),
                    CGPoint(x: pen + shape.width, y: bar),
                ])

                path.addPath(StrokeFont.path(
                    for: under,
                    from: penDown(
                        x: pen + (shape.width - shape.underWidth) / 2,
                        // The denominator hangs below it: its own line sits a
                        // full character-height further down, so that the top
                        // of it clears the bar.
                        onto: bar + height * fractionGap + shape.height,
                        height: shape.height
                    ),
                    height: shape.height
                ))

                pen += shape.width
            }
        }

        return path
    }

    /// How wide `text` will be once written.
    static func width(of text: String, height: CGFloat) -> CGFloat {
        let scale = height / capitalHeight
        var total: CGFloat = 0

        for piece in pieces(in: text) {
            switch piece {
            case .mark(let mark):
                guard let glyph = glyphs[mark.character] else { continue }

                let markScale = mark.isRaised ? scale * superscriptScale : scale
                total += (glyph.right - glyph.left) * markScale

            case .fraction(let over, let under):
                total += fractionShape(over: over, under: under, height: height).width
            }
        }

        return total
    }

    /// The size of a stacked fraction, which both drawing and measuring need.
    private static func fractionShape(
        over: String,
        under: String,
        height: CGFloat
    ) -> (height: CGFloat, width: CGFloat, overWidth: CGFloat, underWidth: CGFloat) {
        let halfHeight = height * fractionScale
        let overWidth = width(of: over, height: halfHeight)
        let underWidth = width(of: under, height: halfHeight)

        return (
            height: halfHeight,
            // The bar is drawn past whichever half is wider, the way it is by
            // hand. A bar exactly as long as the numerator reads as an
            // underline instead.
            width: max(overWidth, underWidth) + height * fractionOverhang * 2,
            overWidth: overWidth,
            underWidth: underWidth
        )
    }

    /// Where the pen touches down for writing that should stand on line `y`.
    ///
    /// `path(for:from:height:)` takes the top of the writing, not the line it
    /// stands on, so anything positioned by its baseline has to convert.
    private static func penDown(x: CGFloat, onto y: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y - baselineHeight * height / capitalHeight)
    }

    /// Break a sentence into lines that fit the page.
    ///
    /// Handwriting has no equivalent of a text view quietly wrapping for you —
    /// a path just keeps going, straight off the edge of the paper. So a
    /// sentence has to be measured and broken before any of it is drawn.
    ///
    /// Breaks between words, and never in the middle of one. A single word too
    /// long for the line is left to overhang, which is ugly but readable, and
    /// far better than the alternative of slicing a word in half.
    static func wrap(_ text: String, height: CGFloat, into maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var words = text.split(separator: " ").map(String.init)

        while !words.isEmpty {
            let taken = fit(words, height: height, into: maxWidth)
            lines.append(taken.line)
            words = taken.rest
        }

        return lines
    }

    /// As much of `words` as fits a line this wide, and whatever is left over.
    ///
    /// Separate from `wrap` because a line's width is not a property of the
    /// sentence. Writing that starts beside a student's working has only the
    /// rest of that line, while the line under it usually has the whole page —
    /// so each line has to be filled against its own room rather than every
    /// line being cut to the width of the first.
    ///
    /// Always takes at least one word, so a word too long for the line
    /// overhangs rather than leaving the caller going round forever.
    static func fit(
        _ words: [String],
        height: CGFloat,
        into maxWidth: CGFloat
    ) -> (line: String, rest: [String]) {
        var line = ""
        var taken = 0

        for word in words {
            let extended = line.isEmpty ? word : line + " " + word

            if !line.isEmpty, width(of: extended, height: height) > maxWidth { break }

            line = extended
            taken += 1
        }

        return (line, Array(words.dropFirst(taken)))
    }

    /// How many characters the pen actually puts on the page.
    ///
    /// A `^` and the braces around a superscript are instructions to this
    /// file, not marks the hand makes, so anyone timing the writing would
    /// wait too long if they counted them.
    static func writtenCharacterCount(in text: String) -> Int {
        pieces(in: text).reduce(0) { total, piece in
            switch piece {
            case .mark:
                total + 1
            // Both halves and the bar between them, since all three are drawn.
            case .fraction(let over, let under):
                total + over.count + under.count + 1
            }
        }
    }

    // MARK: - Reading the text

    /// One thing the pen writes: a character, or a fraction stacked up.
    private enum Piece {
        case mark(Mark)
        case fraction(over: String, under: String)
    }

    /// One character the pen writes, and whether it sits raised.
    private struct Mark {
        let character: Character
        let isRaised: Bool
    }

    /// Split the text into characters and fractions.
    ///
    /// A slash only becomes a fraction when both sides look like a term you
    /// would stack by hand. Most slashes are not that. "+/-" is how a plus or
    /// minus sign reaches this file, "and/or" is a word, and stacking either
    /// of them produces something nobody can read. So the test is deliberately
    /// mean, and anything that fails it is written sideways exactly as before.
    private static func pieces(in text: String) -> [Piece] {
        let characters = Array(text)

        var pieces: [Piece] = []
        var plain = ""
        var index = 0

        while index < characters.count {
            guard
                characters[index] == "/",
                let over = term(endingBefore: index, in: characters),
                let under = term(startingAfter: index, in: characters)
            else {
                plain.append(characters[index])
                index += 1
                continue
            }

            // The numerator was collected as ordinary text on the way past.
            // It belongs to the fraction, so take it back off.
            plain.removeLast(over.characters)
            pieces.append(contentsOf: marks(in: plain).map(Piece.mark))
            plain = ""

            pieces.append(.fraction(over: over.text, under: under.text))
            index += 1 + under.characters
        }

        pieces.append(contentsOf: marks(in: plain).map(Piece.mark))

        return pieces
    }

    /// Half of a fraction: what to write, and how much text it came from.
    private struct Term {
        let text: String
        let characters: Int
    }

    /// The most a half of a fraction can be. Past this it is a sentence with a
    /// slash in it rather than a fraction, whatever it looks like.
    private static let longestTerm = 8

    /// What is on the left of a slash, if it is fit to stack.
    private static func term(endingBefore slash: Int, in characters: [Character]) -> Term? {
        var end = slash
        var spaces = 0

        // "42 / 6" is how the tutor is asked to write division, so a single
        // space on either side of the slash is part of the fraction.
        if end > 0, characters[end - 1] == " " {
            end -= 1
            spaces = 1
        }

        if end > 0, characters[end - 1] == ")" {
            guard let open = openingBracket(before: end - 1, in: characters) else { return nil }

            let inside = String(characters[(open + 1)..<(end - 1)])

            // Brackets say this is a fraction on their own — nobody writes
            // (x + 1)/2 meaning anything else — so the contents are not
            // held to the same test, only to a length.
            guard !inside.isEmpty, inside.count <= longestTerm else { return nil }

            return Term(text: inside, characters: end - open + spaces)
        }

        var start = end
        while start > 0, isTermCharacter(characters[start - 1]) {
            start -= 1
        }

        let run = String(characters[start..<end])

        guard isSimpleTerm(run) else { return nil }

        return Term(text: run, characters: run.count + spaces)
    }

    /// What is on the right of a slash, if it is fit to stack.
    private static func term(startingAfter slash: Int, in characters: [Character]) -> Term? {
        var start = slash + 1
        var spaces = 0

        if start < characters.count, characters[start] == " " {
            start += 1
            spaces = 1
        }

        if start < characters.count, characters[start] == "(" {
            guard let close = closingBracket(after: start, in: characters) else { return nil }

            let inside = String(characters[(start + 1)..<close])

            guard !inside.isEmpty, inside.count <= longestTerm else { return nil }

            return Term(text: inside, characters: close - slash + spaces)
        }

        var end = start
        while end < characters.count, isTermCharacter(characters[end]) {
            end += 1
        }

        let run = String(characters[start..<end])

        guard isSimpleTerm(run) else { return nil }

        return Term(text: run, characters: run.count + spaces)
    }

    private static func isTermCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "^{}.".contains(character)
    }

    /// Whether a run of text is the kind of thing that gets stacked.
    ///
    /// A number, or something with a number in it: 3, 42, 2x, x^2. A lone
    /// letter counts too, because x/2 is an ordinary thing to write. Anything
    /// else made only of letters is a word, and words either side of a slash
    /// are two words rather than a fraction.
    private static func isSimpleTerm(_ run: String) -> Bool {
        guard !run.isEmpty, run.count <= longestTerm else { return false }

        return run.contains(where: \.isNumber) || (run.count == 1 && run.first?.isLetter == true)
    }

    private static func openingBracket(before close: Int, in characters: [Character]) -> Int? {
        var depth = 0

        for index in stride(from: close, through: 0, by: -1) {
            if characters[index] == ")" { depth += 1 }
            if characters[index] == "(" {
                depth -= 1
                if depth == 0 { return index }
            }
        }

        return nil
    }

    private static func closingBracket(after open: Int, in characters: [Character]) -> Int? {
        var depth = 0

        for index in open..<characters.count {
            if characters[index] == "(" { depth += 1 }
            if characters[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }

        return nil
    }

    /// Work out which characters are raised, before anything is drawn.
    ///
    /// A `^` raises the single character after it, so `x^2 + 1` puts only the
    /// 2 up and the `+ 1` back on the line. Braces raise a whole group, which
    /// is the only way to write `x^{10}` or `x^{n+1}`.
    ///
    /// Braces are only special straight after a `^`; anywhere else they are
    /// written as ordinary braces, as they always were.
    ///
    /// There is no second level: a `^` inside a group is written as a caret.
    /// Powers of powers are not something this app has to write, and pretending
    /// to support them would cost more than it is worth.
    private static func marks(in text: String) -> [Mark] {
        let characters = Array(text)

        var marks: [Mark] = []
        var index = 0

        // Every branch below moves `index` forward, so malformed input runs
        // off the end of the text rather than going round forever.
        while index < characters.count {
            guard characters[index] == "^" else {
                marks.append(Mark(character: characters[index], isRaised: false))
                index += 1
                continue
            }

            // Step over the ^ itself. It says what to do; it is not written.
            index += 1

            // A ^ with nothing after it raises nothing, and is simply dropped.
            guard index < characters.count else { break }

            if characters[index] == "{" {
                index += 1

                while index < characters.count && characters[index] != "}" {
                    marks.append(Mark(character: characters[index], isRaised: true))
                    index += 1
                }

                // Step over the closing brace. If the text ran out first the
                // brace was never closed, and everything to the end of the
                // line stays raised — wrong, but readable, and it still ends.
                if index < characters.count {
                    index += 1
                }
            } else {
                marks.append(Mark(character: characters[index], isRaised: true))
                index += 1
            }
        }

        return marks
    }

    // MARK: - Reading the font file

    /// Unpack the font file into a glyph for each character.
    ///
    /// The format is from an era that counted every byte, so it is terse but
    /// simple. One line per character, and every number is a single letter:
    ///
    ///     ...8 characters of bookkeeping...  then pairs of letters
    ///
    /// Each letter stands for a number, counting from "R" — so "R" is 0, "S" is
    /// 1, "Q" is -1. Pairs of them make an x and a y. The pair " R" is special:
    /// it means lift the pen, which is how one character can be more than one
    /// unbroken line.
    private static func readFontFile() -> [Character: Glyph] {
        guard
            let url = Bundle.main.url(forResource: fontName, withExtension: "jhf"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return [:]
        }

        var glyphs: [Character: Glyph] = [:]

        for (lineNumber, line) in contents.split(separator: "\n").enumerated() {
            // Characters are listed in ASCII order, starting at the space.
            let character = Character(UnicodeScalar(UInt8(32 + lineNumber)))

            // The first 8 characters are a serial number and a point count,
            // neither of which we need — the pairs that follow tell us both.
            let values = Array(line.dropFirst(8))
            guard values.count >= 2 else { continue }

            var strokes: [[CGPoint]] = []
            var current: [CGPoint] = []

            // The very first pair is not a point: it is the left and right
            // edges, which say how far to move the pen for the next character.
            for index in stride(from: 2, to: values.count - 1, by: 2) {
                if values[index] == " " {
                    if !current.isEmpty { strokes.append(current) }
                    current = []
                } else {
                    current.append(CGPoint(
                        x: number(values[index]),
                        y: number(values[index + 1])
                    ))
                }
            }
            if !current.isEmpty { strokes.append(current) }

            glyphs[character] = Glyph(
                strokes: strokes,
                left: number(values[0]),
                right: number(values[1])
            )
        }

        return glyphs
    }

    /// "R" is zero, and every other letter counts up or down from it.
    private static func number(_ character: Character) -> CGFloat {
        CGFloat(Int(character.asciiValue ?? 82) - 82)
    }
}
