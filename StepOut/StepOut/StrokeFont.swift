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
/// stored as the line the pen follows. That is exactly what we need. They are
/// public domain, and `cursive.jhf` is the joined-up handwriting one.
///
/// The file is unmodified, from github.com/kamalmostafa/hershey-fonts.
enum StrokeFont {

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

    private static let glyphs = readFontFile()

    /// The path that writes `text`, resting on a baseline starting at `origin`.
    ///
    /// Letters like g and y dip below the baseline, and every letter body sits
    /// above it, which is exactly how the font stores them — so `origin` is the
    /// point where the pen would touch down on a ruled line.
    static func path(for text: String, from origin: CGPoint, height: CGFloat) -> Path {
        let scale = height / capitalHeight

        var path = Path()
        var pen = origin.x

        for character in text {
            guard let glyph = glyphs[character] else { continue }

            for stroke in glyph.strokes {
                path.addLines(stroke.map { point in
                    CGPoint(
                        x: pen + (point.x - glyph.left) * scale,
                        y: origin.y + point.y * scale
                    )
                })
            }

            pen += (glyph.right - glyph.left) * scale
        }

        return path
    }

    // MARK: - Reading the font file

    /// Unpack cursive.jhf into a glyph for each character.
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
            let url = Bundle.main.url(forResource: "cursive", withExtension: "jhf"),
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
