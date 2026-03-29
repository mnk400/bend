#!/bin/bash
# install.sh — Created by Manik
set -euo pipefail

REPO="mnk400/bend"
INSTALL_DIR="/usr/local/bin"

echo "Fetching latest version..."
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": *"//;s/".*//')

if [[ -z "$TAG" ]]; then
    echo "Error: could not determine latest version"
    exit 1
fi

VERSION="${TAG#v}"
ARCHIVE="bend-${VERSION}-aarch64-macos.tar.gz"
ARCHIVE_URL="https://github.com/$REPO/releases/download/$TAG/$ARCHIVE"

echo "Installing bend $VERSION..."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$ARCHIVE_URL" -o "$TMP/bend.tar.gz"
tar -xzf "$TMP/bend.tar.gz" -C "$TMP"

if [[ -w "$INSTALL_DIR" ]]; then
    cp "$TMP/bend" "$INSTALL_DIR/bend"
    chmod +x "$INSTALL_DIR/bend"
else
    echo "Need sudo to install to $INSTALL_DIR"
    sudo cp "$TMP/bend" "$INSTALL_DIR/bend"
    sudo chmod +x "$INSTALL_DIR/bend"
fi

echo "Installed bend $VERSION to $INSTALL_DIR/bend"
