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
echo "nginx health:"
curl -fsS -H "Host: ${SERVER_NAME}" \
  "http://127.0.0.1:${LISTEN_PORT}/healthz"
echo
