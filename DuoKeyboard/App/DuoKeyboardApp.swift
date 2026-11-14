import SwiftUI

@main
struct DuoKeyboardApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SettingsView()
            }
        }
    }
}

/// The App Group store shared with the keyboard extension.
let sharedDefaults: UserDefaults = {
    let d = UserDefaults(suiteName: KeyboardSettings.appGroupID) ?? .standard
    d.register(defaults: KeyboardSettings.defaultValues)
    return d
}()
