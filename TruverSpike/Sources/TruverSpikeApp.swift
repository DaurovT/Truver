import SwiftUI

@main
struct TruverSpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Environment(SpikeModel.self) private var model

    var body: some View {
        TabView {
            TunerScreen()
                .tabItem { Label("Тюнер", systemImage: "tuningfork") }
            MetronomeScreen()
                .tabItem { Label("Метроном", systemImage: "metronome") }
            DiagnosticsScreen()
                .tabItem { Label("Диагностика", systemImage: "waveform.path.ecg") }
        }
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }  // 6: the screen stays on while working
        #endif
        .task {
            if SpikeModel.autotestRequested { await model.runAutotest() }
        }
    }
}
