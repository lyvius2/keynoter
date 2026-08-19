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
}
