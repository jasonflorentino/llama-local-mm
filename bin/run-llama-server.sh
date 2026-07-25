#!/usr/bin/env bash
set -euo pipefail

readonly CONFIG_FILE="${HOME_LLAMA_CONFIG:-/usr/local/etc/home-llama.env}"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration file is not readable: $CONFIG_FILE" >&2
  exit 1
fi

# The installed configuration is root-owned and is created from the repository's
# .env file by setup.sh.
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

: "${LLAMA_SERVER_BIN:?LLAMA_SERVER_BIN is required}"
: "${LLAMA_MODEL:?LLAMA_MODEL is required}"
: "${LLAMA_PORT:?LLAMA_PORT is required}"
: "${LLAMA_CTX_SIZE:?LLAMA_CTX_SIZE is required}"
: "${LLAMA_PARALLEL:?LLAMA_PARALLEL is required}"

args=(
  "$LLAMA_SERVER_BIN"
  --hf "$LLAMA_MODEL"
  --host 127.0.0.1
  --port "$LLAMA_PORT"
  --ctx-size "$LLAMA_CTX_SIZE"
  --parallel "$LLAMA_PARALLEL"
)

if [[ -n "${LLAMA_DEVICE:-}" ]]; then
  args+=(--device "$LLAMA_DEVICE")
fi

if [[ -n "${LLAMA_THREADS:-}" ]]; then
  args+=(--threads "$LLAMA_THREADS")
fi

if [[ -n "${LLAMA_GPU_LAYERS:-}" ]]; then
  args+=(--n-gpu-layers "$LLAMA_GPU_LAYERS")
fi

if [[ -n "${LLAMA_API_KEY:-}" ]]; then
  args+=(--api-key "$LLAMA_API_KEY")
fi

exec "${args[@]}"
