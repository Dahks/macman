import Cocoa
import ApplicationServices

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// We must be an accessory app (no dock icon, no menu bar)
app.setActivationPolicy(.accessory)
app.run()
