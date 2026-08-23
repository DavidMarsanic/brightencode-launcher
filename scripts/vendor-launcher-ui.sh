#!/usr/bin/env bash
# Populates vendor/launcher-ui/ (tauri.conf.json's frontendDist) from the
# version pinned in launcher-ui.version — the "update, don't live-swap"
# mechanism described in CLAUDE.md. Run automatically by tauri.conf.json's
# beforeDevCommand/beforeBuildCommand; safe to run by hand too.
#
# For local UI iteration without a tag/release round-trip, set
# LAUNCHER_UI_LOCAL to a checkout of brightencode-launcher-ui instead:
#   LAUNCHER_UI_LOCAL=../brightencode-launcher-ui ./scripts/vendor-launcher-ui.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_dir="$repo_root/vendor/launcher-ui"
pin_file="$repo_root/launcher-ui.version"
marker_file="$vendor_dir/.vendored-from"

if [ -n "${LAUNCHER_UI_LOCAL:-}" ]; then
  if [ ! -f "$LAUNCHER_UI_LOCAL/index.html" ]; then
    echo "error: LAUNCHER_UI_LOCAL=$LAUNCHER_UI_LOCAL doesn't look like a brightencode-launcher-ui checkout (no index.html)" >&2
    exit 1
  fi
  echo "Vendoring launcher-ui from local checkout: $LAUNCHER_UI_LOCAL"
  rm -rf "$vendor_dir"
  mkdir -p "$vendor_dir"
  cp "$LAUNCHER_UI_LOCAL/index.html" "$LAUNCHER_UI_LOCAL/main.js" "$LAUNCHER_UI_LOCAL/styles.css" "$vendor_dir/"
  echo "local:$LAUNCHER_UI_LOCAL" > "$marker_file"
  exit 0
fi

if [ ! -f "$pin_file" ]; then
  echo "error: $pin_file is missing — nothing to vendor. Create it with the launcher-ui tag to pin, e.g. \"v0.1.0\"." >&2
  exit 1
fi

pin="$(tr -d '[:space:]' < "$pin_file")"
if [ -z "$pin" ]; then
  echo "error: $pin_file is empty — expected a launcher-ui release tag, e.g. \"v0.1.0\"." >&2
  exit 1
fi

if [ -f "$marker_file" ] && [ "$(cat "$marker_file")" = "$pin" ] && [ -f "$vendor_dir/index.html" ]; then
  echo "vendor/launcher-ui already matches pinned version $pin, skipping fetch (set FORCE=1 to re-fetch)."
  if [ "${FORCE:-}" != "1" ]; then
    exit 0
  fi
fi

base_url="https://github.com/DavidMarsanic/brightencode-launcher-ui/releases/download/$pin"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Fetching brightencode-launcher-ui $pin..."
if ! curl -fsSL "$base_url/launcher-ui.zip" -o "$tmp_dir/launcher-ui.zip"; then
  echo "error: failed to download $base_url/launcher-ui.zip — is $pin a real published release of brightencode-launcher-ui?" >&2
  exit 1
fi
if ! curl -fsSL "$base_url/launcher-ui.zip.sha256" -o "$tmp_dir/launcher-ui.zip.sha256"; then
  echo "error: failed to download the checksum for $pin ($base_url/launcher-ui.zip.sha256)" >&2
  exit 1
fi

echo "Verifying checksum..."
if ! (cd "$tmp_dir" && shasum -a 256 -c launcher-ui.zip.sha256); then
  echo "error: launcher-ui.zip for $pin failed checksum verification — refusing to vendor a corrupted/tampered build." >&2
  exit 1
fi

rm -rf "$vendor_dir"
mkdir -p "$vendor_dir"
unzip -q "$tmp_dir/launcher-ui.zip" -d "$vendor_dir"
echo "$pin" > "$marker_file"

echo "Vendored launcher-ui $pin into $vendor_dir"
