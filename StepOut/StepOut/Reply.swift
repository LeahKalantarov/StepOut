/// What the student wrote back when the tutor offered to help.
///
/// Only the two answers to that question. Anything else written under it is
/// not a reply at all — most likely another go at the step — and is left be.
enum Reply {
    case yes
    case no

    /// Read a written reply, or nil if it wasn't one.
    ///
    /// "yes" was the only word that worked, which is not how anybody answers a
    /// question. People write yeah, yep, sure, ok, or just a tick, and being
    /// ignored for it looks exactly like the app being broken.
    ///
    /// Matched whole rather than by prefix. A prefix rule reads "note" as no
    /// and "yet" as yes, and mistaking a line of working for a reply is much
    /// worse than missing a reply: it throws a lesson onto the page in the
    /// middle of the student's own writing.
    static func read(_ words: [String]) -> Reply? {
        let said = words.joined().lowercased().filter(\.isLetter)

        // A tick means yes wherever it turns up. Kept off the letters-only
        // path above, since it isn't one.
        if words.contains(where: { $0.contains("✓") || $0.contains("✔") }) {
            return .yes
        }

        if yesWords.contains(said) { return .yes }
        if noWords.contains(said) { return .no }

        return nil
    }

    /// Spaces are already gone by the time these are compared, so "yes please"
    /// is looked up as "yesplease".
    private static let yesWords: Set<String> = [
        "y", "ya", "yah", "yeah", "yeh", "yea", "yes", "yess", "yep", "yup",
        "ok", "okay", "okey", "k", "kk", "sure", "please", "pls", "plz",
        "yesplease", "okthanks", "alright", "aight", "definitely", "absolutely",
        "go", "goahead", "goon", "doit", "showme", "tellme", "explain",
        "help", "helpme", "iwanthelp", "ineedhelp",
    ]

    private static let noWords: Set<String> = [
        "n", "no", "nope", "nah", "naw", "nothanks", "nothx", "noty",
        "nevermind", "nvm", "notnow", "later", "imgood", "imok", "imfine",
        "ivegotit", "gotit", "illtry", "letmetry", "stop",
    ]
}
