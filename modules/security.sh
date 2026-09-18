#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
install_security() { apt-get update; apt-get install -y fail2ban unattended-upgrades; systemctl enable --now fail2ban; say "Fail2ban and automatic security updates enabled."; }
require_root
while true; do clear; say "===== Security ====="; say "1. Install Fail2ban and unattended upgrades"; say "2. Status"; say "0. Back"; read -r -p "Select: " c; case "$c" in 1) install_security; read -r -p "Press Enter..." _;;2) systemctl --no-pager status fail2ban || true; read -r -p "Press Enter..." _;;0) exit;;*) say "Invalid selection.";;esac; done
