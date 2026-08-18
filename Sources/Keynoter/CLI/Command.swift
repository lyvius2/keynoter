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
        CommandSpec(keyword: "save-as", argument: "<name>", summary: "Save a copy under a new name"),
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

    /// Builds the command for a known keyword. Argument presence is validated by
    /// the parser before this is called.
    static func make(keyword: String, argument: String?) -> Command? {
        switch keyword {
        case "help": .help
        case "create": argument.map { .create(name: $0) }
        case "edit": argument.map { .edit(path: $0) }
        case "status": .status
        case "open": .open
        case "save": .save
        case "save-as": argument.map { .saveAs(name: $0) }
        case "undo": .undo
        case "redo": .redo
        case "script": .script
        case "doctor": .doctor
        case "close": .close
        case "exit": .exit
        default: nil
        }
    }
}
