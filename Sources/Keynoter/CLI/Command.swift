import Foundation

/// Every slash command the REPL understands.
///
/// Slash commands drive the *application*. Natural-language input drives the
/// *presentation content* and is represented separately (see `CommandParser.Input`).
enum Command: Equatable, Sendable {
    case help
    case create(name: String)
    case edit(path: String)
    case status
    case open
    case save
    case saveAs(name: String)
    /// `path` is `nil` when the user gave only a format, meaning "next to the
    /// document, same base name".
    case export(format: ExportFormat, path: String?)
    case undo
    case redo
    case script
    case doctor
    case close
    case exit
}

/// One row of the command catalog: the single source of truth for what the
/// parser accepts and what `/help` prints.
struct CommandSpec: Sendable {
    /// Keyword without the leading slash.
    let keyword: String
    /// Placeholder shown in help, e.g. `<name>`. `nil` means the command takes no argument.
    let argument: String?
    let summary: String

    var usage: String {
        if let argument {
            return "/\(keyword) \(argument)"
        }
        return "/\(keyword)"
    }

    var requiresArgument: Bool { argument != nil }
}

extension Command {

    /// Declaration order is the order `/help` prints.
    static let catalog: [CommandSpec] = [
        CommandSpec(keyword: "help", argument: nil, summary: "List commands"),
        CommandSpec(keyword: "create", argument: "<name>", summary: "Create a new .key document and make it active"),
        CommandSpec(keyword: "edit", argument: "<path>", summary: "Open an existing .key document"),
        CommandSpec(keyword: "status", argument: nil, summary: "Show session state"),
        CommandSpec(keyword: "open", argument: nil, summary: "Bring the active document to the foreground"),
        CommandSpec(keyword: "save", argument: nil, summary: "Save the active document"),
        CommandSpec(keyword: "save-as", argument: "<name>", summary: "Write a copy and continue editing it"),
        CommandSpec(
            keyword: "export",
            argument: "<\(ExportFormat.keywordList)> [<path>]",
            summary: "Write the deck out as PDF or PowerPoint"
        ),
        CommandSpec(keyword: "undo", argument: nil, summary: "Revert the last Keynoter-driven action"),
        CommandSpec(keyword: "redo", argument: nil, summary: "Reapply the last undone action"),
        CommandSpec(keyword: "script", argument: nil, summary: "Print the AppleScript from the last operation"),
        CommandSpec(keyword: "doctor", argument: nil, summary: "Check the runtime environment"),
        CommandSpec(keyword: "close", argument: nil, summary: "Close the session, keep the REPL running"),
        CommandSpec(keyword: "exit", argument: nil, summary: "Quit Keynoter")
    ]

    static func spec(for keyword: String) -> CommandSpec? {
        catalog.first { $0.keyword == keyword }
    }

    /// Builds the command for a known keyword.
    ///
    /// Argument *presence* is already settled by the parser; what is left here
    /// is argument *shape*, which only `/export` has any of. Returning a
    /// `Result` rather than an optional is what lets "/export docx" say so
    /// instead of being reported as an unknown command.
    static func make(
        keyword: String,
        argument: String?
    ) -> Result<Command, CommandParser.ParseError> {
        switch keyword {
        case "help": .success(.help)
        case "create": requiring(argument, keyword) { .create(name: $0) }
        case "edit": requiring(argument, keyword) { .edit(path: $0) }
        case "status": .success(.status)
        case "open": .success(.open)
        case "save": .success(.save)
        case "save-as": requiring(argument, keyword) { .saveAs(name: $0) }
        case "export": makeExport(argument: argument)
        case "undo": .success(.undo)
        case "redo": .success(.redo)
        case "script": .success(.script)
        case "doctor": .success(.doctor)
        case "close": .success(.close)
        case "exit": .success(.exit)
        default: .failure(.unknownCommand(keyword: keyword))
        }
    }

    /// `/export <format> [<path>]` — the format is required, the path optional.
    /// Both halves come out of one free-form argument, because a path may
    /// contain spaces and the parser therefore cannot tokenize it blindly.
    private static func makeExport(argument: String?) -> Result<Command, CommandParser.ParseError> {
        guard let argument else {
            return .failure(ParseError.missingArgument(usage: usage(for: "export")))
        }

        let (token, remainder) = CommandParser.splitFirstToken(argument)
        guard let format = ExportFormat.parse(token) else {
            return .failure(ParseError.invalidArgument(
                usage: usage(for: "export"),
                detail: "'\(token)' is not a format Keynote exports to."
            ))
        }
        return .success(Command.export(format: format, path: CommandParser.unquoted(remainder)))
    }

    /// Wraps a command whose argument the catalog marks required. The parser
    /// rejects a missing one first, so this only fires if the catalog and this
    /// switch ever disagree — and then it says which argument is missing rather
    /// than claiming the command doesn't exist.
    private static func requiring(
        _ argument: String?,
        _ keyword: String,
        _ build: (String) -> Command
    ) -> Result<Command, CommandParser.ParseError> {
        guard let argument else {
            return .failure(ParseError.missingArgument(usage: usage(for: keyword)))
        }
        return .success(build(argument))
    }

    private static func usage(for keyword: String) -> String {
        spec(for: keyword)?.usage ?? "/\(keyword)"
    }

    /// Shorthand for the error type `make` reports through. The parser owns
    /// these cases because it owns the messages the REPL prints.
    private typealias ParseError = CommandParser.ParseError
}
