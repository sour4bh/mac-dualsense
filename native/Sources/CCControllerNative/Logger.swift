import Foundation

final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let logFile: URL
    private let queue = DispatchQueue(label: "cc-controller.logger", qos: .utility)
    private let dateFormatter: DateFormatter

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        logFile = logsDir.appendingPathComponent("cc-controller.log", isDirectory: false)
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

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

    private func log(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) \(level) CCControllerNative: \(message)\n"

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
