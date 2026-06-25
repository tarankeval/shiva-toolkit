#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$PROJECT_DIR"/bin/shiva* "$PROJECT_DIR"/lib/shiva/*.sh \
  "$PROJECT_DIR"/install.sh "$PROJECT_DIR"/tests/*.sh; do
  bash -n "$script"
done

version_output="$(NO_COLOR=1 "$PROJECT_DIR/bin/shiva" --version)"
help_output="$(NO_COLOR=1 "$PROJECT_DIR/bin/shiva" --help)"
grep -q '^Shiva Toolkit v1.0.0$' <<<"$version_output"
grep -q 'Shiva Toolkit v1.0.0 (Stable)' <<<"$help_output"
NO_COLOR=1 "$PROJECT_DIR/bin/shiva-doctor" >/dev/null || [[ $? -eq 2 ]]
bash "$PROJECT_DIR/tests/health-vpn.sh"
bash "$PROJECT_DIR/tests/profiles.sh"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
install_output="$(DESTDIR="$stage" "$PROJECT_DIR/install.sh")"
grep -q 'Shiva Toolkit v1.0.0 Stable installed' <<<"$install_output"
test -x "$stage/usr/local/bin/shiva"
test -r "$stage/usr/local/lib/shiva/common.sh"
test -r "$stage/usr/local/lib/shiva/profiles/shiva-server.conf"
grep -q '^CHECK_DOCKER=false$' \
  "$stage/usr/local/lib/shiva/profiles/shiva-server.conf"
test -r "$stage/usr/local/lib/shiva/profiles/shiva-vpn.conf"
test -r "$stage/usr/local/lib/shiva/profiles/ananda.conf"
test -d "$stage/etc/shiva/profiles"
test -r "$stage/etc/shiva/shiva.conf"

printf 'Smoke tests passed.\n'
