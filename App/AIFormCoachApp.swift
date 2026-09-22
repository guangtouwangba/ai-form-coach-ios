import SwiftUI
import SwiftData

@main
struct AIFormCoachApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: StoredWorkoutSession.self)
    }
}
