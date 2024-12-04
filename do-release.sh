#!/bin/bash

set -xe

ASSETS="$(pwd)/assets"
VERSION="v0.8-crispin-crystal"

rm -rf zig-out/release

zig build -Dstatic-link -Ddo-release

pushd zig-out/release

for DIR in */; do
	echo "$DIR"
	pushd "$DIR"
	pushd "action-deckbuilder"
	rsync -av --exclude='*tilemaps.tiled-*' $ASSETS .
	ZIPNAME="wizardboi-${DIR%/}-${VERSION}.zip"
	zip -r "$ZIPNAME" *
	popd # arch dir
	popd # release dir
	mv "$DIR/action-deckbuilder/$ZIPNAME" .
done
