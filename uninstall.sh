#!/usr/bin/env bash
set -euo pipefail

readonly SERVICE_LABEL="com.home-llama.server"
readonly PLIST_PATH="/Library/LaunchDaemons/${SERVICE_LABEL}.plist"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as your normal user; it invokes sudo where needed." >&2
  exit 1
fi

cd "$(dirname "$0")"
[[ -f .env ]] || {
  echo "Missing .env; it is needed to identify the nginx site." >&2
  exit 1
}

set -a
# shellcheck disable=SC1091
source .env
set +a

readonly BREW_PREFIX="$(brew --prefix)"
readonly INSTALL_DIR="${BREW_PREFIX}/libexec/home-llama"
readonly CONFIG_PATH="${BREW_PREFIX}/etc/home-llama.env"
readonly NGINX_SITE_PATH="${BREW_PREFIX}/etc/nginx/servers/${SERVER_NAME}.conf"

if sudo launchctl print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
  sudo launchctl bootout system "$PLIST_PATH"
fi

sudo rm -f "$PLIST_PATH" "$CONFIG_PATH" "$NGINX_SITE_PATH"
sudo rm -f "${INSTALL_DIR}/run-llama-server"
sudo rmdir "$INSTALL_DIR" 2>/dev/null || true

sudo "$(command -v nginx)" -t
if pgrep -x nginx >/dev/null 2>&1; then
  sudo "$(command -v nginx)" -s reload
fi

echo "Removed the llama-server service and nginx site."
echo "Model cache, logs, Homebrew packages, and your .env were left intact."
