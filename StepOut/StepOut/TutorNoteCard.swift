import SwiftUI

/// A single tutor message. No floating chrome — gestures only.
///
/// - Double-tap: collapse to one line / expand again
/// - Long-press: remove, or peek at the AI prompt
struct TutorNoteCard: View {
    let note: TutorNote
    let onToggleCollapsed: () -> Void
    let onRemove: () -> Void

    @State private var showPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.text)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(note.isCollapsed ? 1 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showPrompt, let prompt = note.prompt {
                Text(prompt)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if note.isCollapsed {
                Text("Double-tap to open")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.pink.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.pink.opacity(0.18), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) {
            onToggleCollapsed()
        }
        .contextMenu {
            Button(note.isCollapsed ? "Expand" : "Collapse to one line") {
                onToggleCollapsed()
            }

            if note.prompt != nil {
                Button(showPrompt ? "Hide AI prompt" : "Show AI prompt") {
                    showPrompt.toggle()
                    onTogglePrompt()
                }
            }

            Divider()

            Button("Remove", role: .destructive) {
                onRemove()
            }
        }
    }
}

struct TutorNotesSection: View {
    @Binding var notes: [TutorNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tutor")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(notes) { note in
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    TutorNoteCard(
                        note: note,
                        onToggleCollapsed: {
                            notes[index].isCollapsed.toggle()
                        },
                        onRemove: {
                            withAnimation(.snappy) {
                                notes.remove(at: index)
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
    }
}
