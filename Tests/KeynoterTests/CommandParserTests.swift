import Testing
@testable import Keynoter

@Suite("CommandParser")
struct CommandParserTests {

    // MARK: - Blank input

    @Test("Blank lines produce no work", arguments: ["", "   ", "\t", "\n"])
    func blankInput(line: String) {
        #expect(CommandParser.parse(line) == .empty)
    }

    // MARK: - Natural language

    @Test("Text without a leading slash is a planner prompt")
    func naturalLanguage() {
        #expect(CommandParser.parse("Make a 5-slide deck about Kafka.")
                == .prompt("Make a 5-slide deck about Kafka."))
    }

    @Test("Prompts are trimmed")
    func promptIsTrimmed() {
        #expect(CommandParser.parse("   make a deck   ") == .prompt("make a deck"))
    }

    // MARK: - Commands

    @Test("Argument-free commands parse", arguments: [
        ("/help", Command.help),
        ("/status", .status),
        ("/open", .open),
        ("/save", .save),
        ("/undo", .undo),
        ("/redo", .redo),
        ("/script", .script),
        ("/doctor", .doctor),
        ("/close", .close),
        ("/exit", .exit)
    ])
    func argumentFreeCommands(line: String, expected: Command) {
        #expect(CommandParser.parse(line) == .command(expected))
    }

    @Test("Commands carry their argument", arguments: [
        ("/create demo", Command.create(name: "demo")),
        ("/edit ~/Desktop/deck.key", .edit(path: "~/Desktop/deck.key")),
        ("/save-as copy", .saveAs(name: "copy"))
    ])
    func commandsWithArguments(line: String, expected: Command) {
        #expect(CommandParser.parse(line) == .command(expected))
    }

    // MARK: - /export

    @Test("A format alone exports beside the document", arguments: [
        ("/export pdf", Command.export(format: .pdf, path: nil)),
        ("/export pptx", .export(format: .pptx, path: nil))
    ])
    func exportWithoutPath(line: String, expected: Command) {
        #expect(CommandParser.parse(line) == .command(expected))
    }

    @Test("A path after the format is carried through")
    func exportWithPath() {
        #expect(CommandParser.parse("/export pdf ~/Desktop/deck.pdf")
                == .command(.export(format: .pdf, path: "~/Desktop/deck.pdf")))
    }

    @Test("An export path may contain spaces, quoted or not", arguments: [
        "/export pdf my deck.pdf",
        "/export pdf \"my deck.pdf\"",
        "/export pdf 'my deck.pdf'"
    ])
    func exportPathWithSpaces(line: String) {
        #expect(CommandParser.parse(line) == .command(.export(format: .pdf, path: "my deck.pdf")))
    }

    @Test("Format keywords are case-insensitive and accept the usual aliases", arguments: [
        ("/export PDF", ExportFormat.pdf),
        ("/export Pptx", .pptx),
        ("/export powerpoint", .pptx),
        ("/export ppt", .pptx)
    ])
    func exportFormatAliases(line: String, expected: ExportFormat) {
        #expect(CommandParser.parse(line) == .command(.export(format: expected, path: nil)))
    }

    @Test("An unknown format is rejected as a bad argument, not a bad command")
    func exportUnknownFormat() {
        let result = CommandParser.parse("/export docx")
        guard case .failure(.invalidArgument(let usage, let detail)) = result else {
            Issue.record("expected .invalidArgument, got \(result)")
            return
        }
        #expect(usage == "/export <pdf|pptx> [<path>]")
        #expect(detail.contains("docx"))
    }

    @Test("/export with no format reports its usage")
    func exportMissingFormat() {
        #expect(CommandParser.parse("/export")
                == .failure(.missingArgument(usage: "/export <pdf|pptx> [<path>]")))
    }

    @Test("Keywords are case-insensitive")
    func caseInsensitiveKeywords() {
        #expect(CommandParser.parse("/HELP") == .command(.help))
        #expect(CommandParser.parse("/Save-As copy") == .command(.saveAs(name: "copy")))
    }

    // MARK: - Argument handling

    @Test("Arguments may contain spaces")
    func argumentWithSpaces() {
        #expect(CommandParser.parse("/edit ~/Desktop/my deck.key")
                == .command(.edit(path: "~/Desktop/my deck.key")))
    }

    @Test("Surrounding quotes are stripped", arguments: [
        "/create \"My Big Deck\"",
        "/create 'My Big Deck'"
    ])
    func quotedArgument(line: String) {
        #expect(CommandParser.parse(line) == .command(.create(name: "My Big Deck")))
    }

    @Test("Surrounding whitespace around an argument is dropped")
    func argumentIsTrimmed() {
        #expect(CommandParser.parse("/save-as    Copy 2   ")
                == .command(.saveAs(name: "Copy 2")))
    }

    // MARK: - Failures

    @Test("A command needing an argument reports its usage", arguments: [
        "/create", "/create   ", "/create \"\""
    ])
    func missingArgument(line: String) {
        #expect(CommandParser.parse(line) == .failure(.missingArgument(usage: "/create <name>")))
    }

    @Test("Argument-free commands reject arguments")
    func unexpectedArgument() {
        #expect(CommandParser.parse("/status now")
                == .failure(.unexpectedArgument(keyword: "status")))
    }

    @Test("Unknown keywords are rejected")
    func unknownCommand() {
        #expect(CommandParser.parse("/nope") == .failure(.unknownCommand(keyword: "nope")))
    }

    @Test("A bare slash is rejected")
    func bareSlash() {
        #expect(CommandParser.parse("/") == .failure(.emptyCommand))
    }

    @Test("Every failure explains itself and points at /help where useful")
    func failureMessages() {
        #expect(CommandParser.ParseError.unknownCommand(keyword: "nope").message
                .contains("/help"))
        #expect(CommandParser.ParseError.missingArgument(usage: "/create <name>").message
                .contains("/create <name>"))

        let invalid = CommandParser.ParseError
            .invalidArgument(usage: "/export <pdf|pptx> [<path>]", detail: "'docx' is not a format.")
            .message
        #expect(invalid.contains("'docx' is not a format."))
        #expect(invalid.contains("/export <pdf|pptx> [<path>]"))
    }
}

