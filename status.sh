#!/usr/bin/env bash
set -euo pipefail

readonly SERVICE_LABEL="com.home-llama.server"

cd "$(dirname "$0")"
[[ -f .env ]] || {
  echo "Missing .env" >&2
  exit 1
}

set -a
# shellcheck disable=SC1091
source .env
set +a

echo "launchd service:"
sudo launchctl print "system/${SERVICE_LABEL}" |
  awk '/state =|pid =|last exit code =/{print "  " $0}'

echo
echo "llama-server health:"
curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health"
echo

echo
echo "configured model: ${LLAMA_MODEL}"
echo "stable API alias: ${LLAMA_MODEL_ALIAS:-home-llama}"
echo "advertised model:"
curl -fsS "http://127.0.0.1:${LLAMA_PORT}/v1/models"
echo

echo
echo "nginx health:"
curl -fsS -H "Host: ${SERVER_NAME}" \
  "http://127.0.0.1:${LISTEN_PORT}/healthz"
echo
