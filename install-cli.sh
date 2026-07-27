#!/bin/bash
set -e

APP_PATH="${1:-/Applications/wipeMyKeyboard.app}"
CLI_SOURCE="${APP_PATH}/Contents/Helpers/wipemykeyboard"
INSTALL_DIR="${CLI_INSTALL_DIR:-/usr/local/bin}"
CLI_DESTINATION="${INSTALL_DIR}/wipemykeyboard"

if [ ! -x "${CLI_SOURCE}" ]; then
    echo "Error: CLI executable not found at ${CLI_SOURCE}"
    echo "Build the app first or pass the installed app path as the first argument."
    exit 1
fi

if [ ! -d "${INSTALL_DIR}" ]; then
    echo "Error: ${INSTALL_DIR} does not exist."
    exit 1
fi

if [ ! -w "${INSTALL_DIR}" ]; then
    echo "Error: ${INSTALL_DIR} is not writable."
    echo "Run this installer with sudo, but run wipemykeyboard as your normal user."
    exit 1
fi

ln -sfn "${CLI_SOURCE}" "${CLI_DESTINATION}"

echo "Installed ${CLI_DESTINATION}"
echo "Try: wipemykeyboard --status"
