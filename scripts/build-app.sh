#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="MeuCleaner"
VERSION="1.4.0"
BUILD_NUMBER="7"
BUILD_DIR="$(pwd)/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [[ ! -f "Resources/AppIcon.icns" ]]; then
    echo "🎨 Gerando ícone AppIcon.icns..."
    swift scripts/generate-icon.swift
fi

echo "🔨 Compilando ${APP_NAME} (Release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.vagner.${APP_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

touch "${APP_BUNDLE}"

echo "🔏 Assinando bundle (${APP_NAME})..."
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
rm -f "${ZIP_PATH}" "${DMG_PATH}"

echo "📦 Gerando pacotes de release (${VERSION})..."
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "${APP_BUNDLE}" -ov -format UDZO "${DMG_PATH}" >/dev/null

echo "✅ Bundle criado com ícone em: ${APP_BUNDLE}"
echo "✅ Pacotes gerados: ${ZIP_PATH} e ${DMG_PATH}"
echo "Para abrir: open \"${APP_BUNDLE}\""
