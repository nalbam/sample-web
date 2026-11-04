#!/usr/bin/env bash
#
# Smoke test for the sample-web image. CI and Jenkins run it after the build.
#
#   scripts/smoke.sh IMAGE [VERSION]
#
# Starts IMAGE with VERSION and checks it from a curl container in the same
# network namespace, so the host needs only docker and jq. Exits non-zero and
# prints the container log when a check fails.

set -euo pipefail

IMAGE="${1:?usage: scripts/smoke.sh IMAGE [VERSION]}"
VERSION="${2:-v0.0.0-smoke}"
PORT=8080
TIMEOUT="${SMOKE_TIMEOUT:-60}"
CURL_IMAGE=curlimages/curl:8.23.0
NAME="smoke-$$-$RANDOM"

cleanup() { docker rm -f "$NAME" > /dev/null 2>&1 || true; }
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs "$NAME" >&2 || true
  exit 1
}

# http CURL_ARGS... runs curl inside the network namespace of the container.
http() { docker run --rm --network "container:$NAME" "$CURL_IMAGE" -fsS --max-time 10 "$@"; }

# start [DOCKER_RUN_ARGS...] starts the image and waits for GET /health.
start() {
  cleanup
  docker run -d --name "$NAME" -e VERSION="$VERSION" "$@" "$IMAGE" > /dev/null
  for _ in $(seq "$TIMEOUT"); do
    [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = true ] || fail "container exited"
    http -o /dev/null "http://localhost:$PORT/health" 2> /dev/null && return 0
    sleep 1
  done
  fail "GET /health did not answer in ${TIMEOUT}s"
}

# check_health checks the /health contract: HTTP 200 with result "ok" and VERSION.
check_health() {
  local body
  body="$(http "http://localhost:$PORT/health")" || fail "GET /health"
  jq -e --arg version "$VERSION" '.result == "ok" and .version == $version' <<< "$body" > /dev/null ||
    fail "GET /health returned $body, expected result ok and version $VERSION"
  echo "ok: GET /health $body"
}

# check_get PATH [TEXT] checks HTTP 200 and, when given, that the body contains TEXT.
check_get() {
  if [ -z "${2:-}" ]; then
    http -o /dev/null "http://localhost:$PORT$1" || fail "GET $1"
  else
    http "http://localhost:$PORT$1" | grep -F -- "$2" > /dev/null || fail "GET $1 does not contain '$2'"
  fi
  echo "ok: GET $1"
}

# --- sample-web checks -------------------------------------------------------

start --cap-drop ALL
check_health
check_get / '<title>Hello, world!</title>'
check_get /favicon.ico
if http -o /dev/null "http://localhost:$PORT/does-not-exist" 2> /dev/null; then
  fail "GET /does-not-exist did not return an error"
fi
echo "ok: GET /does-not-exist returns an error"

[ "$(docker exec "$NAME" id -u)" != 0 ] || fail "the container runs as root"
echo "ok: runs as uid $(docker exec "$NAME" id -u)"

PORT=18080
start -e PORT="$PORT"
check_health

echo "smoke test passed: $IMAGE $VERSION"
