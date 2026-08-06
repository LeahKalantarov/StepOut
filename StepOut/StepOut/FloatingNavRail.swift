import SwiftUI

/// The colourful circles on the notebook's left edge — mockup B.
struct FloatingNavRail: View {
    @Binding var showQuestions: Bool
    @Binding var tutorApart: Bool
    @Binding var showMore: Bool

    let isChecking: Bool
    let onCheck: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            railButton(
                icon: "list.bullet",
                fill: Theme.sky,
                isOn: showQuestions
            ) {
                showQuestions.toggle()
            }

            railButton(
                icon: "graduationcap.fill",
                fill: Theme.pink,
                isOn: tutorApart
            ) {
                tutorApart.toggle()
            }

            railButton(
                icon: isChecking ? "hourglass" : "checkmark",
                fill: Theme.yellow,
                isOn: false,
                disabled: isChecking
            ) {
                onCheck()
            }

            railButton(
                icon: "ellipsis",
                fill: Theme.panel,
                isOn: showMore
            ) {
                showMore.toggle()
            }
        }
    }

    private func railButton(
        icon: String,
        fill: Color,
        isOn: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(fill, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Theme.ink, lineWidth: isOn ? 3 : Theme.outline)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}
