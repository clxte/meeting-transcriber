// Pins the French localization tables in Localization/fr.lproj to the code
// that produces their keys.
//
// Two things about the tables cannot be checked by the compiler or by
// scripts/extract-localizable-keys.sh:
//
//  - `Localized.lookup(...)` keys are assembled at runtime (concatenated
//    literals), so the table entry must equal the assembled English byte for
//    byte or the lookup silently falls back to English. The producers are
//    called below with no table in the test bundle, which makes their output
//    exactly the key the running app will look up.
//  - A format-string value whose specifiers disagree with its key's (wrong
//    type, or an argument the key never supplies) garbles or crashes at
//    render time, in French only, on a machine we never test on.
//
// Not pinned, deliberately: assembled texts whose producers are private to a
// view (the caption footnotes, the tuning-knob help). A drifted entry there
// falls back to English, which is the designed failure mode.

import Foundation
@testable import MeetingTranscriber
import XCTest

@MainActor
final class LocalizationTableTests: XCTestCase {
    private static let lprojDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Localization/fr.lproj", isDirectory: true)

    private func loadFrenchStrings() throws -> [String: String] {
        let url = Self.lprojDir.appendingPathComponent("Localizable.strings")
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil,
        )
        return try XCTUnwrap(
            plist as? [String: String],
            "fr.lproj/Localizable.strings missing or unparseable",
        )
    }

    func testFrenchTableParsesAndIsNonEmpty() throws {
        let table = try loadFrenchStrings()
        XCTAssertFalse(table.isEmpty)
        for (key, value) in table {
            XCTAssertFalse(value.isEmpty, "Empty translation for key: \(key)")
        }
    }

    // MARK: - Assembled keys

    func testAssembledMessagesHaveFrenchEntries() throws {
        let table = try loadFrenchStrings()
        var producers: Set<String> = []

        // Channel-health bodies whose key is the full assembled sentence. The
        // two format-key arms — gave-up, and app digital silence that names
        // the Screen Recording pane — are compiler-extractable literals and
        // covered by the extraction script instead.
        for carried in [false, true] {
            producers.insert(ChannelHealthController.faultMessage(
                channel: .app, fault: .noBuffers, everCarriedSignal: carried,
            ))
            producers.insert(ChannelHealthController.faultMessage(
                channel: .mic, fault: .noBuffers, everCarriedSignal: carried,
            ))
            producers.insert(ChannelHealthController.faultMessage(
                channel: .mic, fault: .digitalSilence, everCarriedSignal: carried,
            ))
        }
        producers.insert(ChannelHealthController.faultMessage(
            channel: .app, fault: .digitalSilence, everCarriedSignal: true,
        ))
        producers.insert(ChannelHealthController.silentRecordingMessage(for: .micOnly))
        producers.insert(ChannelHealthController.silentRecordingMessage(for: .appOnly))
        producers.insert(ChannelHealthController.silentRecordingMessage(for: .micAndApp))

        producers.insert(SettingsHelp.echoCancellation)
        producers.insert(SettingsHelp.echoDedup)
        producers.insert(SettingsHelp.vad)
        producers.insert(SettingsHelp.silentCaptureChannel)
        producers.insert(SettingsHelp.asymmetricSilenceWarning)

        for readiness in [
            BrowserConsentReadiness.denied, .undetermined, .quiet, .bannersOff, .timeSensitiveOff,
        ] {
            if let warning = readiness.warning { producers.insert(warning) }
        }

        producers.insert(TranscriptionSettingsView.vocabularyHelpText(for: .whisperKit))
        producers.insert(TranscriptionSettingsView.vocabularyHelpText(for: .parakeet))
        producers.insert(TranscriptionSettingsView.whisperKitVocabularyPromptHelpText)

        // Assembled inline in the transcribe stage, unreachable without a
        // pipeline; restated so at least table drift is caught. Code drift
        // falls back to English, which nothing here can see.
        producers.insert(
            "Speaker diarization needs per-utterance timestamps, which the selected "
                + "transcription engine doesn't produce — speakers not labeled",
        )

        let missing = producers.filter { table[$0] == nil }.sorted()
        XCTAssertTrue(
            missing.isEmpty,
            "French table lacks entries for assembled keys:\n\(missing.joined(separator: "\n---\n"))",
        )
    }

    // MARK: - Format-specifier agreement

    func testFrenchValuesUseOnlyTheKeysFormatArguments() throws {
        let table = try loadFrenchStrings()
        for (key, value) in table {
            let keySpecs = specifiers(in: key)
            let valueSpecs = specifiers(in: value)
            for (position, kind) in valueSpecs {
                XCTAssertEqual(
                    keySpecs[position], kind,
                    "Value for key \"\(key)\" uses argument \(position) as %\(kind), which the key does not supply that way",
                )
            }
        }
    }

    /// Argument position → normalized conversion kind ("d" for every integer
    /// conversion, "f" for every float one). `%%` is a literal and carries no
    /// argument. Positional (`%1$`) and sequential specifiers both land on
    /// their printf argument index.
    ///
    /// Deliberately narrower than printf: no flags, no width. Keys built by
    /// `String(localized:)` interpolation never emit them (a literal % becomes
    /// %%), while `Localized.lookup` keys carry prose percent signs ("29% to
    /// 77%") that a flag-tolerant pattern misreads as specifiers ("% t" + "o"
    /// parsed as %o). Those lookup strings are never run through
    /// String(format:), so prose percents are safe to leave unmatched.
    private func specifiers(in format: String) -> [Int: Character] {
        let pattern = /%(?:(\d+)\$)?(?:\.\d+)?(?:hh|h|ll|l|q|z|t|L)?([@dioxXufeEgGaAcsSpF%])/
        var result: [Int: Character] = [:]
        var nextSequential = 1
        for match in format.matches(of: pattern) {
            let conversion = Character(String(match.2))
            if conversion == "%" { continue }
            let position = match.1.flatMap { Int($0) } ?? nextSequential
            nextSequential = position + 1
            let kind = normalize(conversion)
            if let existing = result[position] {
                XCTAssertEqual(existing, kind, "Argument \(position) used with two types in: \(format)")
            }
            result[position] = kind
        }
        return result
    }

    private func normalize(_ conversion: Character) -> Character {
        switch conversion {
        case "d", "i", "o", "u", "x", "X": "d"
        case "f", "e", "E", "g", "G", "a", "A", "F": "f"
        default: conversion
        }
    }

    // MARK: - Plurals

    func testStringsdictEntriesAreStructurallySound() throws {
        let url = Self.lprojDir.appendingPathComponent("Localizable.stringsdict")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]],
        )
        XCTAssertFalse(plist.isEmpty)
        let strings = try loadFrenchStrings()
        for (key, entry) in plist {
            XCTAssertNil(
                strings[key],
                "\(key) is in both .strings and .stringsdict; the dict wins and the .strings entry is dead",
            )
            let format = try XCTUnwrap(
                entry["NSStringLocalizedFormatKey"] as? String,
                "\(key) has no NSStringLocalizedFormatKey",
            )
            let variables = variableNames(in: format)
            XCTAssertFalse(variables.isEmpty, "\(key) references no %#@variable@")
            for name in variables {
                let variable = try XCTUnwrap(entry[name] as? [String: Any], "\(key) missing variable \(name)")
                XCTAssertEqual(variable["NSStringFormatSpecTypeKey"] as? String, "NSStringPluralRuleType")
                XCTAssertNotNil(variable["other"] as? String, "\(key)/\(name) needs the other category")
                // CLDR French: "one" covers 0 and 1 — the whole reason these
                // entries exist rather than a suffix argument.
                XCTAssertNotNil(variable["one"] as? String, "\(key)/\(name) needs the one category")
            }
        }
    }

    private func variableNames(in format: String) -> [String] {
        format.matches(of: /%(?:\d+\$)?#@([^@]+)@/).map { String($0.1) }
    }

    // MARK: - Permission prompts

    func testInfoPlistTableCoversExactlyTheUsageDescriptions() throws {
        let infoPlistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Info.plist")
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoPlistURL), format: nil,
            ) as? [String: Any],
        )
        let usageKeys = Set(plist.keys.filter { $0.hasSuffix("UsageDescription") })
        XCTAssertFalse(usageKeys.isEmpty)
        // The app name is localized too; the Finder ignores it without the flag.
        let nameKeys: Set = ["CFBundleName", "CFBundleDisplayName"]
        XCTAssertEqual(plist["LSHasLocalizedDisplayName"] as? Bool, true)

        let frURL = Self.lprojDir.appendingPathComponent("InfoPlist.strings")
        let fr = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: frURL), format: nil,
            ) as? [String: String],
            "fr.lproj/InfoPlist.strings missing or unparseable",
        )
        XCTAssertEqual(
            Set(fr.keys), usageKeys.union(nameKeys),
            "fr InfoPlist.strings must translate exactly the app name and the usage descriptions Info.plist declares",
        )
        for (key, value) in fr {
            XCTAssertFalse(value.isEmpty, "Empty translation for \(key)")
        }
    }
}
