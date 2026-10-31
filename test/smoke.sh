#!/usr/bin/env bash
#
# HTTP smoke test for a running sample-web server.
#
# Usage: test/smoke.sh [BASE_URL]   (default: http://localhost:8080)
#
# Checks that /, /index.html and /favicon.ico are served from src/, that the
# page keeps its content and Bootstrap 5 / Font Awesome 7 markup, and that every
# pinned CDN asset downloads and matches its integrity hash. The remote
# counter.js is a known external dependency outside this repository: its status
# is reported but does not fail the test.

set -euo pipefail

base="${1:-http://localhost:8080}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

counter_js="https://nalbam.com/static/sample/counter.js"
failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# Wait up to 15 seconds for the server.
for _ in $(seq 1 15); do
  curl -fsS -o /dev/null "$base/" 2>/dev/null && break
  sleep 1
done

# Each path must return 200 with the expected type and the file from src/.
check_path() {
  local path="$1" file="$2" type="$3" out="$tmp/body" code ctype
  if ! read -r code ctype < <(curl -sS -o "$out" -w '%{http_code} %{content_type}\n' "$base$path"); then
    fail "$path: request failed"
    return
  fi
  [ "$code" = "200" ] || { fail "$path: HTTP $code"; return; }
  [[ "$ctype" == "$type"* ]] || fail "$path: Content-Type '$ctype', expected '$type'"
  cmp -s "$out" "$root/src/$file" || fail "$path: body differs from src/$file"
  echo "ok: $path HTTP $code $ctype"
}

check_path / index.html text/html
check_path /index.html index.html text/html
check_path /favicon.ico favicon.ico image/x-icon

html="$(tr '\n' ' ' < "$root/src/index.html")"

# Content and markup that the page must keep.
for want in \
  '<title>Hello, world!</title>' \
  'src="https://nalbam.com/static/logo/nginx.png"' \
  'id="host">sample-web<' \
  'class="btn btn-primary btn-thumbs-up"><i class="fa-regular fa-thumbs-up"></i>' \
  'class="btn btn-danger btn-thumbs-down"><i class="fa-regular fa-thumbs-down"></i>' \
  'id="thumbs-up-count">0<' \
  'id="thumbs-down-count">0<' \
  "src=\"$counter_js\""; do
  grep -qF -- "$want" <<<"$html" || fail "index.html: missing $want"
done

# Markup removed by the Bootstrap 5 / Font Awesome 7 migration.
for legacy in 'jumbotron' 'class="far ' 'bootstrap/4.' 'stackpath.bootstrapcdn.com' 'releases/v5.'; do
  if grep -qF -- "$legacy" <<<"$html"; then fail "index.html: legacy markup $legacy"; fi
done

# Every external stylesheet and script except counter.js must be pinned with
# integrity, download with HTTP 200 and match that hash.
assets=0
while read -r tag; do
  url="$(sed -nE 's/.*(href|src)="(https:[^"]*)".*/\2/p' <<<"$tag")"
  [ -n "$url" ] || continue
  if [ "$url" = "$counter_js" ]; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)"
    echo "known external constraint: $url HTTP $code (not a test failure)"
    continue
  fi
  assets=$((assets + 1))
  integrity="$(sed -nE 's/.*integrity="([^"]*)".*/\1/p' <<<"$tag")"
  [[ "$integrity" =~ ^sha(256|384|512)- ]] || { fail "$url: missing integrity"; continue; }
  grep -qF 'crossorigin="anonymous"' <<<"$tag" || fail "$url: missing crossorigin=\"anonymous\""
  if ! curl -fsSL --retry 3 -o "$tmp/asset" "$url"; then
    fail "$url: download failed"
    continue
  fi
  algo="${integrity%%-*}"
  actual="$algo-$(openssl dgst "-$algo" -binary "$tmp/asset" | openssl base64 -A)"
  if [ "$actual" = "$integrity" ]; then
    echo "ok: $url $integrity"
  else
    fail "$url: integrity $actual, expected $integrity"
  fi
done < <(grep -oE '<(link|script)[^>]*>' <<<"$html")

[ "$assets" -ge 3 ] || fail "expected at least 3 pinned CDN assets, found $assets"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
