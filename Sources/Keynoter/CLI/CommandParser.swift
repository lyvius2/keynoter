import Foundation

/// Turns a raw input line into either a slash command or a natural-language prompt.
///
/// This is a pure function of its input — no session state, no side effects — so
/// it stays trivially testable as the command surface grows.
enum CommandParser {

    enum Input: Equatable {
        /// Blank line; the REPL simply re-prompts.
        case empty
        case command(Command)
        /// Natural language destined for the planner.
        case prompt(String)
        case failure(ParseError)
    }

    enum ParseError: Equatable {
        case emptyCommand
        case unknownCommand(keyword: String)
        case missingArgument(usage: String)
        case unexpectedArgument(keyword: String)

        var message: String {
            switch self {
            case .emptyCommand:
                "Missing command name after '/'. Type /help for commands."
            case .unknownCommand(let keyword):
                "Unknown command '/\(keyword)'. Type /help for commands."
            case .missingArgument(let usage):
                "Missing argument. Usage: \(usage)"
            case .unexpectedArgument(let keyword):
                "'/\(keyword)' takes no arguments."
            }
        }
    }

    static func parse(_ rawLine: String) -> Input {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !line.isEmpty else { return .empty }
        guard line.hasPrefix("/") else { return .prompt(line) }

        let (keyword, remainder) = splitFirstToken(String(line.dropFirst()))

        guard !keyword.isEmpty else { return .failure(.emptyCommand) }
        guard let spec = Command.spec(for: keyword.lowercased()) else {
            return .failure(.unknownCommand(keyword: keyword))
        }

        // Arguments are free-form (names and paths may contain spaces), so the
        // whole remainder is one argument rather than a token list.
        let argument = unquoted(remainder)

        if spec.requiresArgument, argument == nil {
            return .failure(.missingArgument(usage: spec.usage))
        }
        if !spec.requiresArgument, argument != nil {
            return .failure(.unexpectedArgument(keyword: spec.keyword))
        }

        guard let command = Command.make(keyword: spec.keyword, argument: argument) else {
            return .failure(.unknownCommand(keyword: keyword))
        }
        return .command(command)
    }

    // MARK: - Helpers

    private static func splitFirstToken(_ text: String) -> (token: String, remainder: String) {
        guard let space = text.firstIndex(where: { $0.isWhitespace }) else {
            return (text, "")
        }
        let token = String(text[text.startIndex..<space])
        let remainder = String(text[space...]).trimmingCharacters(in: .whitespaces)
        return (token, remainder)
    }

    /// Strips one layer of matching surrounding quotes. Returns `nil` for a blank argument.
    private static func unquoted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        for quote in ["\"", "'"] where trimmed.hasPrefix(quote) && trimmed.hasSuffix(quote) && trimmed.count >= 2 {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner.isEmpty ? nil : inner
        }
        return trimmed
    }
}
