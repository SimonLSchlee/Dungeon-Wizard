#!/bin/bash

set -xe

ASSETS="$(pwd)/assets"
VERSION="v0.12.1-fixes"

rm -rf zig-out/release

zig build -Dstatic-link -Ddo-release

pushd zig-out/release

for DIR in */; do
	echo "$DIR"
	pushd "$DIR"
	pushd "Dungeon Wizard"
	rsync -av --exclude='*tilemaps.tiled-*' $ASSETS .
	cp ../../../../CHANGELOG.md .
	ZIPNAME="DungeonWizard-${DIR%/}-${VERSION}.zip"
	zip -r "$ZIPNAME" *
	popd # arch dir
	popd # release dir
	mv "$DIR/Dungeon Wizard/$ZIPNAME" .
done
