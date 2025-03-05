#!/bin/bash

set -xe

ASSETS="$(pwd)/assets"
VERSION="v0.12.1-fixes"
REPO_DIR=$(realpath)
RELEASE_REL_DIR="zig-out/release"

rm -rf "$RELEASE_REL_DIR"
zig build -Dstatic-link -Ddo-release

RELEASE_DIR=$(realpath "$RELEASE_REL_DIR")

make_app_bundle() {
	local EXE_DIR="$1"
	local APP_DIR="Dungeon Wizard.app"
	pushd "$EXE_DIR"
	cp -R "$REPO_DIR/app-bundle" "$APP_DIR"
	rsync -av --exclude='*tilemaps.tiled-*' --exclude='.DS_Store' $ASSETS "$APP_DIR/Contents/Resources"
	cp "Dungeon Wizard" "$APP_DIR/Contents/MacOS"
	popd
	mv "$EXE_DIR/$APP_DIR" "$RELEASE_DIR"
}

make_zip() {
	local EXE_DIR="$1"
	pushd "$EXE_DIR"
	rsync -av --exclude='*tilemaps.tiled-*' --exclude='.DS_Store' $ASSETS .
	cp "$REPO_DIR/CHANGELOG.md" .
	ZIPNAME="DungeonWizard-${DIR%/}-${VERSION}.zip"
	zip -r "$ZIPNAME" *
	popd
	mv "$EXE_DIR/$ZIPNAME" "$RELEASE_DIR"
}

pushd "$RELEASE_DIR"

for DIR in */; do
	DDIR="$DIR/Dungeon Wizard"
	REAL_DDIR=$(realpath "$DDIR")
	echo "$DIR"
	if echo "$DIR" | grep -q "macos"; then
		make_app_bundle "$REAL_DDIR"
	elif echo "$DIR" | grep -q "windows"; then
		make_zip "$REAL_DDIR"
	else
		echo "Nothing to do?"
	fi
done
