import Foundation

/// All terminal output flows through here so formatting stays consistent
/// as later phases add command results, AI progress, and error reporting.
enum Console {

    // MARK: - Styling

    /// Whether stdout is a terminal. ANSI styling and in-place progress are
    /// only emitted when it is, so piped or redirected output stays clean.
    static let isTerminal: Bool = isatty(STDOUT_FILENO) == 1

    private enum Style: String {
        case reset = "\u{001B}[0m"
        case bold = "\u{001B}[1m"
        case dim = "\u{001B}[2m"
        case green = "\u{001B}[32m"
        case red = "\u{001B}[31m"
        case yellow = "\u{001B}[33m"
        case cyan = "\u{001B}[36m"
    }

    private static func styled(_ text: String, _ style: Style) -> String {
        isTerminal ? style.rawValue + text + Style.reset.rawValue : text
    }

    // MARK: - Setup

    /// Line-buffers stdout so output stays correctly ordered against stderr when
    /// Keynoter's output is piped or redirected (stdout is block-buffered by default).
    static func configure() {
        setvbuf(stdout, nil, _IOLBF, 0)
    }

    // MARK: - Output

    static func write(_ text: String) {
        print(text, terminator: "")
        fflush(stdout)
    }

    static func line(_ text: String = "") {
        print(text)
    }

    static func success(_ text: String) {
        print("\(styled("✓", .green)) \(text)")
    }

    static func failure(_ text: String) {
        FileHandle.standardError.write(Data("\(styled("✗", .red)) \(text)\n".utf8))
    }

    static func warning(_ text: String) {
        print("\(styled("!", .yellow)) \(text)")
    }

    static func info(_ text: String) {
        print(styled(text, .dim))
    }

    static func heading(_ text: String) {
        print(styled(text, .bold))
    }

    // MARK: - Progress

    /// Rewrites the current line with `text`. Meant for work in flight, where
    /// only the newest line is worth reading.
    ///
    /// Silent when stdout is not a terminal: a redirected transcript would
    /// otherwise collect one line per snapshot, most of them half-written, and
    /// carriage returns cannot take them back.
    static func progress(_ text: String) {
        guard isTerminal else { return }
        write("\r\u{001B}[2K" + styled(text, .dim))
    }

    /// Erases the progress line so ordinary output starts from a clean one.
    /// Safe to call when nothing was written.
    static func endProgress() {
        guard isTerminal else { return }
        write("\r\u{001B}[2K")
    }

    // MARK: - Fixed screens

    static func banner() {
        print(styled("Keynoter", .bold))
        print(styled("On-device AI presentation assistant for Apple Keynote", .dim))
        print(styled("Type /help for commands, /exit to quit.", .dim))
        print("")
    }

    static var prompt: String {
        styled("> ", .cyan)
    }
}
