#!/usr/bin/env bash
set -euo pipefail

readonly ENV_FILE=".env"
readonly BACKUP_FILE=".env.before-model-switch"

die() {
  echo "Error: $*" >&2
  exit 1
}

if [[ "$(id -u)" -eq 0 ]]; then
  die "Run this script as your normal user; setup.sh invokes sudo where needed."
fi

cd "$(dirname "$0")"
[[ -f "$ENV_FILE" ]] || die "Missing .env. Run: cp .env.example .env"

if [[ "${1:-}" == "--previous" ]]; then
  [[ $# -eq 1 ]] || die "Usage: $0 --previous"
  [[ -f "$BACKUP_FILE" ]] || die "No previous configuration is available"

  current_tmp="$(mktemp)"
  trap 'rm -f "$current_tmp"' EXIT
  cp "$ENV_FILE" "$current_tmp"
  cp "$BACKUP_FILE" "$ENV_FILE"
  cp "$current_tmp" "$BACKUP_FILE"
  rm -f "$current_tmp"
  trap - EXIT

  echo "Restoring the previous model configuration..."
  ./setup.sh
  exit 0
fi

[[ $# -eq 1 ]] || die "Usage: $0 OWNER/REPOSITORY:QUANTIZATION"
readonly NEW_MODEL="$1"

[[ "$NEW_MODEL" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$ ]] ||
  die "Model must use the Hugging Face form OWNER/REPOSITORY:QUANTIZATION"

set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a

if [[ "${LLAMA_MODEL:-}" == "$NEW_MODEL" ]]; then
  echo "Already configured for ${NEW_MODEL}"
  exec ./status.sh
fi

cp "$ENV_FILE" "$BACKUP_FILE"
sed -i '' "s|^LLAMA_MODEL=.*$|LLAMA_MODEL=${NEW_MODEL}|" "$ENV_FILE"

echo "Switching from ${LLAMA_MODEL:-unknown} to ${NEW_MODEL}..."
if ! ./setup.sh; then
  echo "The candidate did not become healthy; restoring the previous configuration..." >&2
  cp "$BACKUP_FILE" "$ENV_FILE"
  if ./setup.sh; then
    echo "Previous model restored." >&2
  else
    echo "Automatic restoration also failed. Inspect the logs and .env.before-model-switch." >&2
  fi
  exit 1
fi

echo
echo "Model switch complete. The client-facing alias remains ${LLAMA_MODEL_ALIAS:-home-llama}."
echo "To swap the current and previous configurations, run: ./switch-model.sh --previous"
