#!/bin/sh
#
# Offline runtime test for sample-web.
#
# Usage: sh test/runtime.sh   (run from the repository root inside nginx:1.30-alpine)
#
# Renders nginx/templates with the image's own envsubst entrypoint script and a
# non-default PORT, starts Nginx from nginx/nginx.conf as the unprivileged nginx
# user on that port, and checks /health, the static files from src/ and a 404.
# Uses no network beyond 127.0.0.1 and no secrets.

set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
port="${TEST_PORT:-18080}"
tmp="$(mktemp -d)"
failures=0
pid=""

cleanup() {
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -QUIT "$pid" 2>/dev/null || true
    sleep 1
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

ok() {
  echo "ok: $*"
}

# --- Static checks on the image definition ---------------------------------

grep -q '^FROM nginx:1\.30-alpine' "$root/Dockerfile" || fail "Dockerfile: base image is not nginx:1.30-alpine"
grep -q '^EXPOSE 8080$' "$root/Dockerfile" || fail "Dockerfile: EXPOSE 8080 missing"
grep -q 'PORT=8080' "$root/Dockerfile" || fail "Dockerfile: default PORT=8080 missing"
user="$(sed -n 's/^USER[[:space:]]\{1,\}//p' "$root/Dockerfile" | tail -n 1)"
case "$user" in
  "" | 0 | root | 0:*) fail "Dockerfile: final USER is not non-root ('$user')" ;;
  *) ok "Dockerfile: runs as USER $user" ;;
esac
if grep -Eq '^[[:space:]]*user[[:space:]]' "$root/nginx/nginx.conf"; then
  fail "nginx.conf: 'user' directive needs root"
fi
grep -q 'listen \${PORT};' "$root/nginx/templates/default.conf.template" || fail "template: does not listen on \${PORT}"

# --- Render the config like the image entrypoint does ----------------------

mkdir -p "$tmp/conf.d" "$tmp/html" "$tmp/logs"
cp -R "$root/src/." "$tmp/html/"

envsubst_script=/docker-entrypoint.d/20-envsubst-on-templates.sh
if [ -x "$envsubst_script" ]; then
  PORT="$port" \
  NGINX_ENVSUBST_FILTER='^PORT$' \
  NGINX_ENVSUBST_TEMPLATE_DIR="$root/nginx/templates" \
  NGINX_ENVSUBST_OUTPUT_DIR="$tmp/conf.d" \
    sh "$envsubst_script" >/dev/null
else
  echo "note: $envsubst_script not found, using envsubst directly"
  PORT="$port" envsubst '${PORT}' <"$root/nginx/templates/default.conf.template" >"$tmp/conf.d/default.conf"
fi

conf="$tmp/conf.d/default.conf"
[ -f "$conf" ] || { echo "FAIL: template was not rendered"; exit 1; }
grep -q "listen $port;" "$conf" && ok "rendered listen $port" || fail "rendered config does not listen on $port"
grep -q 'try_files \$uri \$uri/ =404;' "$conf" && ok "nginx variables left intact" || fail "envsubst replaced nginx variables"

# Point the image paths at the temp dir.
sed -i "s#/usr/share/nginx/html#$tmp/html#g" "$conf"
# Replace /tmp/ first so the $tmp paths inserted below are not rewritten again.
sed -e "s#/tmp/#$tmp/#g" \
    -e "s#/etc/nginx/conf.d/#$tmp/conf.d/#g" \
    -e "s#/var/log/nginx/#$tmp/logs/#g" \
    "$root/nginx/nginx.conf" >"$tmp/nginx.conf"

# --- Start Nginx as a non-root user ----------------------------------------

