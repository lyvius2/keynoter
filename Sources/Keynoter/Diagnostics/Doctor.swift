import Foundation
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Environment diagnostics behind `/doctor`.
///
/// Every system probe is split into two halves: a `probe*` that reads the world
/// and a pure `*Check` that maps that reading to a `Check`. Tests exercise the
/// evaluators with hand-built inputs so the suite never has to touch subprocesses,
/// the FoundationModels framework, or the Apple Events database.
enum Doctor {

    // MARK: - Types

    enum Severity: String, Sendable, CaseIterable {
        case ok
        case warn
        case fail
    }

    struct Check: Equatable, Sendable {
        let name: String
        let severity: Severity
        let detail: String
    }

    struct Report: Equatable, Sendable {
        let checks: [Check]

        /// Rolled up so `/doctor`'s trailing line matches the worst individual check.
        var overall: Severity {
            if checks.contains(where: { $0.severity == .fail }) { return .fail }
            if checks.contains(where: { $0.severity == .warn }) { return .warn }
            return .ok
        }
    }

    /// Everything the evaluator layer needs to know about SystemLanguageModel,
    /// framed so the FoundationModels-free build path still has something to say.
    enum AppleIntelligenceState: Equatable, Sendable {
        case available
        case unavailable(reason: String)
        case notLinked
    }

    /// Result of `AEDeterminePermissionToAutomateTarget` for Keynote, translated
    /// into the four states `/doctor` cares about.
    enum AutomationState: Equatable, Sendable {
        case granted
        case denied
        case notDetermined
        case unknown(reason: String)
    }

    // MARK: - Constants

    static let minimumMacOSMajor = 26
    static let keynoteBundleID = "com.apple.iWork.Keynote"

    // MARK: - Pure evaluators

    static func macOSCheck(_ version: OperatingSystemVersion) -> Check {
        let display = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if version.majorVersion >= minimumMacOSMajor {
            return Check(name: "macOS", severity: .ok, detail: display)
        }
        return Check(
            name: "macOS",
            severity: .fail,
            detail: "\(display) — macOS \(minimumMacOSMajor) or later is required"
        )
    }

    static func toolchainCheck(_ developerDir: String?) -> Check {
        guard let developerDir, !developerDir.isEmpty else {
            return Check(
                name: "Xcode toolchain",
                severity: .fail,
                detail: "xcode-select did not report a developer directory"
            )
        }
        if developerDir.contains("CommandLineTools") {
            return Check(
                name: "Xcode toolchain",
                severity: .fail,
                detail: "\(developerDir) — Command Line Tools cannot build this package. Run: sudo xcode-select -s /Applications/Xcode.app"
            )
        }
        if developerDir.contains("Xcode") {
            return Check(name: "Xcode toolchain", severity: .ok, detail: developerDir)
        }
        return Check(
            name: "Xcode toolchain",
            severity: .warn,
            detail: "\(developerDir) — unrecognized toolchain path; the FoundationModels SDK may be missing"
        )
    }

    static func keynoteCheck(_ installLocation: URL?) -> Check {
        if let installLocation {
            return Check(name: "Keynote", severity: .ok, detail: installLocation.path)
        }
        return Check(
            name: "Keynote",
            severity: .fail,
            detail: "Keynote.app not found — install it from the Mac App Store"
        )
    }

    static func appleIntelligenceCheck(_ state: AppleIntelligenceState) -> Check {
        switch state {
        case .available:
            return Check(
                name: "Apple Intelligence",
                severity: .ok,
                detail: "SystemLanguageModel available"
            )
        case .unavailable(let reason):
            return Check(name: "Apple Intelligence", severity: .fail, detail: reason)
        case .notLinked:
            return Check(
                name: "Apple Intelligence",
                severity: .fail,
                detail: "FoundationModels framework not linked — rebuild with Xcode 26"
            )
        }
    }

    static func automationCheck(_ state: AutomationState) -> Check {
        switch state {
        case .granted:
            return Check(name: "Keynote automation", severity: .ok, detail: "granted")
        case .denied:
            return Check(
                name: "Keynote automation",
                severity: .fail,
                detail: "denied — allow this terminal to control Keynote in System Settings > Privacy & Security > Automation"
            )
        case .notDetermined:
            return Check(
                name: "Keynote automation",
                severity: .warn,
                detail: "not yet granted — you will be prompted on the first Keynote action"
            )
        case .unknown(let reason):
            return Check(name: "Keynote automation", severity: .warn, detail: reason)
        }
    }

    // MARK: - Live report

    static func report() -> Report {
        Report(checks: [
            macOSCheck(ProcessInfo.processInfo.operatingSystemVersion),
            toolchainCheck(probeDeveloperDir()),
            keynoteCheck(probeKeynoteInstall()),
            appleIntelligenceCheck(probeAppleIntelligence()),
            automationCheck(probeAutomation())
        ])
    }

    // MARK: - Live probes (not directly tested)

    /// `DEVELOPER_DIR` wins because the CLAUDE.md workflow relies on it for users
    /// who cannot `sudo xcode-select -s`.
    private static func probeDeveloperDir() -> String? {
        if let envDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !envDir.isEmpty {
            return envDir
        }
        return runXcodeSelect()
    }

    private static func runXcodeSelect() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    private static func probeKeynoteInstall() -> URL? {
        #if canImport(AppKit)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: keynoteBundleID) {
            return url
        }
        #endif
        let fallback = "/Applications/Keynote.app"
        return FileManager.default.fileExists(atPath: fallback)
            ? URL(fileURLWithPath: fallback)
            : nil
    }

    private static func probeAppleIntelligence() -> AppleIntelligenceState {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            // Shared with the planner rather than worded twice: two independent
            // explanations of the same three states is how they drift apart.
            return .unavailable(reason: FoundationModelClient.describe(reason))
        @unknown default:
            return .unavailable(reason: "SystemLanguageModel is not available")
        }
        #else
        // Currently unreachable: `AI/` imports FoundationModels unconditionally,
        // so a toolchain without the framework fails to build the target long
        // before /doctor runs. Kept so the check still has an honest answer if
        // that import ever becomes conditional.
        return .notLinked
        #endif
    }


    private static func probeAutomation() -> AutomationState {
        #if canImport(ApplicationServices)
        let data = Data(keynoteBundleID.utf8)
        var addressDesc = AEDesc()
        let createStatus = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return OSStatus(-50) }
            return OSStatus(AECreateDesc(
                DescType(typeApplicationBundleID),
                baseAddress,
                data.count,
                &addressDesc
            ))
        }
        guard createStatus == noErr else {
            return .unknown(reason: "AECreateDesc failed (\(createStatus))")
        }
        defer { AEDisposeDesc(&addressDesc) }

        let status = AEDeterminePermissionToAutomateTarget(
            &addressDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        )
        switch status {
        case noErr:
            return .granted
        case -1743: // errAEEventNotPermitted
            return .denied
        case -1744: // errAEEventWouldRequireUserConsent
            return .notDetermined
        case -600:  // procNotFound
            return .unknown(reason: "Keynote is not running — permission is verified on first launch")
        default:
            return .unknown(reason: "AEDeterminePermissionToAutomateTarget returned \(status)")
        }
        #else
        return .unknown(reason: "ApplicationServices unavailable on this platform")
        #endif
    }
}
