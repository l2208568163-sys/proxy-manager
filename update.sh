#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
require_root
git -C "$BASE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Installed project is not a Git checkout."
say "Current version: $(<"$BASE_DIR/VERSION")"
git -C "$BASE_DIR" fetch --prune origin
git -C "$BASE_DIR" pull --ff-only origin main
find "$BASE_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
systemctl daemon-reload
restart_if_active xray; restart_if_active mihomo; restart_if_active nginx
say "Update completed. Current version: $(<"$BASE_DIR/VERSION")"