# As root, drop to the nginx user (uid 101) like the image does. If the test
# container lacks the capabilities for that (CAP_SETUID/SETGID/CHOWN), run as
# root in single-process mode with "user root;" in this test-only config, so
# Nginx neither chowns its temp dirs to uid 101 nor calls setgid/setuid.
use_su=0
if [ "$(id -u)" = "0" ]; then
  if su -s /bin/sh nginx -c true 2>/dev/null && chown -R nginx:nginx "$tmp" 2>/dev/null; then
    use_su=1
  else
    echo "note: cannot switch to the nginx user, running as root with 'user root; master_process off;' (test config only)"
    { printf 'user root;\nmaster_process off;\n'; cat "$tmp/nginx.conf"; } >"$tmp/nginx.conf.new"
    mv "$tmp/nginx.conf.new" "$tmp/nginx.conf"
  fi
fi

run() {
  if [ "$use_su" = "1" ]; then
    su -s /bin/sh nginx -c "$*"
  else
    sh -c "$*"
  fi
}

if ! run "nginx -t -q -e '$tmp/logs/error.log' -c '$tmp/nginx.conf'"; then
  echo "FAIL: nginx -t"
  exit 1
fi
ok "nginx -t"

run "nginx -e '$tmp/logs/error.log' -c '$tmp/nginx.conf'"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$tmp/nginx.pid" ] && wget -q -O /dev/null "http://127.0.0.1:$port/health" 2>/dev/null && break
  sleep 1
done
pid="$(cat "$tmp/nginx.pid" 2>/dev/null || true)"
[ -n "$pid" ] || { echo "FAIL: nginx did not start"; cat "$tmp/logs/error.log" 2>/dev/null || true; exit 1; }

master_uid="$(awk '/^Uid:/ { print $2 }' "/proc/$pid/status")"
if [ "$master_uid" != "0" ]; then
  ok "nginx master runs as uid $master_uid"
elif [ "$use_su" = "1" ]; then
  fail "nginx master runs as root"
fi

# --- HTTP checks -------------------------------------------------------------

# fetch PATH -> writes body to $tmp/body, headers to $tmp/headers
fetch() {
  rm -f "$tmp/body" "$tmp/headers"
  wget -S -q -O "$tmp/body" "http://127.0.0.1:$port$1" 2>"$tmp/headers" || true
  status="$(sed -n 's/^ *HTTP\/[0-9.]* \([0-9][0-9][0-9]\).*/\1/p' "$tmp/headers" | tail -n 1)"
  ctype="$(sed -n 's/^ *[Cc]ontent-[Tt]ype: *//p' "$tmp/headers" | tail -n 1 | tr -d '\r')"
}

fetch /health
[ "$status" = "200" ] && ok "/health HTTP 200" || fail "/health HTTP '$status'"
[ "$(cat "$tmp/body" 2>/dev/null)" = "ok" ] || fail "/health body is not 'ok'"
case "$ctype" in text/plain*) ;; *) fail "/health Content-Type '$ctype'" ;; esac

check_path() {
  fetch "$1"
  if [ "$status" != "200" ]; then
    fail "$1: HTTP '$status'"
    return
  fi
  case "$ctype" in "$3"*) ;; *) fail "$1: Content-Type '$ctype', expected '$3'" ;; esac
  cmp -s "$tmp/body" "$root/src/$2" || fail "$1: body differs from src/$2"
  ok "$1 HTTP $status $ctype"
}

check_path / index.html text/html
check_path /index.html index.html text/html
check_path /favicon.ico favicon.ico image/x-icon

grep -qF '<title>Hello, world!</title>' "$root/src/index.html" || fail "index.html: title missing"
grep -qF 'id="host">sample-web<' "$root/src/index.html" || fail "index.html: sample-web heading missing"

fetch /does-not-exist
[ "$status" = "404" ] && ok "/does-not-exist HTTP 404" || fail "/does-not-exist HTTP '$status', expected 404"

if [ "$failures" -gt 0 ]; then
  echo "--- error.log"
  cat "$tmp/logs/error.log" 2>/dev/null || true
  echo "$failures check(s) failed"
  exit 1
fi
echo "all runtime checks passed"
