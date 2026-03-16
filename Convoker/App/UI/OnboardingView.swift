import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .tutorial:
                tutorialContent
            case .whatsNew:
                whatsNewContent
            }
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - Tutorial

    private var tutorialContent: some View {
        VStack(spacing: 0) {
            progressBar

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(viewModel.currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            Divider()

            bottomBar
        }
    }

    private var progressBar: some View {
        let total = OnboardingStep.allCases.count
        let current = viewModel.currentStep.rawValue

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * CGFloat(current) / CGFloat(total - 1))
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
        .frame(height: 4)
    }

    private var stepContent: some View {
        let step = viewModel.currentStep

        return VStack(spacing: 16) {
            Spacer()

            Image(systemName: step.iconName)
                .font(.system(size: 48))
                .foregroundStyle(step == .complete ? .green : .accentColor)

            Text(step.title)
                .font(.system(size: 24, weight: .semibold))

            Text(step.description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            if let hint = step.shortcutHint {
                shortcutBadge(hint)
                    .padding(.top, 4)
            }

            if step.isInteractive && !viewModel.stepCompleted {
                Text("Try it now!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
                    .opacity(0.8)
                    .padding(.top, 8)
            }

            if viewModel.stepCompleted {
                Label("Nice!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func shortcutBadge(_ hint: String) -> some View {
        Text(hint)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(8)
    }

    private var bottomBar: some View {
        HStack {
            if viewModel.currentStep != .complete {
                Button("Skip Tutorial") {
                    viewModel.skipTutorial()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            } else {
                Spacer().frame(width: 100)
            }

            Spacer()

            Text("\(viewModel.currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()

            if viewModel.currentStep.isInteractive {
                if viewModel.stepCompleted {
                    Label("Done!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("Waiting for action...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(viewModel.currentStep == .complete ? "Done" :
                       viewModel.currentStep == .welcome ? "Let's Go" : "Next") {
                    if viewModel.currentStep == .complete {
                        viewModel.skipTutorial()
                    } else {
                        viewModel.advanceStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - What's New

    private var whatsNewContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)
                Text("What's New in Convoker")
                    .font(.system(size: 24, weight: .semibold))
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(viewModel.whatsNewFeatures.enumerated()), id: \.offset) { _, feature in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: feature.iconName)
                                .font(.system(size: 24))
                                .foregroundColor(.accentColor)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(feature.description)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Got It") {
                    viewModel.dismissWhatsNew()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}
