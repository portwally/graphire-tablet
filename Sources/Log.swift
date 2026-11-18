import Foundation

/// Tiny file logger: ~/Library/Logs/GraphireTablet.log (truncated when it passes 1 MB).
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/GraphireTablet.log")

    private static let formatter = ISO8601DateFormatter()

    private static let handle: FileHandle? = {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            try? fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) { handle?.write(data) }
    }

    static func hex(_ r: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: r)) }
}
