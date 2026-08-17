import Foundation
import Observation

/// Everything the student has ever done, and where they left off.
///
/// One object owns the lot, because the dashboard and the page it opens are
/// two views of the same thing: close a session having solved something, and
/// the tick has to be waiting on the dashboard when you get back.
///
/// The work is kept beside the sessions rather than inside them. A page is a
/// small thing — a name and a question — and its ink is not; keeping them
/// apart means the dashboard can list a hundred pages without reading a
/// hundred drawings into memory to do it.
@Observable
final class Library {
    var sessions: [Session] = []
    var work: [UUID: PageWork] = [:]

    /// Which session is open. Nil means the dashboard.
    var openSession: UUID?

    init() {
        guard let saved = LibraryStore.load() ?? LibraryStore.loadOldNotebook() else { return }

        sessions = saved.sessions

        // Writing done in an earlier sitting has already happened. Replaying
        // it stroke by stroke on launch would be a small lie, and a slow one
        // on a page with a whole lesson on it.
        work = saved.work.mapValues { page in
            var page = page
            page.tutorLines = page.tutorLines.map {
                var line = $0
                line.written = true
                return line
            }
            return page
        }

        tidyNames()
    }

    /// Give every session still carrying its date a name off its own work.
    ///
    /// Sessions were named after the day they were started, which is useful
    /// for about a day. A dashboard of "Thursday 13 Aug" and "Friday 14 Aug"
    /// tells you when you sat down and nothing about what you sat down to, so
    /// finding the quadratics again means opening three of them.
    ///
    /// Only ever touches names nobody chose. A session somebody has renamed by
    /// hand keeps that name whatever is written inside it.
    private func tidyNames() {
        var renamed = false

        for at in sessions.indices where Library.isAutomatic(sessions[at]) {
            let sheet = sessions[at].pages.compactMap { work[$0.id]?.sheet?.title }.first
            let title = sheet ?? sessions[at].questions.first?.name

            guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }

            sessions[at].name = title
            renamed = true
        }

        if renamed { save() }
    }

    // MARK: - Reading

    var current: Session? {
        sessions.first { $0.id == openSession }
    }

    var pages: [Page] {
        current?.pages ?? []
    }

    /// Sessions newest first, which is the order you want them in: the work
    /// you are most likely to open is the work you last put down.
    var byMostRecent: [Session] {
        sessions.sorted { $0.started > $1.started }
    }

    // MARK: - Writing

    func add(_ session: Session) {
        sessions.append(session)
        save()
    }

    func remove(_ session: Session) {
        for page in session.pages {
            work.removeValue(forKey: page.id)
        }

        sessions.removeAll { $0.id == session.id }

        if openSession == session.id {
            openSession = nil
        }

        save()
    }

    /// Change the open session in place.
    ///
    /// Everything that edits a session goes through here, so there is one
    /// place that knows how to find it and one place that saves afterwards.
    func change(_ edit: (inout Session) -> Void) {
        guard let at = sessions.firstIndex(where: { $0.id == openSession }) else { return }

        edit(&sessions[at])
        save()
    }

    func rename(_ session: Session, to name: String) {
        let wanted = name.trimmingCharacters(in: .whitespaces)

        guard
            !wanted.isEmpty,
            let at = sessions.firstIndex(where: { $0.id == session.id })
        else {
            return
        }

        sessions[at].name = wanted
        save()
    }

    func save() {
        LibraryStore.save(SavedLibrary(sessions: sessions, work: work))
    }

    /// Name the open session after the work that has just landed in it.
    ///
    /// A session is made before its photograph has been read, so the only
    /// thing there is to call it at that point is the date. This is the second
    /// chance, once there is a title on the notes to use instead.
    func nameOpenSession(after title: String) {
        let wanted = title.trimmingCharacters(in: .whitespaces)

        guard !wanted.isEmpty else { return }

        change { session in
            guard Library.isAutomatic(session) else { return }

            session.name = wanted
        }
    }

    /// A name for a session with nothing in it yet to name it after. Today's
    /// date reads better than "Session 4" and tells you something "Session 4"
    /// does not.
    func nameForNewSession() -> String {
        Library.dateName(for: Date())
    }

    /// Whether a session is still called what the app called it.
    static func isAutomatic(_ session: Session) -> Bool {
        session.name == dateName(for: session.started)
    }

    static func dateName(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// The library as it is written to disk.
struct SavedLibrary: Codable {
    var sessions: [Session] = []
    var work: [UUID: PageWork] = [:]
}

/// Reading and writing the library.
///
/// A file rather than UserDefaults, because a page of handwriting runs to
/// hundreds of kilobytes once PencilKit has stored every stroke, and
/// UserDefaults is a preferences store — read into memory whole at launch, and
/// the wrong place to keep a notebook.
///
/// Nothing here throws. A library that cannot be read is a library that starts
/// empty, which is bad but survivable; an app that will not open because of it
/// is worse.
enum LibraryStore {
    private static let name = "library.json"

    static func load() -> SavedLibrary? {
        guard
            let url = fileURL(named: name),
            let saved = try? Data(contentsOf: url),
            let library = try? JSONDecoder().decode(SavedLibrary.self, from: saved)
        else {
            return nil
        }

        return library
    }

    /// Work saved before there were sessions, gathered into one.
    ///
    /// Only reached when there is no library yet, so it runs once: the first
    /// save afterwards writes a real library and this is never asked again.
    /// The old file is left where it is — deleting a student's only copy of
    /// their work to tidy up is not a trade worth making.
    static func loadOldNotebook() -> SavedLibrary? {
        struct Notebook: Codable {
            var pages: [Page] = []
            var work: [UUID: PageWork] = [:]
            var openPage: UUID?
        }

        guard
            let url = fileURL(named: "notebook.json"),
            let saved = try? Data(contentsOf: url),
            let old = try? JSONDecoder().decode(Notebook.self, from: saved),
            !old.pages.isEmpty
        else {
            return nil
        }

        let session = Session(
            name: "Earlier work",
            pages: old.pages,
            openPage: old.openPage
        )

        return SavedLibrary(sessions: [session], work: old.work)
    }

    static func save(_ library: SavedLibrary) {
        guard let url = fileURL(named: name), let written = try? JSONEncoder().encode(library) else {
            return
        }

        try? written.write(to: url, options: .atomic)
    }

    /// Where the app's files live, making the folder if this is the first run.
    ///
    /// Application Support rather than Documents: this is the app's own store,
    /// not a set of files the student would expect to see and manage.
    private static func fileURL(named file: String) -> URL? {
        let manager = FileManager.default

        guard
            let folder = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        if !manager.fileExists(atPath: folder.path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        return folder.appendingPathComponent(file)
    }
}
