import Foundation

/// Reads one line of input at a time.
///
/// Wrapped in its own type so the REPL never touches stdin directly — later
/// phases can swap in line editing or history without touching the loop.
struct LineReader {

    /// Piped or redirected input suppresses the prompt so transcripts stay clean.
    let isInteractive: Bool = isatty(STDIN_FILENO) == 1

    /// Returns `nil` at end of input (Ctrl-D, or the end of a piped script).
    func readLine(prompt: String) -> String? {
        if isInteractive {
            Console.write(prompt)
        }
        return Swift.readLine(strippingNewline: true)
    }
}
