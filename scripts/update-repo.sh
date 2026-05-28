#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../repo" && pwd)"
POOL_DIR="$REPO_DIR/pool/main"

# ── Dependency check ────────────────────────────────────────────────────────
if ! command -v dpkg-deb &>/dev/null; then
  echo "Error: dpkg-deb not found. Install with: brew install dpkg" >&2
  exit 1
fi

# macOS md5 vs Linux md5sum
if command -v md5 &>/dev/null && ! command -v md5sum &>/dev/null; then
  md5sum() { md5 -q "$1"; }
fi

sha256sum_file() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ── Build Packages ──────────────────────────────────────────────────────────
PACKAGES_FILE="$REPO_DIR/Packages"
> "$PACKAGES_FILE"

shopt -s nullglob
debs=("$POOL_DIR"/*.deb)

if [[ ${#debs[@]} -eq 0 ]]; then
  echo "Warning: no .deb files found in $POOL_DIR" >&2
  echo "Copy your built .deb there before running this script." >&2
fi

for deb in "${debs[@]}"; do
  basename_deb="$(basename "$deb")"
  size="$(wc -c < "$deb" | tr -d ' ')"
  md5="$(md5sum "$deb" | awk '{print $1}')"
  sha256="$(sha256sum_file "$deb")"

  # Extract control fields from the .deb
  control="$(dpkg-deb --field "$deb")"

  {
    echo "$control"
    printf "Filename: pool/main/%s\nSize: %s\nMD5sum: %s\nSHA256: %s\n\n" \
      "$basename_deb" "$size" "$md5" "$sha256"
  } >> "$PACKAGES_FILE"

  echo "  + $basename_deb (${size} bytes)"
done

# ── Compress ────────────────────────────────────────────────────────────────
gzip -9 -c "$PACKAGES_FILE" > "$REPO_DIR/Packages.gz"
bzip2 -9 -c "$PACKAGES_FILE" > "$REPO_DIR/Packages.bz2"

# ── Regenerate Release checksums ────────────────────────────────────────────
RELEASE_FILE="$REPO_DIR/Release"

# Strip any previous checksum blocks
perl -i -0pe 's/\nMD5Sum:.*//s' "$RELEASE_FILE" 2>/dev/null || true

{
  echo ""
  echo "MD5Sum:"
  for f in Packages Packages.gz Packages.bz2; do
    hash="$(md5sum "$REPO_DIR/$f" | awk '{print $1}')"
    size="$(wc -c < "$REPO_DIR/$f" | tr -d ' ')"
    printf " %s %16s %s\n" "$hash" "$size" "$f"
  done
  echo "SHA256:"
  for f in Packages Packages.gz Packages.bz2; do
    hash="$(sha256sum_file "$REPO_DIR/$f")"
    size="$(wc -c < "$REPO_DIR/$f" | tr -d ' ')"
    printf " %s %16s %s\n" "$hash" "$size" "$f"
  done
} >> "$RELEASE_FILE"

echo ""
echo "Repo updated → $REPO_DIR"
echo "Packages: ${#debs[@]} package(s)"
echo ""
echo "Next: git add repo/ && git commit -m 'chore: update repo' && git push"
