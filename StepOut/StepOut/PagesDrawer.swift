import SwiftUI

/// The notebook's contents, sliding over the page when Pages is tapped.
///
/// Starts empty and stays empty until the student puts something in it. There
/// is no set of questions shipped with the app: the questions worth doing are
/// the ones on their own homework, and those arrive by photograph.
struct PagesDrawer: View {
    let pages: [Page]
    let currentPageID: UUID?

    let onSelect: (Page) -> Void
    let onAddNotes: () -> Void
    let onAddQuestion: () -> Void
    let onRename: (Page) -> Void
    let onDelete: (Page) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.ink.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                header

                if pages.isEmpty {
                    empty
                } else {
                    list
                }

                addButtons
            }
            .frame(width: 320)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
        }
    }

    private var header: some View {
        HStack {
            Text("Pages")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.yellow, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.sky)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.ink.opacity(0.4))

            Text("Nothing in here yet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)

            Text("Photograph your homework and the questions on it become pages. Or start a page of your own.")
                .font(.footnote)
                .foregroundStyle(Theme.ink.opacity(0.6))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { number, page in
                    Button {
                        onSelect(page)
                        onClose()
                    } label: {
                        row(for: page, number: number + 1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename") { onRename(page) }
                        Button("Delete", role: .destructive) { onDelete(page) }
                    }
                }
            }
            .padding(16)
        }
    }

    private var addButtons: some View {
        HStack(spacing: 10) {
            add("Notes page", symbol: "note.text", action: onAddNotes)
            add("Question", symbol: "function", action: onAddQuestion)
        }
        .padding(16)
        .background(Theme.sky.opacity(0.4))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
        }
    }

    private func add(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func row(for page: Page, number: Int) -> some View {
        let chosen = page.id == currentPageID

        return HStack(spacing: 12) {
            Image(systemName: page.isQuestion ? "function" : "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.7))
                .frame(width: 22)

            Text(page.name)
                .font(.callout.weight(chosen ? .bold : .regular))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if page.solved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.13, green: 0.52, blue: 0.32))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            chosen ? Theme.yellow : Theme.paper,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: chosen ? Theme.outline : 1)
        )
    }
}
