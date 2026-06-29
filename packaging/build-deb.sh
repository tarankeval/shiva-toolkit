#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="shiva-toolkit"
PACKAGE_VERSION="1.1.0~dev-1"
ARCHITECTURE="all"
BUILD_DIR="$PROJECT_DIR/build/deb"
PACKAGE_ROOT="$BUILD_DIR/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCHITECTURE}"
DEB_PATH="$PROJECT_DIR/dist/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCHITECTURE}.deb"

rm -rf "$BUILD_DIR" "$PROJECT_DIR/dist"
mkdir -p \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/lib/shiva/profiles" \
  "$PACKAGE_ROOT/usr/share/doc/$PACKAGE_NAME" \
  "$PACKAGE_ROOT/lib/systemd/system" \
  "$PACKAGE_ROOT/etc/shiva/profiles" \
  "$PROJECT_DIR/dist"

install -m 0755 "$PROJECT_DIR"/bin/shiva* "$PACKAGE_ROOT/usr/bin/"
install -m 0644 "$PROJECT_DIR"/lib/shiva/*.sh "$PACKAGE_ROOT/usr/lib/shiva/"
install -m 0644 "$PROJECT_DIR"/lib/shiva/profiles/*.conf \
  "$PACKAGE_ROOT/usr/lib/shiva/profiles/"
install -m 0644 "$PROJECT_DIR/config/shiva.conf.example" \
  "$PACKAGE_ROOT/etc/shiva/shiva.conf"
sed 's|@BINDIR@|/usr/bin|g' \
  "$PROJECT_DIR/packaging/systemd/shiva-watchdog.service" \
  > "$PACKAGE_ROOT/lib/systemd/system/shiva-watchdog.service"
chmod 0644 "$PACKAGE_ROOT/lib/systemd/system/shiva-watchdog.service"
install -m 0644 "$PROJECT_DIR/README.md" \
  "$PACKAGE_ROOT/usr/share/doc/$PACKAGE_NAME/README.md"
install -m 0644 "$PROJECT_DIR/debian/copyright" \
  "$PACKAGE_ROOT/usr/share/doc/$PACKAGE_NAME/copyright"
gzip -9c "$PROJECT_DIR/debian/changelog" \
  > "$PACKAGE_ROOT/usr/share/doc/$PACKAGE_NAME/changelog.Debian.gz"

install -m 0644 "$PROJECT_DIR/debian/control" "$PACKAGE_ROOT/DEBIAN/control"
cat >"$PACKAGE_ROOT/DEBIAN/conffiles" <<'EOF'
/etc/shiva/shiva.conf
EOF

find "$PACKAGE_ROOT" -type d -exec chmod 0755 {} +
fakeroot dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$DEB_PATH"

printf '%s\n' "$DEB_PATH"
