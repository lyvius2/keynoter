import Foundation
import Testing
@testable import Keynoter

@Suite("AppleScriptExecutor")
struct AppleScriptExecutorTests {

    private let executor = AppleScriptExecutor()

    // MARK: - Happy path

    @Test("Returns a string result from a trivial script")
    func returnsString() async throws {
        let result = try await executor.run(#"return "hello""#)
        #expect(result == "hello")
    }

    @Test("Returns an empty string when the script's return value is empty")
    func returnsEmpty() async throws {
        let result = try await executor.run(#"return """#)
        #expect(result == "")
    }

    @Test("Round-trips a multi-line string containing embedded quotes")
    func multilineRoundTrip() async throws {
        let script = """
        set quote to "she said \\"hi\\""
        return quote
        """
        let result = try await executor.run(script)
        #expect(result == "she said \"hi\"")
    }

    @Test("Round-trips unicode without corruption")
    func unicode() async throws {
        let result = try await executor.run(#"return "안녕 世界 🇰🇷""#)
        #expect(result == "안녕 世界 🇰🇷")
    }

    // MARK: - Error path

    @Test("A script that raises an error throws executionFailed with the AppleScript error number")
    func scriptError() async throws {
        do {
            _ = try await executor.run(#"error "boom" number -128"#)
            Issue.record("expected AppleScriptError.executionFailed")
        } catch let AppleScriptError.executionFailed(exitCode, errorCode, _, stderr) {
            #expect(exitCode != 0)
            #expect(errorCode == -128)
            #expect(stderr.contains("boom"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("A syntax error surfaces as executionFailed")
    func syntaxError() async throws {
        do {
            _ = try await executor.run("this is not valid applescript {")
            Issue.record("expected AppleScriptError.executionFailed")
        } catch AppleScriptError.executionFailed {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

@Suite("AppleScriptExecutor helpers")
struct AppleScriptExecutorHelperTests {

    // MARK: - parseErrorCode

    @Test("Extracts a trailing (-N) code")
    func parseTrailingCode() {
        let stderr = "80:83: execution error: boom (-128)"
        #expect(AppleScriptExecutor.parseErrorCode(from: stderr) == -128)
    }

    @Test("Reads only the last non-empty line")
    func parseLastLine() {
        let stderr = """
        header line
        80:83: execution error: Not authorized to send Apple events to Keynote. (-1743)
        """
        #expect(AppleScriptExecutor.parseErrorCode(from: stderr) == -1743)
    }

    @Test("Skips trailing blank lines")
    func parseIgnoresTrailingBlank() {
        let stderr = "0:0: execution error: nope (-1728)\n\n"
        #expect(AppleScriptExecutor.parseErrorCode(from: stderr) == -1728)
    }

    @Test("Returns nil when no trailing code is present", arguments: [
        "just a message",
        "",
        "some (nonsense) trailing text"
    ])
    func parseNoCode(_ stderr: String) {
        #expect(AppleScriptExecutor.parseErrorCode(from: stderr) == nil)
    }

    // MARK: - stripTrailingNewline

    @Test("Strips a single trailing LF")
    func stripLF() {
        #expect(AppleScriptExecutor.stripTrailingNewline("hello\n") == "hello")
    }

    @Test("Strips a single trailing CRLF")
    func stripCRLF() {
        #expect(AppleScriptExecutor.stripTrailingNewline("hello\r\n") == "hello")
    }

    @Test("Leaves a bare string alone")
    func stripNothing() {
        #expect(AppleScriptExecutor.stripTrailingNewline("hello") == "hello")
    }

    @Test("Strips at most one trailing newline")
    func stripOnlyOne() {
        #expect(AppleScriptExecutor.stripTrailingNewline("hello\n\n") == "hello\n")
    }
}