@Suite("Command catalog")
struct CommandCatalogTests {

    @Test("Keywords are unique")
    func uniqueKeywords() {
        let keywords = Command.catalog.map(\.keyword)
        #expect(Set(keywords).count == keywords.count)
    }

    @Test("Keywords are lowercase so case-insensitive lookup always matches")
    func lowercaseKeywords() {
        for spec in Command.catalog {
            #expect(spec.keyword == spec.keyword.lowercased())
        }
    }

    /// An argument that the command in question actually accepts. Most take a
    /// free-form name or path; `/export` takes a keyword from a fixed set, so
    /// "sample" would (rightly) be rejected and prove nothing.
    private static let sampleArguments = [
        "create": "sample",
        "edit": "sample",
        "save-as": "sample",
        "export": "pdf"
    ]

    /// Guards the one seam where the catalog and `Command.make` can drift apart:
    /// a new catalog row without a matching case would parse to nothing.
    @Test("Every catalog entry parses into a command", arguments: Command.catalog)
    func everyEntryIsReachable(spec: CommandSpec) {
        guard let line = Self.sampleLine(for: spec) else {
            Issue.record("'/\(spec.keyword)' takes an argument but the test has no sample for it")
            return
        }
        let result = CommandParser.parse(line)
        guard case .command = result else {
            Issue.record("'\(line)' did not parse into a command; got \(result)")
            return
        }
    }

    private static func sampleLine(for spec: CommandSpec) -> String? {
        guard spec.requiresArgument else { return "/\(spec.keyword)" }
        return sampleArguments[spec.keyword].map { "/\(spec.keyword) \($0)" }
    }

    @Test("Usage strings read the way help prints them")
    func usageStrings() {
        #expect(Command.spec(for: "help")?.usage == "/help")
        #expect(Command.spec(for: "create")?.usage == "/create <name>")
    }
}
