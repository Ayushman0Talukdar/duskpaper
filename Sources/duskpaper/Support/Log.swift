import Foundation
import os

/// Lightweight leveled logger writing to stderr and, when a debug flag is set,
/// to a rotating file in the app's log directory.
enum Log {
    private static let subsystem = "app.duskpaper.livewallpaper"
    private static let osLog = Logger(subsystem: subsystem, category: "duskpaper")

    static var debugEnabled = ProcessInfo.processInfo.environment["DUSKPAPER_DEBUG"] == "1"

    static func info(_ message: String) {
        osLog.info("\(message, privacy: .public)")
        emit("INFO", message)
    }

    static func warn(_ message: String) {
        osLog.warning("\(message, privacy: .public)")
        emit("WARN", message)
    }

    static func error(_ message: String) {
        osLog.error("\(message, privacy: .public)")
        emit("ERROR", message)
    }

    static func debug(_ message: String) {
        osLog.debug("\(message, privacy: .public)")
        guard debugEnabled else { return }
        emit("DEBUG", message)
    }

    private static func emit(_ level: String, _ message: String) {
        let line = "[\(level)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard debugEnabled else { return }
        appendToFile(line)
    }

    private static func appendToFile(_ line: String) {
        let url = Paths.logFile
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
    }
}
