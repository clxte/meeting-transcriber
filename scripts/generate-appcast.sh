#!/usr/bin/env bash
# Builds the single-item Sparkle appcast a release attaches next to its DMG.
#
# Sparkle resolves updates from the URL in Info.plist (SUFeedURL), which points
# at .../releases/latest/download/appcast.xml — GitHub serves the asset of the
# newest NON-prerelease release at that URL, so an RC's appcast is published
# with the RC but never offered to stable installs.
#
# The enclosure signature comes from `sign_update` out of the pinned Sparkle
# tools release (version AND checksum, same policy as the lint toolchain); the
# private key arrives via $SPARKLE_ED_PRIVATE_KEY — a GitHub secret in CI,
# exported from the keychain with `generate_keys -x`. One item only: Sparkle
# wants the newest version, not a history.
set -euo pipefail

SPARKLE_VERSION="2.9.6"
SPARKLE_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$SCRIPT_DIR/../app/MeetingTranscriber/Sources/Info.plist"

usage() {
    echo "usage: $0 --dmg <path> --version <x.y.z> --url <download-url> --output <path>" >&2
    exit 2
}

DMG="" VERSION="" URL="" OUTPUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dmg) DMG="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --url) URL="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$DMG" ] && [ -n "$VERSION" ] && [ -n "$URL" ] && [ -n "$OUTPUT" ] || usage
[ -f "$DMG" ] || { echo "ERROR: DMG not found: $DMG" >&2; exit 1; }
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is unset — export it with 'generate_keys -x'}"

tools_dir="$(mktemp -d)"
trap 'rm -rf "$tools_dir"' EXIT
curl -fsSL -o "$tools_dir/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
echo "$SPARKLE_SHA256  $tools_dir/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null || {
    echo "ERROR: Sparkle tools checksum mismatch for ${SPARKLE_VERSION}." >&2
    exit 1
}
tar -x -f "$tools_dir/sparkle.tar.xz" -C "$tools_dir" bin/sign_update

# sign_update prints the ready-made attribute pair:
#   sparkle:edSignature="…" length="…"
signature="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tools_dir/bin/sign_update" --ed-key-file - "$DMG")"

min_system="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST")"

cat > "$OUTPUT" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Meeting Transcriber</title>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${min_system}</sparkle:minimumSystemVersion>
            <enclosure url="${URL}" ${signature} type="application/octet-stream"/>
        </item>
    </channel>
</rss>
APPCAST
echo "Appcast written: $OUTPUT"
