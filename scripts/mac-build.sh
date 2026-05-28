#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew &>/dev/null; then
  echo "Cài Homebrew trước: https://brew.sh" >&2
  exit 1
fi

if ! command -v dpkg-deb &>/dev/null; then
  echo "→ Cài dpkg..."
  brew install dpkg
fi

if [[ -z "${THEOS:-}" ]]; then
  export THEOS="$HOME/theos"
fi

if [[ ! -d "$THEOS" ]]; then
  echo "→ Cài Theos vào $THEOS (lần đầu ~5 phút)..."
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "→ Build package (chạy build.sh)..."
chmod +x build.sh deps/download-mongoose.sh deps/build-luajit-arm64.sh spoof/rename-to-xm.sh webide/download-monaco.sh
./build.sh

mkdir -p repo/pool/main
cp packages/*.deb repo/pool/main/
echo "→ Đã copy $(ls packages/*.deb | wc -l | tr -d ' ') file(s) sang repo/pool/main/"

echo "→ Update repo index..."
chmod +x scripts/update-repo.sh
./scripts/update-repo.sh

git add repo/
git commit -m "chore: update repo" 2>/dev/null || echo "(không có gì thay đổi, skip commit)"
git push

echo ""
echo "Xong. Sileo repo đã được cập nhật."
