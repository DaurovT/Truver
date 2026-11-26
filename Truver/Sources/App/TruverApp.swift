import SwiftData
import SwiftUI

@main
struct TruverApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        UITestSandbox.prepare()
        let inMemory = UITestSandbox.isActive     // UI tests never touch the real instruments and journal
        #else
        let inMemory = false
        #endif
        let schema = Schema([StoredInstrument.self, PracticeEntry.self])
        // Local only for now; the models are CloudKit-compatible so iCloud can be switched on later (PRD 4).
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // Update notices of «Спасибо · обновления» (Features/Thanks/UpdateViews.swift).
                .overlay { UpdateNoticeHost().environment(model) }
                // Coach marks of «Знакомство и обучение» (Features/Tour/CoachMarks.swift).
                .overlay { CoachHost().environment(model) }
                .preferredColorScheme(.dark)
                #if os(iOS)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true   // 6: the screen stays on while working
                    #if DEBUG
                    // Debug hook for screenshots: `-landscape` turns the simulator sideways.
                    if ProcessInfo.processInfo.arguments.contains("-landscape"),
                       let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    } else if ProcessInfo.processInfo.arguments.contains("-portrait"),
                              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        // `-portrait`: back upright after a landscape screenshot (the simulator keeps its rotation).
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                    }
                    #endif
                }
                #endif
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.practice.flush() }
                }
        }
        .modelContainer(container)
    }
}
