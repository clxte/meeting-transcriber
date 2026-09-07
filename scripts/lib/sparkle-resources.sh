#!/usr/bin/env bash
# Installs (and for release builds, re-signs) the Sparkle auto-update
# framework in an assembled app bundle.
#
# Sparkle is the in-app update channel: the app checks the appcast feed named
# in Info.plist (SUFeedURL) and offers signed updates — no Homebrew, no manual
# DMG round-trips. SPM links the framework dynamically, so the executable
# expects it at @executable_path/../Frameworks (rpath set in Package.swift)
# and every bundle assembler has to copy it there. Same no-drift arrangement
# as lib/localvqe-resources.sh: both build_release.sh and run_app.sh source
# this.
#
# The App Store variant embeds it too, even though its updater code is
# compiled out (#if !APPSTORE): the load command remains in the executable,
# so a bundle without the framework would fail at dyld time. A genuine Mac
# App Store submission would need Sparkle stripped entirely — this fork does
# not submit there.
#
# Source this, don't execute it.

# Copies Sparkle.framework from the SPM build products directory into
# <contents-dir>/Frameworks, replacing any previous copy.
install_sparkle_framework() {
    local contents_dir="$1" products_dir="$2"
    local fw="$products_dir/Sparkle.framework"
    [ -n "$contents_dir" ] || { echo "  ERROR: no Contents directory given" >&2; return 1; }
    [ -d "$fw" ] || { echo "  ERROR: Sparkle.framework not found at $fw" >&2; return 1; }
    mkdir -p "$contents_dir/Frameworks" || return 1
    rm -rf "$contents_dir/Frameworks/Sparkle.framework" || return 1
    # cp -R preserves the framework's Versions/ symlink structure.
    cp -R "$fw" "$contents_dir/Frameworks/" || return 1
    echo "  Sparkle.framework: $contents_dir/Frameworks/"
}

# Re-signs the nested Sparkle executables inside-out with the given identity,
# then the framework itself. Needed for the notarized build only: a
# hardened-runtime app loads only frameworks signed by its own team (library
# validation), so the framework cannot ship with the Sparkle project's
# signature. The dev build is not hardened and loads the original signature
# as-is, which is why run_app.sh installs but never calls this.
sign_sparkle_framework() {
    local contents_dir="$1" identity="$2"
    local fw="$contents_dir/Frameworks/Sparkle.framework"
    local fwv="$fw/Versions/B"
    local nested
    [ -d "$fw" ] || { echo "  ERROR: no Sparkle.framework in $contents_dir/Frameworks" >&2; return 1; }
    # XPC services keep their entitlements (Sparkle's sandboxing story relies
    # on them); the plain executables need none.
    for nested in "$fwv/XPCServices/Installer.xpc" "$fwv/XPCServices/Downloader.xpc"; do
        [ -e "$nested" ] || continue
        codesign --force --options runtime --timestamp \
            --preserve-metadata=entitlements --sign "$identity" "$nested" || return 1
    done
    for nested in "$fwv/Autoupdate" "$fwv/Updater.app"; do
        [ -e "$nested" ] || continue
        codesign --force --options runtime --timestamp --sign "$identity" "$nested" || return 1
    done
    codesign --force --options runtime --timestamp --sign "$identity" "$fw" || return 1
    echo "  Signed Sparkle.framework (nested executables first)"
}
