import Foundation
import Testing
@testable import Keynoter

@Suite("Doctor evaluators")
struct DoctorEvaluatorTests {

    // MARK: - macOS

    @Test("macOS at or above the minimum passes and echoes the version")
    func macOSAtMinimum() {
        let check = Doctor.macOSCheck(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
        #expect(check.severity == .ok)
        #expect(check.detail.contains("26.0.0"))
    }

    @Test("A newer major version still passes")
    func macOSNewer() {
        let check = Doctor.macOSCheck(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 3, patchVersion: 1)
        )
        #expect(check.severity == .ok)
        #expect(check.detail.contains("27.3.1"))
    }

    @Test("Older macOS fails and names the minimum")
    func macOSTooOld() {
        let check = Doctor.macOSCheck(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 5, patchVersion: 0)
        )
        #expect(check.severity == .fail)
        #expect(check.detail.contains("15.5.0"))
        #expect(check.detail.contains("\(Doctor.minimumMacOSMajor)"))
    }

    // MARK: - Xcode toolchain

    @Test("An Xcode path passes")
    func toolchainXcode() {
        let check = Doctor.toolchainCheck("/Applications/Xcode.app/Contents/Developer")
        #expect(check.severity == .ok)
    }

    @Test("A Command Line Tools path fails and points at xcode-select")
    func toolchainCommandLineTools() {
        let check = Doctor.toolchainCheck("/Library/Developer/CommandLineTools")
        #expect(check.severity == .fail)
        #expect(check.detail.contains("xcode-select"))
    }

    @Test("A missing toolchain path fails", arguments: [nil, ""])
    func toolchainMissing(_ path: String?) {
        #expect(Doctor.toolchainCheck(path).severity == .fail)
    }

    @Test("An unrecognized toolchain path warns")
    func toolchainUnknown() {
        let check = Doctor.toolchainCheck("/opt/some-other-toolchain")
        #expect(check.severity == .warn)
    }

    // MARK: - Keynote install

    @Test("A resolved Keynote bundle passes")
    func keynoteFound() {
        let check = Doctor.keynoteCheck(URL(fileURLWithPath: "/Applications/Keynote.app"))
        #expect(check.severity == .ok)
        #expect(check.detail.contains("Keynote.app"))
    }

    @Test("A missing Keynote fails")
    func keynoteMissing() {
        #expect(Doctor.keynoteCheck(nil).severity == .fail)
    }

    // MARK: - Apple Intelligence

    @Test("Apple Intelligence available passes")
    func intelligenceAvailable() {
        #expect(Doctor.appleIntelligenceCheck(.available).severity == .ok)
    }

    @Test("Apple Intelligence unavailable carries the reason through")
    func intelligenceUnavailable() {
        let check = Doctor.appleIntelligenceCheck(.unavailable(reason: "device not eligible"))
        #expect(check.severity == .fail)
        #expect(check.detail.contains("device not eligible"))
    }

    @Test("Apple Intelligence framework not linked fails")
    func intelligenceNotLinked() {
        let check = Doctor.appleIntelligenceCheck(.notLinked)
        #expect(check.severity == .fail)
        #expect(check.detail.contains("FoundationModels"))
    }

    // MARK: - Automation permission

    @Test("Automation granted passes")
    func automationGranted() {
        #expect(Doctor.automationCheck(.granted).severity == .ok)
    }

    @Test("Automation denied fails and points at System Settings")
    func automationDenied() {
        let check = Doctor.automationCheck(.denied)
        #expect(check.severity == .fail)
        #expect(check.detail.contains("System Settings"))
    }

    @Test("Automation not-yet-determined warns")
    func automationNotDetermined() {
        #expect(Doctor.automationCheck(.notDetermined).severity == .warn)
    }

    @Test("Unknown automation status warns and surfaces the reason")
    func automationUnknown() {
        let check = Doctor.automationCheck(.unknown(reason: "Keynote is not running"))
        #expect(check.severity == .warn)
        #expect(check.detail.contains("Keynote is not running"))
    }
}

@Suite("Doctor report aggregation")
struct DoctorReportTests {

    private func report(_ severities: [Doctor.Severity]) -> Doctor.Report {
        Doctor.Report(
            checks: severities.enumerated().map { index, severity in
                Doctor.Check(name: "check\(index)", severity: severity, detail: "")
            }
        )
    }

    @Test("All ok rolls up to ok")
    func allOK() {
        #expect(report([.ok, .ok, .ok]).overall == .ok)
    }

    @Test("A warn (without any fail) rolls up to warn")
    func anyWarn() {
        #expect(report([.ok, .warn, .ok]).overall == .warn)
    }

    @Test("A fail wins over a warn")
    func failWinsOverWarn() {
        #expect(report([.ok, .warn, .fail]).overall == .fail)
    }

    @Test("An empty report is treated as ok")
    func empty() {
        #expect(report([]).overall == .ok)
    }
}
