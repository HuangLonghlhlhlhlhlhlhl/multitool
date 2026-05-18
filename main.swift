import Cocoa

// Entry point for the macOS status bar application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

withExtendedLifetime(delegate) {
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
