#!/usr/bin/env bash

# TLS preflight for local Moodle HTTPS.
# Fail closed if a leaf certificate is expired or too close to expiry,
# so compose-up and baseline never advertise a URL browsers will reject.

tls_preflight_min_remaining_seconds() {
  printf '%s\n' "${TLS_PREFLIGHT_MIN_REMAINING_SECONDS:-3600}"
}

tls_preflight_usage() {
  cat <<'EOF'
Check that a TLS leaf certificate is still valid long enough to serve.

Usage:
  tls-preflight.sh --pem FILE
  tls-preflight.sh --url URL
  tls-preflight.sh prune DIR
  tls-preflight.sh --help

Environment:
  TLS_PREFLIGHT_MIN_REMAINING_SECONDS   Minimum remaining lifetime (default: 3600)
EOF
}

tls_preflight_fail() {
  printf 'Error: %s\n' "$1" >&2
  return 1
}

tls_preflight_check_pem() {
  local pem="$1"
  local min_remaining="${2:-$(tls_preflight_min_remaining_seconds)}"
  local not_after=""
  local subject=""

  if [[ ! -f "${pem}" ]]; then
    tls_preflight_fail "certificate file not found: ${pem}"
    return 1
  fi

  if ! openssl x509 -in "${pem}" -noout >/dev/null 2>&1; then
    tls_preflight_fail "not a readable X.509 certificate: ${pem}"
    return 1
  fi

  not_after="$(openssl x509 -in "${pem}" -noout -enddate | sed 's/^notAfter=//')"
  subject="$(openssl x509 -in "${pem}" -noout -subject | sed 's/^subject=//')"

  if ! openssl x509 -in "${pem}" -noout -checkend 0 >/dev/null 2>&1; then
    tls_preflight_fail "TLS certificate expired (notAfter=${not_after})."
    return 1
  fi

  if ! openssl x509 -in "${pem}" -noout -checkend "${min_remaining}" >/dev/null 2>&1; then
    tls_preflight_fail "TLS certificate expires too soon (notAfter=${not_after}; required remaining ${min_remaining}s)."
    return 1
  fi

  printf 'TLS certificate is valid (subject=%s; notAfter=%s).\n' "${subject}" "${not_after}"
}

tls_preflight_parse_https_url() {
  local url="$1"

  command -v python3 >/dev/null 2>&1 || {
    tls_preflight_fail "python3 is required to parse --url"
    return 1
  }

  python3 - "${url}" <<'PY'
from urllib.parse import urlparse
import sys

url = sys.argv[1]
parsed = urlparse(url)
if parsed.scheme != "https" or not parsed.hostname:
    sys.exit(2)
port = parsed.port or 443
print(parsed.hostname)
print(port)
PY
}

tls_preflight_fetch_peer_pem() {
  local host="$1"
  local port="$2"
  local servername="${3:-${host}}"

  command -v python3 >/dev/null 2>&1 || {
    tls_preflight_fail "python3 is required to fetch a peer certificate"
    return 1
  }

  python3 - "${host}" "${port}" "${servername}" <<'PY'
import socket
import ssl
import sys

host, port, servername = sys.argv[1], int(sys.argv[2]), sys.argv[3]
context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE
try:
    with socket.create_connection((host, port), timeout=5) as sock:
        with context.wrap_socket(sock, server_hostname=servername) as tls:
            der = tls.getpeercert(binary_form=True)
except OSError as exc:
    print(f"could not complete TLS handshake with {host}:{port}: {exc}", file=sys.stderr)
    sys.exit(1)

if not der:
    print(f"peer at {host}:{port} presented no certificate", file=sys.stderr)
    sys.exit(1)

sys.stdout.write(ssl.DER_cert_to_PEM_cert(der))
PY
}

tls_preflight_check_url() {
  local url="$1"
  local parsed=""
  local host=""
  local port=""
  local pem=""
  local status=0

  parsed="$(tls_preflight_parse_https_url "${url}")" || {
    tls_preflight_fail "URL must be https://host[:port]/; got ${url}"
    return 1
  }
  host="$(printf '%s\n' "${parsed}" | sed -n '1p')"
  port="$(printf '%s\n' "${parsed}" | sed -n '2p')"

  pem="$(mktemp "${TMPDIR:-/tmp}/tls-preflight-XXXX.pem")"
  if ! tls_preflight_fetch_peer_pem "${host}" "${port}" "${host}" >"${pem}"; then
    rm -f "${pem}"
    return 1
  fi

  tls_preflight_check_pem "${pem}" || status=$?
  rm -f "${pem}"
  return "${status}"
}

tls_preflight_wait_for_https() {
  local url="$1"
  local attempts="${2:-90}"

  command -v curl >/dev/null 2>&1 || {
    tls_preflight_fail "curl is required to wait for HTTPS"
    return 1
  }

  while (( attempts > 0 )); do
    if curl -kfsS --max-time 3 -o /dev/null "${url}" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 1
  done

  tls_preflight_fail "${url} did not start serving HTTPS in time."
  return 1
}

tls_preflight_prune_expired_certs() {
  local cert_root="${1:-/data/caddy/certificates}"
  local crt=""
  local dir=""

  [[ -d "${cert_root}" ]] || return 0

  command -v openssl >/dev/null 2>&1 || {
    tls_preflight_fail "openssl is required to prune expired certificates"
    return 1
  }

  while IFS= read -r -d '' crt; do
    if openssl x509 -in "${crt}" -noout -checkend 0 >/dev/null 2>&1; then
      continue
    fi
    dir="$(dirname "${crt}")"
    printf 'removing expired certificate directory %s\n' "${dir}"
    rm -rf "${dir}"
  done < <(find "${cert_root}" -type f -name '*.crt' -print0 2>/dev/null)
}

tls_preflight_main() {
  case "${1:-}" in
    -h|--help)
      tls_preflight_usage
      return 0
      ;;
    --pem)
      [[ -n "${2:-}" ]] || {
        tls_preflight_usage >&2
        return 1
      }
      tls_preflight_check_pem "$2"
      ;;
    --url)
      [[ -n "${2:-}" ]] || {
        tls_preflight_usage >&2
        return 1
      }
      tls_preflight_check_url "$2"
      ;;
    prune)
      tls_preflight_prune_expired_certs "${2:-}"
      ;;
    *)
      tls_preflight_usage >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  tls_preflight_main "$@"
fi
