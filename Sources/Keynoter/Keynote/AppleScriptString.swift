import Foundation

/// Escaping for values interpolated into AppleScript string literals.
///
/// Deliberately the *only* escaper in the project: `KeynoteController` and
/// `AppleScriptRenderer` both route through here, because two subtly different
/// escapers is how a quote eventually slips through into a live script.
enum AppleScriptString {

    /// Escapes `s` for use inside a `"..."` literal, without the quotes.
    ///
    /// Backslash must be replaced first — otherwise the backslashes written by
    /// the later replacements get escaped a second time.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// `escape(_:)` plus the surrounding double quotes — a complete AppleScript
    /// string literal.
    static func literal(_ s: String) -> String {
        "\"\(escape(s))\""
    }
}
