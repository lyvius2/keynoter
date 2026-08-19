import Foundation

/// The read-eval-print loop: reads a line, routes it, prints the result, repeats.
@MainActor
final class REPL {

    private let session: Session
    private let controller: KeynoteController
    private let reader = LineReader()

    init(session: Session, controller: KeynoteController = KeynoteController()) {
        self.session = session
        self.controller = controller
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

        case .create(let name):
            await handleCreate(name)
        case .edit(let path):
            await handleEdit(path)
        case .open:
            await handleOpen()
        case .save:
            await handleSave()
        case .saveAs(let name):
            await handleSaveAs(name)
        case .close:
            await handleClose()

        // Phase 3 — domain model & renderer
        case .undo:
            notImplemented("/undo", phase: 3)
        case .redo:
            notImplemented("/redo", phase: 3)
        case .script:
            notImplemented("/script", phase: 3)

        case .status:
            await printStatus()
        case .doctor:
            printDoctor()
        }
    }

    private func handleNaturalLanguage(_ prompt: String) async {
        // Phase 4 wires this to PresentationPlanner.
        Console.warning("Natural-language planning is not wired up yet (Phase 4).")
        Console.info("Received prompt: \(prompt)")
    }

    // MARK: - Keynote commands

    private func handleCreate(_ name: String) async {
        if session.hasDocument {
            Console.warning("A document is already open. Use /close first.")
            return
        }
        let url = PathResolver.resolveKeynotePath(name)
        if FileManager.default.fileExists(atPath: url.path) {
            Console.failure("File already exists: \(url.path). Use /edit to open it.")
            return
        }
        do {
            try await controller.createDocument(at: url)
            session.attach(documentPath: url, mode: .create)
            Console.success("Created \(url.lastPathComponent)")
            await refreshSlides()
        } catch {
            reportError(error)
        }
    }

    private func handleEdit(_ path: String) async {
        if session.hasDocument {
            Console.warning("A document is already open. Use /close first.")
            return
        }
        let url = PathResolver.resolveKeynotePath(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Console.failure("File not found: \(url.path)")
            return
        }
        do {
            try await controller.openDocument(at: url)
            session.attach(documentPath: url, mode: .edit)
            Console.success("Opened \(url.lastPathComponent)")
            await refreshSlides()
        } catch {
            reportError(error)
        }
    }

    private func handleOpen() async {
        guard session.hasDocument else {
            Console.warning("No active document. Use /create <name> or /edit <path>.")
            return
        }
        do {
            try await controller.activate()
        } catch {
            reportError(error)
        }
    }

    private func handleSave() async {
        guard session.hasDocument else {
            Console.warning("No active document.")
            return
        }
        do {
            try await controller.saveDocument()
            session.markModified(false)
            Console.success("Saved \(session.documentName ?? "")")
        } catch {
            reportError(error)
        }
    }

    private func handleSaveAs(_ name: String) async {
        guard session.hasDocument else {
            Console.warning("No active document.")
            return
        }
        let url = PathResolver.resolveKeynotePath(name)
        if FileManager.default.fileExists(atPath: url.path) {
            Console.failure("File already exists: \(url.path).")
            return
        }
        do {
            try await controller.saveDocumentAs(at: url)
            session.renameDocument(to: url)
            Console.success("Saved as \(url.lastPathComponent)")
        } catch {
            reportError(error)
        }
    }

    private func handleClose() async {
        guard session.hasDocument else {
            Console.warning("No active document.")
            return
        }
        do {
            try await controller.closeDocument(save: true)
            let name = session.documentName ?? ""
            session.closeDocument()
            Console.success("Closed \(name)")
        } catch {
            reportError(error)
        }
    }

    private func refreshSlides() async {
        do {
            let slides = try await controller.readSlideMetadata()
            session.updateSlideMetadata(slides)
        } catch {
            // Non-fatal: leave cached metadata in place, tell the user why.
            Console.warning("Could not read slide metadata: \(errorMessage(error))")
        }
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

    private func printStatus() async {
        // Refresh from Keynote first so a slide count edited outside Keynoter
        // still shows up. Failure is silent — the cached value is still shown.
        if session.hasDocument {
            await refreshSlides()
        }
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

    // MARK: - Errors

    private func reportError(_ error: Error) {
        Console.failure(errorMessage(error))
    }

    private func errorMessage(_ error: Error) -> String {
        if let ae = error as? AppleScriptError { return ae.userMessage }
        return "\(error)"
    }
}
