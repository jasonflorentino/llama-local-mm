#!/usr/bin/env bash
set -euo pipefail

readonly CONFIG_FILE="${HOME_LLAMA_CONFIG:-/usr/local/etc/home-llama.env}"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Configuration file is not readable: $CONFIG_FILE" >&2
  exit 1
fi

# The installed configuration is generated from the repository's .env file by
# setup.sh and is private to the service user.
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

: "${LLAMA_SERVER_BIN:?LLAMA_SERVER_BIN is required}"
: "${LLAMA_MODEL:?LLAMA_MODEL is required}"
: "${LLAMA_MODEL_ALIAS:?LLAMA_MODEL_ALIAS is required}"
: "${LLAMA_WEBUI_CONFIG_FILE:?LLAMA_WEBUI_CONFIG_FILE is required}"
: "${LLAMA_PORT:?LLAMA_PORT is required}"
: "${LLAMA_CTX_SIZE:?LLAMA_CTX_SIZE is required}"
: "${LLAMA_PARALLEL:?LLAMA_PARALLEL is required}"

if [[ ! -r "$LLAMA_WEBUI_CONFIG_FILE" ]]; then
  echo "Web UI configuration file is not readable: $LLAMA_WEBUI_CONFIG_FILE" >&2
  exit 1
fi

args=(
  "$LLAMA_SERVER_BIN"
  --hf-repo "$LLAMA_MODEL"
  --alias "$LLAMA_MODEL_ALIAS"
  --ui-config-file "$LLAMA_WEBUI_CONFIG_FILE"
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

if [[ -n "${LLAMA_THREADS_BATCH:-}" ]]; then
  args+=(--threads-batch "$LLAMA_THREADS_BATCH")
fi

if [[ -n "${LLAMA_CACHE_RAM:-}" ]]; then
  args+=(--cache-ram "$LLAMA_CACHE_RAM")
fi

if [[ -n "${LLAMA_CORS_ORIGINS:-}" ]]; then
  args+=(--cors-origins "$LLAMA_CORS_ORIGINS")
fi

if [[ -n "${LLAMA_GPU_LAYERS:-}" ]]; then
  args+=(--n-gpu-layers "$LLAMA_GPU_LAYERS")
fi

if [[ -n "${LLAMA_API_KEY:-}" ]]; then
  args+=(--api-key "$LLAMA_API_KEY")
fi

exec "${args[@]}"
