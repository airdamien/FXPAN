import SwiftUI

@main
struct FXPANApp: App {
    @State private var model = AppModel()

    init() {
        FontBook.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task { await model.start() }
        }
    }
}
