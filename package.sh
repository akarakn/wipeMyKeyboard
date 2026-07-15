#!/bin/bash
set -e

APP_NAME="wipeMyKeyboard"
APP_DIR="${APP_NAME}.app"
VERSION="1.0"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
ZIP_NAME="${APP_NAME}-v${VERSION}.zip"

if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR not found. Please run ./build.sh first to build the application."
    exit 1
fi

echo "Starting packaging for $APP_NAME..."

echo "Creating $ZIP_NAME..."
rm -f "$ZIP_NAME"
zip -qry "$ZIP_NAME" "$APP_DIR"

echo "Creating $DMG_NAME..."
rm -f "$DMG_NAME"

npx --yes create-dmg --no-code-sign "$APP_DIR" . || true

GENERATED_DMG=$(ls *.dmg | grep -v "$DMG_NAME" | head -n 1 || true)
if [ -n "$GENERATED_DMG" ] && [ "$GENERATED_DMG" != "$DMG_NAME" ]; then
    mv "$GENERATED_DMG" "$DMG_NAME"
fi

echo ""
echo "Done!"
echo "$ZIP_NAME"
echo "$DMG_NAME"
