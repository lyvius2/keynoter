import Foundation

/// Turns raw file arguments typed at the REPL — `demo`, `~/Desktop/deck`,
/// `./copy.key`, `/tmp/x` — into absolute `.key` URLs.
///
/// Pure: expands the leading tilde, appends `.key` when the input doesn't
/// already end that way (case-insensitive), and resolves relative paths
/// against the caller-supplied working directory. `standardizedFileURL`
/// collapses `.` and `..` lexically.
enum PathResolver {

    static func resolveKeynotePath(
        _ input: String,
        relativeTo cwd: URL = defaultCWD
    ) -> URL {
        let expanded = (input as NSString).expandingTildeInPath
        let withExt = expanded.lowercased().hasSuffix(".key") ? expanded : expanded + ".key"

        let url: URL
        if withExt.hasPrefix("/") {
            url = URL(fileURLWithPath: withExt)
        } else {
            url = cwd.appendingPathComponent(withExt)
        }
        return url.standardizedFileURL
    }

    static var defaultCWD: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
