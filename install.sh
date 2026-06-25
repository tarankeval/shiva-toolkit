#!/usr/bin/env bash
set -euo pipefail

SHIVA_VERSION="1.0.0"
PREFIX="${PREFIX:-/usr/local}"
SYSCONFDIR="${SYSCONFDIR:-/etc}"
ROOT="${DESTDIR:-}"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if (( EUID != 0 )) && [[ -z "$ROOT" ]]; then
  printf 'Installation into %s requires root. Run: sudo ./install.sh\n' "$PREFIX" >&2
  exit 1
fi

install -d "$ROOT$PREFIX/bin" "$ROOT$PREFIX/lib/shiva/profiles" \
  "$ROOT$SYSCONFDIR/shiva/profiles"
install -m 0755 "$PROJECT_DIR"/bin/shiva* "$ROOT$PREFIX/bin/"
install -m 0644 "$PROJECT_DIR"/lib/shiva/*.sh "$ROOT$PREFIX/lib/shiva/"
install -m 0644 "$PROJECT_DIR"/lib/shiva/profiles/*.conf \
  "$ROOT$PREFIX/lib/shiva/profiles/"

if [[ ! -e "$ROOT$SYSCONFDIR/shiva/shiva.conf" ]]; then
  install -m 0644 "$PROJECT_DIR/config/shiva.conf.example" \
    "$ROOT$SYSCONFDIR/shiva/shiva.conf"
fi

printf 'Shiva Toolkit v%s Stable installed in %s\n' "$SHIVA_VERSION" "$ROOT$PREFIX"
