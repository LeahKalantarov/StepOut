/// Something the tutor has offered and is waiting on an answer to.
///
/// Both offers are answered the same way — a yes or a no — so they share one
/// mechanism, and only what a yes leads to differs.
enum Offer {
    /// Help with a mistake the checker found. Yes brings a lesson.
    case help(HelpContext)

    /// To work an example through. Yes brings that example.
    case example(Question)
}
