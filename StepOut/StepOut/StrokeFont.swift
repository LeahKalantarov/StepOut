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

    private static let glyphs = readFontFile()

    /// The path that writes `text`, resting on a baseline starting at `origin`.
    ///
    /// Letters like g and y dip below the baseline, and every letter body sits
    /// above it, which is exactly how the font stores them — so `origin` is the
    /// point where the pen would touch down on a ruled line.
    ///
    /// A `^` raises what follows, so `a^2 - b^2` writes the way it would be
    /// written by hand. See `marks(in:)` for what counts as "what follows".
    static func path(for text: String, from origin: CGPoint, height: CGFloat) -> Path {
        let scale = height / capitalHeight

        // Where the letters actually stand, which is a little below `origin`.
        let baseline = origin.y + baselineHeight * scale

        var path = Path()
        var pen = origin.x

        for mark in marks(in: text) {
            guard let glyph = glyphs[mark.character] else { continue }

            let markScale = mark.isRaised ? scale * superscriptScale : scale

            // Lift a superscript by exactly the height it lost by shrinking,
            // which puts its top level with the top of a capital letter
            // standing next to it. Any less and it reads as a second digit;
            // any more and it floats away from the line.
            let lift = mark.isRaised ? (capitalHeight - capitalHeight * superscriptScale) * scale : 0

            for stroke in glyph.strokes {
                path.addLines(stroke.map { point in
                    CGPoint(
                        x: pen + (point.x - glyph.left) * markScale,
                        y: baseline - lift + (point.y - baselineHeight) * markScale
                    )
                })
            }

            pen += (glyph.right - glyph.left) * markScale
        }

        return path
    }

    /// How wide `text` will be once written.
    static func width(of text: String, height: CGFloat) -> CGFloat {
        let scale = height / capitalHeight
        var total: CGFloat = 0

        for mark in marks(in: text) {
            guard let glyph = glyphs[mark.character] else { continue }

            let markScale = mark.isRaised ? scale * superscriptScale : scale
            total += (glyph.right - glyph.left) * markScale
        }

        return total
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
        var line = ""

        for word in text.split(separator: " ") {
            let extended = line.isEmpty ? String(word) : line + " " + word

            if line.isEmpty || width(of: extended, height: height) <= maxWidth {
                line = extended
            } else {
                lines.append(line)
                line = String(word)
            }
        }

        if !line.isEmpty {
            lines.append(line)
        }

        return lines
    }

    /// How many characters the pen actually puts on the page.
    ///
    /// A `^` and the braces around a superscript are instructions to this
    /// file, not marks the hand makes, so anyone timing the writing would
    /// wait too long if they counted them.
    static func writtenCharacterCount(in text: String) -> Int {
        marks(in: text).count
    }

    // MARK: - Reading the text

    /// One character the pen writes, and whether it sits raised.
    private struct Mark {
        let character: Character
        let isRaised: Bool
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
