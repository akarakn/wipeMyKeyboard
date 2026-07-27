#!/bin/bash
set -e

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

APP_NAME="wipeMyKeyboard"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"

rm -rf "${APP_DIR}"

mkdir -p "${MACOS_DIR}"
mkdir -p "${HELPERS_DIR}"
mkdir -p "${CONTENTS_DIR}/Resources"

echo "Compiling Swift files..."
swiftc src/CLIControlProtocol.swift src/KeyboardLocker.swift src/ContentView.swift src/wipeMyKeyboardApp.swift -o "${MACOS_DIR}/${APP_NAME}"

echo "Compiling CLI helper..."
swiftc src/CLIControlProtocol.swift cli/wipemykeyboard.swift -o "${HELPERS_DIR}/wipemykeyboard"

if [ -f "assets/AppIcon.icns" ]; then
    echo "Adding AppIcon.icns..."
    cp "assets/AppIcon.icns" "${CONTENTS_DIR}/Resources/"
fi

echo "Adding zsh completion..."
cp "completions/_wipemykeyboard" "${CONTENTS_DIR}/Resources/"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc code sign the application so macOS recognizes its identity
echo "Code signing..."
codesign --force --deep --sign - "${APP_DIR}"

echo "Done!"
