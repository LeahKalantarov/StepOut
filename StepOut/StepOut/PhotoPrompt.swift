import PencilKit
import SwiftUI

/// A picture waiting to be asked about.
///
/// A wrapper only so it can be handed to a sheet, which needs something it can
/// tell apart from the last one.
struct ChosenPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Asks what to do with a page that has just been photographed.
///
/// The same picture can be wanted for opposite reasons. A worksheet is usually
/// "copy these out so I can do them"; a revision sheet covered in formulas is
/// usually "explain this and then test me on it". Guessing between them is a
/// coin toss, and guessing wrong wastes the upload.
///
/// Writable as well as typeable, because the Pencil is already in their hand
/// and putting it down to reach for a keyboard is a small thing that stops
/// people bothering.
struct PhotoPrompt: View {
    let picture: UIImage

    /// What they asked for. Empty means they skipped, and the page is left to
    /// speak for itself.
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var typed = ""
    @State private var scribble = PKCanvasView()
    @State private var reading = false

    /// Ready-made answers, for the times nobody wants to write a sentence.
    private let suggestions = [
        "Copy these questions out so I can do them",
        "Explain this page and then give me questions to practice",
        "Teach me this, I don't understand it",
        "Just give me harder questions on this",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.ink, lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity)

                    section("Write it") {
                        Scribble(canvas: scribble)
                            .frame(height: 110)
                            .background(Theme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.ink, lineWidth: Theme.outline)
                            )

                        Button("Clear") {
                            scribble.drawing = PKDrawing()
                        }
                        .font(.footnote)
                        .disabled(scribble.drawing.strokes.isEmpty)
                    }

                    section("Or type it") {
                        TextField("What should I do with this page?", text: $typed, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Theme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.ink, lineWidth: 1)
                            )
                    }

                    section("Or pick one") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                typed = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        typed == suggestion ? Theme.yellow : Theme.paper,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Theme.ink, lineWidth: typed == suggestion ? Theme.outline : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.sky.opacity(0.25))
            .navigationTitle("What should I do with this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(reading ? "Reading…" : "Go") {
                        Task { await send() }
                    }
                    .disabled(reading)
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink.opacity(0.6))

            content()
        }
    }

    /// Read anything handwritten, and send whichever instruction there is.
    ///
    /// Typing wins when both are there. It arrived without going through a
    /// recognizer, so it is the one we are sure of.
    private func send() async {
        let written = typed.trimmingCharacters(in: .whitespacesAndNewlines)

        if !written.isEmpty {
            onSend(written)
            return
        }

        let strokes = scribble.drawing.strokes

        guard !strokes.isEmpty else {
            onSend("")
            return
        }

        reading = true
        defer { reading = false }

        let words = (try? await readWords([RowData(strokes: strokes.asCoordinates())])) ?? []

        onSend(words.joined(separator: " "))
    }
}

/// A small patch of paper to write an instruction on.
private struct Scribble: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {}
}
