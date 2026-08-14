import SwiftUI

/// Everything about how the app behaves rather than what is on the page.
///
/// Two settings, and both are about being taught rather than about the maths:
/// when the tutor speaks up, and how it sounds when it does. Neither changes
/// the marking — that is done by a computer algebra system and is the same
/// whoever is being taught.
struct SettingsSheet: View {
    @Binding var voice: Voice
    @Binding var marking: Marking
    let chart: Chart
    let onForget: () -> Void
    let onClose: () -> Void

    @State private var confirmingForget = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("When should your work be checked?")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)

                    ForEach(Marking.allCases) { option in
                        Button {
                            marking = option
                        } label: {
                            row(
                                name: option.name,
                                summary: option.summary,
                                symbol: option.symbol,
                                chosen: option == marking
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Check is always there either way. Checking as you go only means you don't have to remember to tap it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink.opacity(0.55))
                        .padding(.top, 4)

                    Divider().padding(.vertical, 10)

                    Text("How should the tutor talk to you?")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)

                    ForEach(Voice.allCases) { option in
                        Button {
                            voice = option
                        } label: {
                            row(
                                name: option.name,
                                summary: option.summary,
                                symbol: option.symbol,
                                chosen: option == voice
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Your working is marked the same way whichever you pick. This only changes how the tutor says it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink.opacity(0.55))
                        .padding(.top, 4)

                    Divider().padding(.vertical, 10)

                    yourRecord
                }
                .padding(20)
            }
            .background(Theme.sky.opacity(0.25))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .confirmationDialog(
                "Start the tutor off with a blank chart?",
                isPresented: $confirmingForget,
                titleVisibility: .visible
            ) {
                Button("Clear my record", role: .destructive, action: onForget)
                Button("Keep it", role: .cancel) {}
            }
        }
    }

    /// What the tutor remembers, shown back to the student.
    ///
    /// A record kept about someone that they cannot read is a different and
    /// worse thing than a record kept for them. All of this is on the iPad and
    /// all of it can be thrown away here.
    private var yourRecord: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the tutor remembers")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            if chart.solved + chart.slips == 0 {
                Text("Nothing yet. Once you have worked through a few questions, the tutor will start noticing what trips you up.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.65))
            } else {
                fact("\(chart.solved) question(s) finished")
                fact("\(chart.slips) step(s) marked wrong")

                ForEach(chart.habits.prefix(3), id: \.reason) { habit in
                    fact("\(habit.times)× \(habit.reason)")
                }

                Button("Clear my record") { confirmingForget = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }

            Text("Kept on this iPad. The tutor is told a short summary so it can spot a mistake you have made before.")
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.5))
                .padding(.top, 2)
        }
    }

    private func fact(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.ink.opacity(0.4))
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.ink.opacity(0.8))
        }
    }

    private func row(
        name: String,
        summary: String,
        symbol: String,
        chosen: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(chosen ? Theme.pink : Theme.paper, in: Circle())
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)

                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if chosen {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(14)
        .background(
            chosen ? Theme.yellow : Theme.paper,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: chosen ? Theme.outline : 1)
        )
    }
}
