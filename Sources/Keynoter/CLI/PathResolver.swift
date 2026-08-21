import Foundation

/// Turns raw file arguments typed at the REPL — `demo`, `~/Desktop/deck`,
/// `./copy.key`, `/tmp/x` — into absolute URLs with a known extension.
///
/// Pure: expands the leading tilde, appends the extension when the input
/// doesn't already end that way (case-insensitive), and resolves relative paths
/// against the caller-supplied working directory. `standardizedFileURL`
/// collapses `.` and `..` lexically.
enum PathResolver {

    /// `.key` documents — `/create`, `/edit`, `/save-as`.
    static func resolveKeynotePath(
        _ input: String,
        relativeTo cwd: URL = defaultCWD
    ) -> URL {
        resolvePath(input, extension: "key", relativeTo: cwd)
    }

    /// The general form, used by `/export` for `.pdf` / `.pptx`.
    ///
    /// The extension is only ever *appended*, never swapped: `/export pdf
    /// deck.key` produces `deck.key.pdf`, so a mistyped export can't be aimed
    /// at the presentation it came from.
    static func resolvePath(
        _ input: String,
        extension ext: String,
        relativeTo cwd: URL = defaultCWD
    ) -> URL {
        let expanded = (input as NSString).expandingTildeInPath
        let suffix = "." + ext
        let withExt = expanded.lowercased().hasSuffix(suffix.lowercased()) ? expanded : expanded + suffix

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
