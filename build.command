#!/bin/bash
# ---------------------------------------------------------------
#  RsyncBackup Desktop – Ein-Klick-Build
#  Doppelklick auf diese Datei baut die App "RsyncBackupDesktop.app"
#  und legt sie in diesem Ordner ab.
# ---------------------------------------------------------------
set -e
cd "$(dirname "$0")"

APP_NAME="RsyncBackupDesktop"
BUNDLE_ID="com.jens.rsyncbackupdesktop"
APP_DIR="${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "==> Prüfe Swift-Compiler …"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "FEHLER: 'swiftc' nicht gefunden."
  echo "Bitte zuerst die Command Line Tools installieren:"
  echo "    xcode-select --install"
  read -p "Drücke Enter zum Schließen."
  exit 1
fi

echo "==> Räume alten Build auf …"
rm -rf "${APP_DIR}" AppIcon.iconset AppIcon.icns
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

echo "==> Baue App-Icon aus AppIconSource/AppIcon.iconset …"
cp -R AppIconSource/AppIcon.iconset AppIcon.iconset
iconutil -c icns AppIcon.iconset -o AppIcon.icns
cp AppIcon.icns "${RES_DIR}/AppIcon.icns"
rm -rf AppIcon.iconset AppIcon.icns

echo "==> Kompiliere …"
swiftc -O -parse-as-library \
  Sources/RsyncBackupApp.swift \
  -o "${MACOS_DIR}/${APP_NAME}" \
  -framework SwiftUI -framework AppKit -framework UserNotifications

echo "==> Schreibe Info.plist …"
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>rsync Backup</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "==> Signiere lokal (ad-hoc) …"
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || \
  echo "   (Signierung übersprungen – App läuft trotzdem.)"

echo ""
echo "FERTIG ✅  ->  ${APP_DIR}"
echo "Du kannst die App jetzt per Doppelklick starten."
echo "Sie erscheint als normales Fenster mit Dock-Icon."
echo ""
read -p "Drücke Enter zum Schließen."
