#!/usr/bin/env bash
set -euo pipefail
sumi_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$sumi_root"
sumi_wrangler="$sumi_root/node_modules/.bin/wrangler"
sumi_version="$(node -p "require('./node_modules/wrangler/package.json').version")"
if [[ "$sumi_version" != "3.114.17" ]]; then
  echo "Expected pinned Wrangler 3.114.17 (run npm ci); refusing an unverified deployment toolchain." >&2
  exit 1
fi
mkdir -p .local
export WRANGLER_LOG_PATH="$sumi_root/.local/wrangler.log"
export WRANGLER_SEND_METRICS=false
case "${1:---dry-run}" in
  --dry-run)
    "$sumi_wrangler" deploy --dry-run --outdir .local/bundle
    ;;
  --deploy)
    # Account API Token only. This never invokes browser OAuth or prints credentials.
    : "${CLOUDFLARE_API_TOKEN:?Set the existing Account API Token in the environment}"
    : "${CLOUDFLARE_ACCOUNT_ID:?Set the intended Cloudflare account ID}"
    "$sumi_wrangler" deploy
    ;;
  *) echo 'Usage: scripts/deploy.sh [--dry-run|--deploy]' >&2; exit 2 ;;
esac
