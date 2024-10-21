#!/bin/bash

set -xe

ASSETS="$(pwd)/assets"

IMAGES="assets/images"
SOUNDS="assets/sounds"
FONTS="assets/fonts"

rm -rf zig-out/release

zig build -Dstatic-link -Ddo-release

pushd zig-out/release

for DIR in */; do
	echo "$DIR"
	pushd "$DIR"
	pushd "action-deckbuilder"
	mkdir -p $IMAGES
	mkdir -p $SOUNDS
	mkdir -p $FONTS
	cp -r "${ASSETS}/images/" $IMAGES
	cp -r "${ASSETS}/sounds/" $SOUNDS
	cp -r "${ASSETS}/fonts/" $FONTS
	ZIPNAME="${DIR%/}.zip"
	zip -r "$ZIPNAME" *
	popd # arch dir
	popd # release dir
	mv "$DIR/action-deckbuilder/$ZIPNAME" .
done
