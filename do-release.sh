#!/bin/bash

set -xe

ASSETS="$(pwd)/assets"
VERSION="v0.10.0-spikes"

rm -rf zig-out/release

zig build -Dstatic-link -Ddo-release

pushd zig-out/release

for DIR in */; do
	echo "$DIR"
	pushd "$DIR"
	pushd "action-deckbuilder"
	rsync -av --exclude='*tilemaps.tiled-*' $ASSETS .
	cp ../../../../CHANGELOG.md .
	ZIPNAME="wizardboi-${DIR%/}-${VERSION}.zip"
	zip -r "$ZIPNAME" *
	popd # arch dir
	popd # release dir
	mv "$DIR/action-deckbuilder/$ZIPNAME" .
done
