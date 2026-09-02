import SwiftUI
import SwiftData

@main
struct AIFormCoachApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .modelContainer(for: StoredWorkoutSession.self)
    }
}
