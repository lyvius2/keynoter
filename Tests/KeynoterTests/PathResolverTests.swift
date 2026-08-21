import Foundation
import Testing
@testable import Keynoter

@Suite("PathResolver")
struct PathResolverTests {

    private let cwd = URL(fileURLWithPath: "/tmp", isDirectory: true)

    @Test("A bare name resolves against the working directory and gets .key")
    func bareName() {
        let url = PathResolver.resolveKeynotePath("demo", relativeTo: cwd)
        #expect(url.path == "/tmp/demo.key")
    }

    @Test("An input that already ends in .key keeps the extension")
    func alreadyHasExtension() {
        let url = PathResolver.resolveKeynotePath("demo.key", relativeTo: cwd)
        #expect(url.path == "/tmp/demo.key")
    }

    @Test("The .key suffix check is case-insensitive")
    func extensionCaseInsensitive() {
        let url = PathResolver.resolveKeynotePath("Demo.KEY", relativeTo: cwd)
        #expect(url.path == "/tmp/Demo.KEY")
    }

    @Test("An absolute path is honored")
    func absolutePath() {
        let url = PathResolver.resolveKeynotePath("/var/tmp/deck", relativeTo: cwd)
        #expect(url.path == "/var/tmp/deck.key")
    }

    @Test("A dot-relative path is collapsed")
    func dotRelative() {
        let url = PathResolver.resolveKeynotePath("./deck", relativeTo: cwd)
        #expect(url.path == "/tmp/deck.key")
    }

    @Test("A double-dot path escapes the working directory")
    func dotDot() {
        let nested = URL(fileURLWithPath: "/tmp/nested", isDirectory: true)
        let url = PathResolver.resolveKeynotePath("../deck", relativeTo: nested)
        #expect(url.path == "/tmp/deck.key")
    }

    @Test("A path with spaces flows through untouched")
    func spaces() {
        let url = PathResolver.resolveKeynotePath("My Big Deck", relativeTo: cwd)
        #expect(url.path == "/tmp/My Big Deck.key")
    }

    @Test("A leading tilde expands to the current user's home")
    func expandsTilde() {
        let url = PathResolver.resolveKeynotePath("~/deck", relativeTo: cwd)
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("deck.key")
            .standardizedFileURL
        #expect(url.path == expected.path)
    }

    // MARK: - Export extensions

    @Test("Export extensions follow the same rules", arguments: [
        ("deck", "pdf", "/tmp/deck.pdf"),
        ("deck.pdf", "pdf", "/tmp/deck.pdf"),
        ("Deck.PDF", "pdf", "/tmp/Deck.PDF"),
        ("deck", "pptx", "/tmp/deck.pptx")
    ])
    func exportExtensions(input: String, ext: String, expected: String) {
        #expect(PathResolver.resolvePath(input, extension: ext, relativeTo: cwd).path == expected)
    }

    /// The extension is appended, never swapped — so an export aimed at a `.key`
    /// path lands beside the presentation rather than on top of it.
    @Test("A .key path is never turned into the export target itself")
    func neverOverwritesTheDeck() {
        let url = PathResolver.resolvePath("demo.key", extension: "pdf", relativeTo: cwd)
        #expect(url.path == "/tmp/demo.key.pdf")
    }
}

@Suite("ExportFormat")
struct ExportFormatTests {

    @Test("Every format parses back from its own keyword", arguments: ExportFormat.allCases)
    func roundTrip(format: ExportFormat) {
        #expect(ExportFormat.parse(format.rawValue) == format)
        #expect(ExportFormat.parse(format.rawValue.uppercased()) == format)
    }

    @Test("Aliases land on PowerPoint", arguments: ["ppt", "powerpoint", "PowerPoint"])
    func powerPointAliases(text: String) {
        #expect(ExportFormat.parse(text) == .pptx)
    }

    @Test("Anything else is not a format", arguments: ["", "docx", "key", "pd"])
    func unknown(text: String) {
        #expect(ExportFormat.parse(text) == nil)
    }

    @Test("The keyword list is what /help and the usage string show")
    func keywordList() {
        #expect(ExportFormat.keywordList == "pdf|pptx")
    }
}
