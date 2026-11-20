#!/usr/bin/env bash
# Build the UNSIGNED Sumi plugin install layout plus a verifiable checklist.json.
#   build-artifact.sh --target <triple> --out <dir> [--debug]
# <dir> ends up holding exactly stage/ and checklist.json. Signing, notarization,
# packaging and listing happen in note.md; this script reads no credential.
set -euo pipefail

usage() { echo "usage: build-artifact.sh --target <triple> --out <dir> [--debug]" >&2; exit 2; }

triple="" out="" profile="release"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) [[ $# -ge 2 ]] || usage; triple="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || usage; out="$2"; shift 2 ;;
    --debug) profile="debug"; shift ;;
    *) usage ;;
  esac
done
[[ -n "$triple" && -n "$out" ]] || usage

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$(cd "$here/.." && pwd)"
repo="$(git -C "$app" rev-parse --show-toplevel)"
manifest="$app/manifest.v2.json"
export PATH="$HOME/.cargo/bin:$PATH"

case "$triple" in
  aarch64-apple-darwin|x86_64-apple-darwin|x86_64-unknown-linux-gnu) ;;
  *) echo "Unsupported Sumi target: $triple" >&2; exit 1 ;;
esac
node -e 'const m=require(process.argv[1]);if(m.binary?.[process.argv[2]]!=="bin/notemd-sumi")throw Error("Sumi native manifest target mismatch")' "$manifest" "$triple"

if [[ "$profile" == release ]] && ! git -C "$repo" diff --quiet HEAD; then
  echo "Refusing a release build: tracked files are modified, so source_commit would be untruthful. Commit or stash, or use --debug." >&2
  exit 1
fi
if [[ "$profile" == release ]]; then
  untracked="$(git -C "$repo" ls-files --others --exclude-standard -- apps/notemd-plugin)"
  if [[ -n "$untracked" ]]; then
    echo "Refusing a release build: untracked files under apps/notemd-plugin would not be described by source_commit:" >&2
    echo "$untracked" >&2
    exit 1
  fi
fi
if [[ -e "$out" ]] && [[ -n "$(ls -A "$out" 2>/dev/null || echo x)" ]]; then
  echo "Output directory exists and is not empty: $out" >&2
  exit 1
fi

source_commit="$(git -C "$repo" rev-parse HEAD)"
version="$(node -e 'console.log(require(process.argv[1]).version)' "$manifest")"
source_tag=""
if t="$(git -C "$repo" describe --exact-match --tags HEAD 2>/dev/null)" && [[ "$t" == "notemd-plugin-v$version" ]]; then
  source_tag="$t"
fi

# Backend (no workspace: target dir is backend/target/<triple>/<profile>).
cargo_args=(build --locked --manifest-path "$app/backend/Cargo.toml" --bin notemd-sumi --target "$triple")
[[ "$profile" == release ]] && cargo_args+=(--release)
cargo +1.99.0 "${cargo_args[@]}"
binary="$app/backend/target/$triple/$profile/notemd-sumi"
[[ -f "$binary" ]] || { echo "Missing backend binary: $binary" >&2; exit 1; }
if [[ "$triple" == *-unknown-linux-gnu ]]; then
  python3 -I "$here/verify-linux-binary.py" "$binary" --target "$triple"
fi

# Frontend.
npm --prefix "$app" ci
npm --prefix "$app" run check
npm --prefix "$app" run build

# Assemble in a temp dir, then move into place.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/stage"
mkdir -p "$stage/bin" "$stage/ui" "$stage/resources"
cp "$manifest" "$stage/manifest.json"
cp "$binary" "$stage/bin/notemd-sumi"
chmod +x "$stage/bin/notemd-sumi"
cp -R "$app/dist/." "$stage/ui/"
# Vite copies public resources into dist. Verify sounds before moving only that
# exact directory out of ui; ship one native-readable copy per package.
python3 -I "$here/verify-sounds.py" "$stage/ui/sounds" --reference "$app/resources/sounds"
mv "$stage/ui/sounds" "$stage/resources/sounds"
python3 -I "$here/verify-sounds.py" "$stage/resources/sounds" --reference "$app/resources/sounds"
python3 -I "$here/verify-stage.py" --stage "$stage" --verify-fonts --source "$app/resources/sumi"
python3 -I "$here/verify-stage.py" --stage "$stage" --write-checklist "$work/checklist.json" \
  --manifest "$manifest" --cargo-toml "$app/backend/Cargo.toml" --target "$triple" \
  --source-commit "$source_commit" --source-tag "$source_tag"
python3 -I "$here/verify-stage.py" --stage "$stage" --verify-checklist "$work/checklist.json"

mkdir -p "$out"
mv "$stage" "$out/stage"
mv "$work/checklist.json" "$out/checklist.json"
echo "unsigned artifact ($profile, $triple) -> $out"
