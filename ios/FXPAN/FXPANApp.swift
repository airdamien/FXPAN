import SwiftUI

@main
struct FXPANApp: App {
    @State private var model = AppModel()

    init() {
        FontBook.register()
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.scene(phase) }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}
