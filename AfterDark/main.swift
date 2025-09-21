import Cocoa

@MainActor
func startApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    NSApp.run()
}

Task { await startApp() }
RunLoop.main.run()
