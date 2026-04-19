import AppKit
import Foundation

@MainActor
enum AppKitDialogs {
    static func promptText(
        title: String,
        message: String,
        defaultValue: String = ""
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let res = alert.runModal()
        guard res == .alertFirstButtonReturn else { return nil }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(
        title: String,
        message: String,
        okTitle: String = "OK",
        cancelTitle: String = "Cancel"
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
