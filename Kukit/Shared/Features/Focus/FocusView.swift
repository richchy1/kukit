import SwiftUI
import KukitCore

/// The Focus screen: the full-size timer, Chef Kukit, technique choices and music.
struct FocusView: View {
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.keepScreenAwake) private var keepAwake = true

    private var state: TimerState { timer.state }

    var body: some View {
        ScrollView {
            FocusCard(style: .immersive)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .background(wash.ignoresSafeArea())
        .navigationTitle("Focus")
        .onAppear(perform: updateAwake)
        .onDisappear { ScreenAwake.set(false) }
        .onChange(of: state.status) { updateAwake() }
        .onChange(of: keepAwake) { updateAwake() }
    }

    /// The room warms up while you cook and cools to green on a break.
    private var wash: some View {
        ZStack {
            KukitBackground()
            if state.status == .running || state.status == .paused {
                LinearGradient(
                    colors: [(state.phase.isBreak ? Theme.basil : Theme.accent).opacity(0.14), .clear],
                    startPoint: .top, endPoint: .center
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: state.phase)
        .animation(.easeInOut(duration: 0.6), value: state.status)
    }

    private func updateAwake() {
        ScreenAwake.set(keepAwake && state.status == .running)
    }
}
