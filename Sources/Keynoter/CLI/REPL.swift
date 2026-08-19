import Foundation

/// The read-eval-print loop: reads a line, routes it, prints the result, repeats.
///
/// Command *behavior* lands in later phases; this loop owns only the routing.
@MainActor
final class REPL {

    private let session: Session
    private let reader = LineReader()

    init(session: Session) {
        self.session = session
    }

    func run() async {
        Console.banner()

        while !session.shouldExit {
            guard let line = reader.readLine(prompt: Console.prompt) else {
                // EOF (Ctrl-D): finish the prompt line, then leave.
                if reader.isInteractive { Console.line() }
                break
            }
            await handle(line)
        }

        Console.info("Goodbye.")
    }

    // MARK: - Routing

    private func handle(_ line: String) async {
        switch CommandParser.parse(line) {
        case .empty:
            break
        case .command(let command):
            await execute(command)
        case .prompt(let prompt):
            await handleNaturalLanguage(prompt)
        case .failure(let error):
            Console.failure(error.message)
        }
    }

    private func execute(_ command: Command) async {
        switch command {
        case .help:
            printHelp()
        case .exit:
            session.shouldExit = true

        // Phase 2 — Keynote integration
        case .create:
            notImplemented("/create", phase: 2)
        case .edit:
            notImplemented("/edit", phase: 2)
        case .open:
            notImplemented("/open", phase: 2)
        case .save:
            notImplemented("/save", phase: 2)
        case .saveAs:
            notImplemented("/save-as", phase: 2)
        case .close:
            notImplemented("/close", phase: 2)

        // Phase 3 — domain model & renderer
        case .undo:
            notImplemented("/undo", phase: 3)
        case .redo:
            notImplemented("/redo", phase: 3)
        case .script:
            notImplemented("/script", phase: 3)

        case .status:
            printStatus()
        case .doctor:
            printDoctor()
        }
    }

    private func handleNaturalLanguage(_ prompt: String) async {
        // Phase 4 wires this to PresentationPlanner.
        Console.warning("Natural-language planning is not wired up yet (Phase 4).")
        Console.info("Received prompt: \(prompt)")
    }

    // MARK: - Output

    private func printHelp() {
        Console.heading("Commands")
        let width = Command.catalog.map(\.usage.count).max() ?? 0
        for spec in Command.catalog {
            let usage = spec.usage.padding(toLength: width, withPad: " ", startingAt: 0)
            Console.line("  \(usage)  \(spec.summary)")
        }
        Console.line()
        Console.info("Anything that does not start with '/' is sent to the presentation planner.")
    }

    private func notImplemented(_ command: String, phase: Int) {
        Console.warning("\(command) is not implemented yet (Phase \(phase)).")
    }

    private func printStatus() {
        Console.heading("Status")
        guard let name = session.documentName else {
            Console.info("  No active document. Use /create <name> or /edit <path>.")
            return
        }
        Console.line("  Document: \(name)")
        if let path = session.documentPath?.path {
            Console.line("  Path:     \(path)")
        }
        Console.line("  Mode:     \(session.mode.rawValue)")
        Console.line("  Slides:   \(session.slideCount)")
        Console.line("  Modified: \(session.isModified ? "yes" : "no")")
    }

    private func printDoctor() {
        let report = Doctor.report()
        Console.heading("Doctor")
        for check in report.checks {
            let text = "\(check.name): \(check.detail)"
            switch check.severity {
            case .ok: Console.success(text)
            case .warn: Console.warning(text)
            case .fail: Console.failure(text)
            }
        }
        Console.line()
        switch report.overall {
        case .ok:
            Console.info("Environment ready.")
        case .warn:
            Console.info("Environment usable — review the warnings above.")
        case .fail:
            Console.info("Environment has blocking issues — address them before continuing.")
        }
    }
}
