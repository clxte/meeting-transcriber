// Runtime localization lookup for user-facing text whose English rendering is
// assembled rather than written as one literal.
//
// `String(localized:)` wants a single literal, which is also what the
// compiler's extraction (-emit-localized-strings) can enumerate. Long texts in
// this codebase are assembled from concatenated literals to respect the
// 160-column lint limit, and a few short ones come out of ternaries; neither
// shape can feed `String(localized:)` without reformatting the English. These
// sites pass the assembled English through this lookup instead: the full
// English sentence IS the table key, so the French table carries that exact
// sentence, and a missing (or drifted) entry falls back to the key — the
// English text — unchanged. `swift test` runs with no tables in Bundle.main,
// which is what keeps every test's expected string byte-identical English on
// any machine locale. LocalizationTableTests pins the French keys to the
// producers so the code and the table cannot drift silently.

import Foundation

enum Localized {
    /// Returns the localized rendering of runtime-assembled English text,
    /// or the text itself when no table entry exists.
    static func lookup(_ english: String) -> String {
        Bundle.main.localizedString(forKey: english, value: nil, table: nil)
    }
}
