#!/usr/bin/env bash
# Installs the UI translation tables every assembled app bundle carries.
#
# The tables live in app/MeetingTranscriber/Localization/<lang>.lproj and are
# copied into Contents/Resources at bundle-assembly time — deliberately NOT
# declared as SPM target resources:
#
#  - SwiftUI's LocalizedStringKey and String(localized:) resolve against
#    Bundle.main by default. A table in the main bundle localizes every
#    existing `Text("...")` literal as-is; a table in an SPM resource bundle
#    (Bundle.module) would localize nothing until every call site is rewritten
#    to pass `bundle:`.
#  - `swift build` / `swift test` never see the tables, so every string a test
#    asserts on stays byte-identical English regardless of the machine's
#    locale. A French dev Mac cannot flip test output to French.
#
# English ships as no table at all: the code's literals ARE the English
# rendering, and CFBundleDevelopmentRegion=en sends every non-French system to
# them. A key missing from the French table falls back the same way — to the
# English literal, never to a placeholder.
#
# Two scripts assemble a bundle (build_release.sh, run_app.sh) and both source
# this, for the same no-drift reason as lib/localvqe-resources.sh. Fatal in
# both callers: the tables are repo files, so a failed copy is a repo bug, not
# an unreachable download.
#
# Source this, don't execute it.

# Copies every <lang>.lproj under app/MeetingTranscriber/Localization/ into the
# given Resources directory. Adding a language later is dropping a new .lproj
# into that directory; no build script learns its name.
install_localization_resources() {
    local resources_dir="$1"
    local lib_dir loc_src dir
    local -a lproj_dirs
    # Guarded because the rm below is a glob: an empty argument would aim it
    # at the filesystem root instead of a bundle.
    [ -n "$resources_dir" ] || { echo "  ERROR: no Resources directory given" >&2; return 1; }
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
    loc_src="$lib_dir/../../app/MeetingTranscriber/Localization"

    # Collected rather than globbed straight into cp so an empty directory is
    # a hard stop with an honest message instead of a cp error about a literal
    # "*.lproj" path.
    lproj_dirs=("$loc_src"/*.lproj)
    if [ ! -e "${lproj_dirs[0]}" ]; then
        echo "  ERROR: no .lproj directories in $loc_src" >&2
        return 1
    fi

    mkdir -p "$resources_dir" || return 1
    # run_app.sh reuses its bundle across builds; a language removed from the
    # repo must not survive inside the assembled app. Unquoted on purpose so
    # the shell expands the pattern; -f keeps a first run (no match, literal
    # argument) silent.
    # shellcheck disable=SC2086
    rm -rf "$resources_dir"/*.lproj || return 1
    for dir in "${lproj_dirs[@]}"; do
        cp -R "$dir" "$resources_dir/" || return 1
    done
    echo "  Localizations: ${lproj_dirs[*]##*/}"
}
