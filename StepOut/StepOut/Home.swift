import PhotosUI
import SwiftUI

/// The app: the dashboard, or the session you opened from it.
///
/// The library and the chart are owned here rather than by either screen,
/// because both screens are looking at the same two things. Solve a question
/// and the tick has to be waiting on the dashboard when you come back out.
struct Home: View {
    @State private var library = Library()
    @State private var record = ChartKeeper()

    // A photograph chosen on the dashboard, handed to the session it starts.
    @State private var photo: PhotosPickerItem?
    @State private var arriving: UIImage?
    @State private var readingPhoto = false

    @State private var renaming: Session?
    @State private var typed = ""
    @State private var showSettings = false

    @AppStorage("tutorVoice") private var voice = Voice.encouraging
    @AppStorage("marking") private var marking = Marking.onAsk

    var body: some View {
        Group {
            if library.openSession != nil {
                ContentView(
                    library: library,
                    record: record,
                    arriving: $arriving,
                    onClose: { library.openSession = nil }
                )
                // A session gets a page view of its own. Without this, opening
                // a second session would inherit the first one's ink, marks,
                // and half-finished lesson.
                .id(library.openSession)
            } else {
                dashboard
            }
        }
        .onChange(of: photo) { _, picked in
            guard let picked else { return }

            Task { await start(from: picked) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                voice: $voice,
                marking: $marking,
                chart: record.chart,
                onForget: { record.forget() },
                onClose: { showSettings = false }
            )
        }
        .alert(
            "Rename session",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ),
            presenting: renaming
        ) { session in
            TextField("Name", text: $typed)

            Button("Rename") { library.rename(session, to: typed) }
            Button("Cancel", role: .cancel) {}
        }
        .tint(Theme.pink)
    }

    private var dashboard: some View {
        Dashboard(
            library: library,
            chart: record.chart,
            photo: $photo,
            readingPhoto: readingPhoto,
            onOpen: { library.openSession = $0.id },
            onNew: newSession,
            onRename: { renaming = $0; typed = $0.name },
            onDelete: library.remove,
            onSettings: { showSettings = true }
        )
    }

    // MARK: - Starting work

    private func newSession() {
        let session = Session(name: library.nameForNewSession(), pages: [.notes()])

        library.add(session)
        library.openSession = session.id
    }

    /// Turn a photograph into a session and open it.
    ///
    /// The picture is only loaded here — reading it is the session's job, and
    /// happens once there is a page to put the result on. That keeps one copy
    /// of that flow instead of a dashboard version and a page version.
    private func start(from picked: PhotosPickerItem) async {
        readingPhoto = true

        defer {
            readingPhoto = false
            // Cleared so choosing the same picture twice still counts.
            photo = nil
        }

        guard
            let data = try? await picked.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return
        }

        let session = Session(name: library.nameForNewSession())

        library.add(session)
        arriving = image
        library.openSession = session.id
    }
}
