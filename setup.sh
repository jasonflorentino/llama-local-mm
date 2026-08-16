#!/usr/bin/env bash
set -euo pipefail

readonly SERVICE_LABEL="com.home-llama.server"
readonly PLIST_PATH="/Library/LaunchDaemons/${SERVICE_LABEL}.plist"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&|]/\\&/g'
}

replace_token() {
  local file="$1"
  local token="$2"
  local value
  value="$(escape_sed_replacement "$3")"
  sed -i '' "s|${token}|${value}|g" "$file"
}

if [[ "$(id -u)" -eq 0 ]]; then
  die "Run this script as your normal user; it invokes sudo only where needed."
fi

cd "$(dirname "$0")"

[[ -f .env ]] || die "Missing .env. Run: cp .env.example .env"

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${SERVER_NAME:?SERVER_NAME is required}"
: "${LISTEN_PORT:?LISTEN_PORT is required}"
: "${LLAMA_PORT:?LLAMA_PORT is required}"
: "${LLAMA_MODEL:?LLAMA_MODEL is required}"
: "${LLAMA_CTX_SIZE:?LLAMA_CTX_SIZE is required}"
: "${LLAMA_PARALLEL:?LLAMA_PARALLEL is required}"

[[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || die "LISTEN_PORT must be numeric"
[[ "$LLAMA_PORT" =~ ^[0-9]+$ ]] || die "LLAMA_PORT must be numeric"
[[ "$LLAMA_CTX_SIZE" =~ ^[0-9]+$ ]] || die "LLAMA_CTX_SIZE must be numeric"
[[ "$LLAMA_PARALLEL" =~ ^[0-9]+$ ]] || die "LLAMA_PARALLEL must be numeric"
[[ -z "${LLAMA_THREADS:-}" || "$LLAMA_THREADS" =~ ^[0-9]+$ ]] ||
  die "LLAMA_THREADS must be empty or numeric"
[[ -z "${LLAMA_THREADS_BATCH:-}" || "$LLAMA_THREADS_BATCH" =~ ^[0-9]+$ ]] ||
  die "LLAMA_THREADS_BATCH must be empty or numeric"
[[ -z "${LLAMA_CACHE_RAM:-}" || "$LLAMA_CACHE_RAM" =~ ^(-1|[0-9]+)$ ]] ||
  die "LLAMA_CACHE_RAM must be empty, -1, or a non-negative integer"
[[ -z "${LLAMA_GPU_LAYERS:-}" || "$LLAMA_GPU_LAYERS" =~ ^([0-9]+|auto|all)$ ]] ||
  die "LLAMA_GPU_LAYERS must be empty, numeric, auto, or all"
[[ "$SERVER_NAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
  die "SERVER_NAME may contain only letters, numbers, dots, underscores, and hyphens"

require_command brew
require_command curl
require_command plutil

readonly BREW_BIN="$(command -v brew)"

echo "Installing or updating required Homebrew packages..."
brew list --formula llama.cpp >/dev/null 2>&1 || brew install llama.cpp
brew list --formula nginx >/dev/null 2>&1 || brew install nginx

readonly BREW_PREFIX="$(brew --prefix)"
readonly LLAMA_SERVER_BIN="$(command -v llama-server)"
readonly NGINX_BIN="$(command -v nginx)"
readonly USER_NAME="$(id -un)"
readonly GROUP_NAME="$(id -gn)"
readonly USER_HOME="$HOME"
readonly INSTALL_DIR="${BREW_PREFIX}/libexec/home-llama"
readonly CONFIG_PATH="${BREW_PREFIX}/etc/home-llama.env"
readonly RUNNER_PATH="${INSTALL_DIR}/run-llama-server"
readonly NGINX_SERVERS_DIR="${BREW_PREFIX}/etc/nginx/servers"
readonly NGINX_SITE_PATH="${NGINX_SERVERS_DIR}/${SERVER_NAME}.conf"
readonly LOG_DIR="${HOME}/Library/Logs/home-llama"

mkdir -p "$LOG_DIR"
touch "$LOG_DIR/llama-server.out.log" "$LOG_DIR/llama-server.err.log"
chmod 644 "$LOG_DIR/llama-server."*.log

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config_tmp="${tmp_dir}/home-llama.env"
{
  printf 'LLAMA_SERVER_BIN=%q\n' "$LLAMA_SERVER_BIN"
  printf 'LLAMA_MODEL=%q\n' "$LLAMA_MODEL"
  printf 'LLAMA_PORT=%q\n' "$LLAMA_PORT"
  printf 'LLAMA_CTX_SIZE=%q\n' "$LLAMA_CTX_SIZE"
  printf 'LLAMA_PARALLEL=%q\n' "$LLAMA_PARALLEL"
  printf 'LLAMA_DEVICE=%q\n' "${LLAMA_DEVICE:-}"
  printf 'LLAMA_THREADS=%q\n' "${LLAMA_THREADS:-}"
  printf 'LLAMA_THREADS_BATCH=%q\n' "${LLAMA_THREADS_BATCH:-}"
  printf 'LLAMA_CACHE_RAM=%q\n' "${LLAMA_CACHE_RAM:-}"
  printf 'LLAMA_GPU_LAYERS=%q\n' "${LLAMA_GPU_LAYERS:-}"
  printf 'LLAMA_API_KEY=%q\n' "${LLAMA_API_KEY:-}"
} > "$config_tmp"

plist_tmp="${tmp_dir}/${SERVICE_LABEL}.plist"
cp etc/com.home-llama.server.plist.template "$plist_tmp"
replace_token "$plist_tmp" "__RUNNER_PATH__" "$RUNNER_PATH"
replace_token "$plist_tmp" "__USER_NAME__" "$USER_NAME"
replace_token "$plist_tmp" "__GROUP_NAME__" "$GROUP_NAME"
replace_token "$plist_tmp" "__USER_HOME__" "$USER_HOME"
replace_token "$plist_tmp" "__CONFIG_PATH__" "$CONFIG_PATH"
replace_token "$plist_tmp" "__BREW_PREFIX__" "$BREW_PREFIX"
replace_token "$plist_tmp" "__LOG_DIR__" "$LOG_DIR"
plutil -lint "$plist_tmp"

nginx_tmp="${tmp_dir}/${SERVER_NAME}.conf"
cp etc/server.nginx.conf.template "$nginx_tmp"
replace_token "$nginx_tmp" "__SERVER_NAME__" "$SERVER_NAME"
replace_token "$nginx_tmp" "__LISTEN_PORT__" "$LISTEN_PORT"
replace_token "$nginx_tmp" "__LLAMA_PORT__" "$LLAMA_PORT"

echo "Installing the llama-server boot service..."
sudo install -d -m 755 "$INSTALL_DIR"
sudo install -m 755 bin/run-llama-server.sh "$RUNNER_PATH"
sudo install -m 600 "$config_tmp" "$CONFIG_PATH"
sudo chown root:wheel "$CONFIG_PATH" "$RUNNER_PATH"
sudo install -m 644 "$plist_tmp" "$PLIST_PATH"
sudo chown root:wheel "$PLIST_PATH"

if sudo launchctl print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
  sudo launchctl bootout system "$PLIST_PATH"
fi
sudo launchctl bootstrap system "$PLIST_PATH"
sudo launchctl enable "system/${SERVICE_LABEL}"
sudo launchctl kickstart -k "system/${SERVICE_LABEL}"

echo "Installing the nginx reverse-proxy configuration..."
sudo install -d -m 755 "$NGINX_SERVERS_DIR"
sudo install -m 644 "$nginx_tmp" "$NGINX_SITE_PATH"

if ! grep -Eq 'include[[:space:]]+([^;[:space:]]*/)?servers/\*' \
  "${BREW_PREFIX}/etc/nginx/nginx.conf"; then
  die "Homebrew nginx.conf does not include ${NGINX_SERVERS_DIR}/*. Add an include inside its http block, then rerun setup.sh."
fi

sudo "$NGINX_BIN" -t
sudo "$BREW_BIN" services restart nginx

echo "Waiting for the model to download and llama-server to become ready..."
for _ in {1..180}; do
  if curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null ||
  die "llama-server did not become ready. Check ${LOG_DIR}/llama-server.err.log"

curl -fsS -H "Host: ${SERVER_NAME}" \
  "http://127.0.0.1:${LISTEN_PORT}/healthz" >/dev/null ||
  die "nginx health check failed"

interface="$(route -n get default | awk '/interface:/{print $2}')"
lan_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"

echo
echo "Setup complete."
if [[ "$LISTEN_PORT" == "80" ]]; then
  echo "Web UI: http://${SERVER_NAME}"
else
  echo "Web UI: http://${SERVER_NAME}:${LISTEN_PORT}"
fi
if [[ -n "$lan_ip" ]]; then
  if [[ "$LISTEN_PORT" == "80" ]]; then
    echo "LAN fallback: http://${lan_ip}"
  else
    echo "LAN fallback: http://${lan_ip}:${LISTEN_PORT}"
  fi
fi
echo "Logs: ${LOG_DIR}"
