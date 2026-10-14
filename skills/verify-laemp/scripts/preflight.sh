#!/usr/bin/env bash
set -euo pipefail

os_name="$(uname -s)"
if [ "$os_name" != "Linux" ]; then
  printf 'BLOCKED: LAEMP provisioning supports only Ubuntu/Debian Linux; detected %s.\n' "$os_name"
  exit 2
fi

os_release="/etc/os-release"
if [ ! -r "$os_release" ]; then
  printf 'BLOCKED: %s is unavailable; cannot verify the supported distribution.\n' "$os_release"
  exit 2
fi

distribution="$(sed -n 's/^ID=//p' "$os_release" | head -n 1 | tr -d '"')"
case "$distribution" in
  ubuntu|debian) printf 'SUPPORTED: %s\n' "$distribution" ;;
  *) printf 'BLOCKED: LAEMP supports Ubuntu/Debian; detected %s.\n' "${distribution:-unknown}"; exit 2 ;;
esac
