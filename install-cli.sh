#!/bin/bash
set -e

APP_PATH="${1:-/Applications/wipeMyKeyboard.app}"
CLI_SOURCE="${APP_PATH}/Contents/Helpers/wipemykeyboard"
INSTALL_DIR="${CLI_INSTALL_DIR:-/usr/local/bin}"
CLI_DESTINATION="${INSTALL_DIR}/wipemykeyboard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_COMPLETION_SOURCE="${APP_PATH}/Contents/Resources/_wipemykeyboard"
REPOSITORY_COMPLETION_SOURCE="${SCRIPT_DIR}/completions/_wipemykeyboard"

if [ -n "${ZSH_COMPLETION_INSTALL_DIR:-}" ]; then
    COMPLETION_INSTALL_DIR="${ZSH_COMPLETION_INSTALL_DIR}"
elif [[ "${INSTALL_DIR}" == /opt/homebrew/* ]]; then
    COMPLETION_INSTALL_DIR="/opt/homebrew/share/zsh/site-functions"
else
    COMPLETION_INSTALL_DIR="/usr/local/share/zsh/site-functions"
fi

COMPLETION_DESTINATION="${COMPLETION_INSTALL_DIR}/_wipemykeyboard"

if [ -f "${BUNDLED_COMPLETION_SOURCE}" ]; then
    COMPLETION_SOURCE="${BUNDLED_COMPLETION_SOURCE}"
elif [ -f "${REPOSITORY_COMPLETION_SOURCE}" ]; then
    COMPLETION_SOURCE="${REPOSITORY_COMPLETION_SOURCE}"
else
    echo "Error: zsh completion file not found."
    echo "Build the app again or run this installer from the repository."
    exit 1
fi

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

if [ ! -d "${COMPLETION_INSTALL_DIR}" ]; then
    mkdir -p "${COMPLETION_INSTALL_DIR}"
fi

if [ ! -w "${COMPLETION_INSTALL_DIR}" ]; then
    echo "Error: ${COMPLETION_INSTALL_DIR} is not writable."
    echo "Run this installer with sudo."
    exit 1
fi

ln -sfn "${CLI_SOURCE}" "${CLI_DESTINATION}"
install -m 0644 "${COMPLETION_SOURCE}" "${COMPLETION_DESTINATION}"

echo "Installed ${CLI_DESTINATION}"
echo "Installed ${COMPLETION_DESTINATION}"
echo "Open a new terminal or run: autoload -Uz compinit && compinit"
echo "Try: wipemykeyboard --status"
