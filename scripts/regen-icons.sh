#!/bin/bash
#
# Regenerate AppIcon.appiconset PNGs from the Icon Composer source.
#
# Source of truth:  Sources/Writey/Core/Resources/AppIcon.icon
# Compiled output:  Sources/Writey/Core/Resources/Assets.xcassets/AppIcon.appiconset/
#
# Why this script exists: Xcode 26's actool can't yet treat a `.icon`
# bundle as the project's AppIcon source — even though Icon Composer
# produces them — so we render `.icon` to PNGs via `ictool` (the
# Icon Composer CLI bundled with Xcode) and feed those into a
# traditional `.appiconset`. Also handles the iOS-marketing-icon alpha
# requirement: App Store Connect rejects RGBA, so we flatten the 1024
# iOS variant against the icon's background gradient color before
# writing it out.
#
# Run after editing AppIcon.icon, then commit the regenerated PNGs.
#
set -euo pipefail

cd "$(dirname "$0")/.."

ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
SRC=Sources/Writey/Core/Resources/AppIcon.icon
DEST=Sources/Writey/Core/Resources/Assets.xcassets/AppIcon.appiconset

if [ ! -d "$SRC" ]; then
  echo "❌ $SRC not found"; exit 1
fi
if [ ! -x "$ICTOOL" ]; then
  echo "❌ Icon Composer not found at $ICTOOL"; exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

echo "▸ rendering macOS variants (alpha OK)"
for size in 16 32 64 128 256 512 1024; do
  "$ICTOOL" "$SRC" \
    --export-image \
    --output-file "$DEST/icon_${size}.png" \
    --platform macOS \
    --rendition Default \
    --width "$size" --height "$size" --scale 1 \
    > /dev/null
done

echo "▸ rendering iOS 1024 marketing icon"
"$ICTOOL" "$SRC" \
  --export-image \
  --output-file "$DEST/icon_ios_1024.rgba.png" \
  --platform iOS \
  --rendition Default \
  --width 1024 --height 1024 --scale 1 \
  > /dev/null

echo "▸ flattening alpha (App Store Connect rejects RGBA)"
python3 <<'PY'
from PIL import Image
src = "Sources/Writey/Core/Resources/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.rgba.png"
dst = "Sources/Writey/Core/Resources/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png"
img = Image.open(src).convert("RGBA")
# Composite against the gradient start color from AppIcon.icon/icon.json:
# "srgb:0.88593,0.50943,0.22759,1.0" → (226, 130, 58). This means any
# alpha-edge pixel blends into the icon's natural background, which keeps
# the visual identity intact instead of a hard white halo.
bg = Image.new("RGB", img.size, (226, 130, 58))
bg.paste(img, mask=img.split()[3])
bg.save(dst)
PY

rm "$DEST/icon_ios_1024.rgba.png"

echo "▸ writing Contents.json"
cat > "$DEST/Contents.json" <<EOF
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16.png"   },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_32.png"   },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32.png"   },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_64.png"   },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128.png"  },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_256.png"  },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256.png"  },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_512.png"  },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512.png"  },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_1024.png" },
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_ios_1024.png" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
EOF

echo ""
echo "✅ Icons regenerated"
ls -la "$DEST"
