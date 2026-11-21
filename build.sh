#!/bin/sh
# Runs on the GitHub runner only (nothing compiles on the Mac). SIGN=- there; the Mac re-signs "Mantra Apps" after the download.
set -e
cd "$(dirname "$0")"
mkdir -p build
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
NAME="LAN Scanner (Mantra)"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -o "$APP/Contents/MacOS/$NAME" app/*.swift \
  -framework AppKit -framework SwiftUI -framework CoreWLAN -framework Network
cp Info.plist "$APP/Contents/Info.plist"
sed -i '' "s/<string>1<\/string>/<string>$V<\/string>/g" "$APP/Contents/Info.plist"
# the icon: six letters over one picture (icon/six_1024.png, made by STAR_SWIFT/icons6)
if [ -f icon/six_1024.png ]; then
  I=build/AppIcon.iconset; rm -rf "$I"; mkdir -p "$I"
  for p in 16 32 64 128 256 512 1024; do sips -z $p $p icon/six_1024.png --out "$I/s$p.png" >/dev/null; done
  cp "$I/s16.png" "$I/icon_16x16.png"; cp "$I/s32.png" "$I/icon_16x16@2x.png"; cp "$I/s32.png" "$I/icon_32x32.png"
  cp "$I/s64.png" "$I/icon_32x32@2x.png"; cp "$I/s128.png" "$I/icon_128x128.png"; cp "$I/s256.png" "$I/icon_128x128@2x.png"
  cp "$I/s256.png" "$I/icon_256x256.png"; cp "$I/s512.png" "$I/icon_256x256@2x.png"; cp "$I/s512.png" "$I/icon_512x512.png"
  cp "$I/s1024.png" "$I/icon_512x512@2x.png"; rm "$I"/s*.png
  iconutil -c icns "$I" -o "$APP/Contents/Resources/AppIcon.icns"
fi
# the maker table made by tools/make_oui.py (absent when the download failed; the app has a small fallback)
[ -f build/oui.tsv ] && cp build/oui.tsv "$APP/Contents/Resources/oui.tsv" || echo "no oui.tsv: the app uses its fallback table"
codesign --force -s "${SIGN:-Mantra Apps}" "$APP"
echo "built $APP (v$V)"
