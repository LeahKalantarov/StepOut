import PhotosUI
import SwiftUI

/// Where the app opens: everything you have worked on, and a way into more.
///
/// Sessions newest first, because the work you are most likely to open is the
/// work you last put down.
struct Dashboard: View {
    let library: Library
    let chart: Chart

    @Binding var photo: PhotosPickerItem?
    let readingPhoto: Bool

    let onOpen: (Session) -> Void
    let onNew: () -> Void
    let onRename: (Session) -> Void
    let onDelete: (Session) -> Void
    let onSettings: () -> Void

    // The session waiting to be thrown away, if one has been asked for. Asked
    // rather than done: everything written in a session goes with it, and there
    // is no undo once it is off the disk.
    @State private var deleting: Session?

    var body: some View {
        ZStack {
            Theme.sky.opacity(0.3).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if chart.solved + chart.slips > 0 {
                        progress
                    }

                    start

                    if library.sessions.isEmpty {
                        empty
                    } else {
                        sessions
                    }
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "Delete this?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleting
        ) { session in
            Button("Delete", role: .destructive) { onDelete(session) }
            Button("Keep it", role: .cancel) {}
        } message: { session in
            Text("Every page in it goes too — \(session.summary). This cannot be undone.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        // Topped rather than baselined: the name is artwork now, and artwork
        // has no text baseline for the settings button to line up against.
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                // Drawn rather than typed, because the blocks are part of the
                // name and the spacing between them has to hold. 40pt is the
                // artwork's own height, so it lands on whole pixels and the
                // block outlines stay sharp.
                Image("Wordmark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 40)
                    .accessibilityLabel("StepOut")

                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink.opacity(0.6))

                Text(AppBuild.marker)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink.opacity(0.35))
            }

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.paper, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .buttonStyle(.plain)
        }
    }

    private var greeting: String {
        library.sessions.isEmpty
            ? "Let's get started."
            : "Pick up where you left off."
    }

    /// The chart, as three numbers. The same record the tutor reads.
    private var progress: some View {
        HStack(spacing: 12) {
            tile("\(chart.solved)", "solved", Theme.yellow)
            tile("\(chart.slips)", "steps caught", Theme.pink)
            tile("\(library.sessions.count)", "sessions", Theme.sky)
        }
    }

    private func tile(_ number: String, _ label: String, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(colour, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: Theme.outline)
        )
    }

    private var start: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                big(
                    readingPhoto ? "Reading…" : "Photograph homework",
                    detail: "Turn a worksheet into pages you can work on",
                    symbol: "camera.fill",
                    colour: Theme.pink
                )
            }
            .buttonStyle(.plain)
            .disabled(readingPhoto)
            .opacity(readingPhoto ? 0.6 : 1)

            Button(action: onNew) {
                big(
                    "Blank session",
                    detail: "Start with an empty page",
                    symbol: "square.and.pencil",
                    colour: Theme.paper
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func big(
        _ title: String,
        detail: String,
        symbol: String,
        colour: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.65))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(colour, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: Theme.outline)
        )
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            Text("Photograph a page of homework and every question on it becomes a page you can work through, with the notes beside it.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your work")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            ForEach(library.byMostRecent) { session in
                Button {
                    onOpen(session)
                } label: {
                    row(for: session)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") { onRename(session) }
                    Button("Delete", role: .destructive) { deleting = session }
                }
                // Laid over the row rather than inside it, so that a tap on the
                // menu is not also a tap on the session behind it. A menu can
                // live inside a button, but only the button ever hears about it.
                .overlay(alignment: .trailing) {
                    rowMenu(for: session)
                        .padding(.trailing, 14)
                }
            }
        }
    }

    /// Rename and delete, on the row itself.
    ///
    /// Both were on a long press and nowhere else, which is a fine shortcut and
    /// a poor way to be told something exists — a page of work you cannot see
    /// how to throw away is a page you are stuck with.
    private func rowMenu(for session: Session) -> some View {
        Menu {
            Button("Rename") { onRename(session) }
            Button("Delete", role: .destructive) { deleting = session }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink.opacity(0.6))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func row(for session: Session) -> some View {
        HStack(spacing: 14) {
            Image(systemName: session.isFinished ? "checkmark.seal.fill" : "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(session.isFinished ? Theme.yellow : Theme.sky, in: Circle())
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(session.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.6))
            }

            Spacer(minLength: 0)

            Text(session.started.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.45))

            // Room down the right for the menu that sits over this row.
            Color.clear.frame(width: 30, height: 1)
        }
        .padding(14)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: 1.5)
        )
    }
}
