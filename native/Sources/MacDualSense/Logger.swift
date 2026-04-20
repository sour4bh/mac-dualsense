import AppKit
import Foundation
import OSLog

final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let logFile: URL
    private let queue = DispatchQueue(label: "mac-dualsense.logger", qos: .utility)
    private let dateFormatter: DateFormatter
    private let systemLog: OSLog

    var logFileURL: URL { logFile }

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        logFile = logsDir.appendingPathComponent("mac-dualsense.log", isDirectory: false)
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        systemLog = OSLog(
            subsystem: Bundle.main.bundleIdentifier ?? "mac-dualsense",
            category: "App"
        )

        // Ensure logs directory exists
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    func info(_ message: String) {
        log("INFO", message)
    }

    func debug(_ message: String) {
        log("DEBUG", message)
    }

    func warning(_ message: String) {
        log("WARNING", message)
    }

    func error(_ message: String) {
        log("ERROR", message)
    }

    @MainActor
    func revealLogFileInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logFile])
    }

    private func log(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) \(level) MacDualSense: \(message)\n"

        switch level {
        case "DEBUG":
            os_log("%{public}@", log: systemLog, type: .debug, message)
        case "WARNING":
            os_log("%{public}@", log: systemLog, type: .default, message)
        case "ERROR":
            os_log("%{public}@", log: systemLog, type: .error, message)
        default:
            os_log("%{public}@", log: systemLog, type: .info, message)
        }

        queue.async { [logFile] in
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }
}
