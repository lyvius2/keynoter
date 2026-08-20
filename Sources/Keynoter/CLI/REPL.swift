import Foundation

/// The read-eval-print loop: reads a line, routes it, prints the result, repeats.
@MainActor
final class REPL {

    private let session: Session
    private let controller: KeynoteController
    private let runner: ActionRunner
    private let planner: PresentationPlanner
    private let reader = LineReader()

    init(
        session: Session,
        controller: KeynoteController = KeynoteController(),
        planner: PresentationPlanner = PresentationPlanner()
    ) {
        self.session = session
        self.controller = controller
        self.runner = ActionRunner(session: session, controller: controller)
        self.planner = planner
    }

    func run() async {
        Console.banner()
        announcePlanner()

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

    /// Says so up front when natural language will not work, rather than
    /// letting the user discover it on their first request. Silent when the
    /// model is available — a working setup should not have to be told.
    private func announcePlanner() {
        if case .unavailable(let reason) = FoundationModelClient.availability() {
            Console.warning(reason)
        }
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

        case .undo:
            await handleUndo()
        case .redo:
            await handleRedo()
        case .script:
            printScript()

        case .status:
            await printStatus()
        case .doctor:
            printDoctor()
        }
    }

    /// Natural language drives the presentation's *content*: plan the change,
    /// then apply it one action at a time.
    private func handleNaturalLanguage(_ request: String) async {
        guard activeDocument() != nil else { return }

        // The model addresses slides by number, so it must see the deck as it
        // is now — not as it was before the last command.
        await refreshSlides()

        let actions: [PresentationAction]
        Console.info("Planning...")
        do {
            actions = try await planner.plan(request: request, slides: session.slideMetadata)
        } catch {
            reportError(error)
            return
        }

        Console.info("Applying \(actions.count) change\(actions.count == 1 ? "" : "s")...")
        await apply(actions)
    }

    /// Applies a plan in order, stopping at the first failure.
    ///
    /// Stopping rather than skipping ahead is deliberate: later actions were
    /// planned against the slide numbers the earlier ones were supposed to
    /// produce, so continuing past a failure edits the wrong slides. Whatever
    /// did apply stays on the undo stack, so `/undo` walks it back.
    private func apply(_ actions: [PresentationAction]) async {
        for (step, action) in actions.enumerated() {
            do {
                try await runner.apply(action)
            } catch {
                Console.failure("Step \(step + 1) (\(action.summary)) failed: \(errorMessage(error))")
                if step > 0 {
                    Console.info("Applied \(step) of \(actions.count) change\(step == 1 ? "" : "s"); /undo reverts them one at a time.")
                }
                await refreshSlides()
                return
            }
            Console.line("  \(action.summary)")
            // Each action shifts the slide numbers the next one was planned
            // against, so the count has to be re-read between steps.
            await refreshSlides()
        }
        Console.success("Done.")
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
            let opened = try await controller.createDocument(at: url)
            session.attach(documentPath: url, ref: opened.ref, mode: .create)
            // After attach — attaching resets the script buffer along with the
            // rest of the previous document's state.
            session.recordAppleScript(opened.script)
            Console.success("Created \(url.lastPathComponent)")
            await refreshSlides()
            planner.client.prewarm()
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
            let opened = try await controller.openDocument(at: url)
            session.attach(documentPath: url, ref: opened.ref, mode: .edit)
            session.recordAppleScript(opened.script)
            Console.success("Opened \(url.lastPathComponent)")
            await refreshSlides()
            // A document is open, so a natural-language request is now possible:
            // start loading the model before the user asks for one.
            planner.client.prewarm()
        } catch {
            reportError(error)
        }
    }

    private func handleOpen() async {
        guard let document = activeDocument() else { return }
        do {
            session.recordAppleScript(try await controller.activate(document))
        } catch {
            reportError(error)
        }
    }

    private func handleSave() async {
        guard let document = activeDocument() else { return }
        do {
            session.recordAppleScript(try await controller.saveDocument(document))
            session.markModified(false)
            Console.success("Saved \(session.documentName ?? "")")
        } catch {
            reportError(error)
        }
    }

    private func handleSaveAs(_ name: String) async {
        guard let document = activeDocument() else { return }
        let url = PathResolver.resolveKeynotePath(name)
        if FileManager.default.fileExists(atPath: url.path) {
            Console.failure("File already exists: \(url.path).")
            return
        }
        do {
            let opened = try await controller.saveDocumentAs(document, at: url)
            let previous = session.documentName
            session.switchDocument(to: url, ref: opened.ref)
            session.recordAppleScript(opened.script)
            Console.success("Saved as \(url.lastPathComponent)")
            // Keynote cannot "save as" in place: editing continues in the copy
            // and the original keeps whatever was last written to it.
            if let previous {
                Console.info("Now editing \(url.lastPathComponent); \(previous) is closed.")
            }
        } catch {
            reportError(error)
        }
    }

    private func handleClose() async {
        guard let document = activeDocument() else { return }
        let name = session.documentName ?? ""
        do {
            try await controller.closeDocument(document, save: true)
            session.closeDocument()
            Console.success("Closed \(name)")
        } catch {
            // Detach regardless. The session is Keynoter's own state, so ending
            // it has to be possible even when Keynote will not cooperate — and
            // the common cause is that the user already closed the document in
            // Keynote, which leaves /save, /close and /create all refusing and
            // no way out but quitting.
            session.closeDocument()
            Console.warning("Ended the session for \(name), but Keynote reported: \(errorMessage(error))")
        }
    }

    // MARK: - History commands

    private func handleUndo() async {
        guard activeDocument() != nil else { return }
        guard session.history.canUndo else {
            Console.warning("Nothing to undo.")
            return
        }
        do {
            let action = try await runner.undo()
            Console.success("Undid: \(action.summary)")
            await refreshSlides()
        } catch {
            reportError(error)
        }
    }

    private func handleRedo() async {
        guard activeDocument() != nil else { return }
        guard session.history.canRedo else {
            Console.warning("Nothing to redo.")
            return
        }
        do {
            let action = try await runner.redo()
            Console.success("Redid: \(action.summary)")
            await refreshSlides()
        } catch {
            reportError(error)
        }
    }

    /// Prints the AppleScript from the last operation — rendered by Keynoter,
    /// never text a model produced.
    private func printScript() {
        guard let script = session.lastAppleScript else {
            Console.warning("No AppleScript yet — run a command that talks to Keynote first.")
            return
        }
        Console.heading("AppleScript")
        Console.line(script)
    }

    /// The active document, or `nil` after reporting that there isn't one.
    /// Every command that touches Keynote starts here, so the "no document"
    /// wording lives in exactly one place.
    private func activeDocument() -> DocumentRef? {
        guard let ref = session.documentRef else {
            Console.warning(ActionRunnerError.noDocument.userMessage)
            return nil
        }
        return ref
    }

    private func refreshSlides() async {
        guard let document = session.documentRef else { return }
        do {
            let slides = try await controller.readSlideMetadata(document)
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
        Console.line("  Undo:     \(session.history.undoDepth) (redo: \(session.history.redoDepth))")
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
        if let re = error as? ActionRunnerError { return re.userMessage }
        if let pe = error as? PlannerError { return pe.userMessage }
        if let ce = error as? PlanConversionError { return ce.userMessage }
        if let ve = error as? ValidationError { return ve.userMessage }
        return "\(error)"
    }
}
