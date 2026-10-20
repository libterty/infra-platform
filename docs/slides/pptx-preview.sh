#!/usr/bin/env bash
# 把 pptx 轉成每頁一張 1920×1080 的 PNG，給 open-slide 預覽用（需要 LibreOffice 與 poppler）
# 用法：pptx-preview.sh <deck.pptx> <out-dir>
# 寫出 <out-dir>/pages/NN.png 與 <out-dir>/stamp.ts（open-slide 靠它換掉快取的舊圖）；舊的 pages 一次整批換掉
# macOS 沒有 Microsoft JhengHei：轉檔前在暫存副本裡換成 Noto Sans TC，所以字距可能跟 PowerPoint 有一點差異
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -eq 2 ] || { sed -n '3p' "$0" | sed 's/^# //' >&2; exit 1; }
pptx="$1"
out="$2"
[ -f "$pptx" ] || { echo "pptx-preview: 找不到 $pptx" >&2; exit 1; }
command -v soffice >/dev/null || { echo "pptx-preview: 需要 LibreOffice（soffice）" >&2; exit 1; }
command -v pdftoppm >/dev/null || { echo "pptx-preview: 需要 poppler（pdftoppm）" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 - "$pptx" "$work/deck.pptx" <<'PY'
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        data = zin.read(item.filename)
        if item.filename.endswith(".xml"):
            data = data.replace(b'typeface="Microsoft JhengHei"', b'typeface="Noto Sans TC"')
        zout.writestr(item, data)
PY

# 獨立的 LibreOffice 設定檔：本機開著 LibreOffice 時，共用設定檔會讓轉檔直接失敗
profile="${TMPDIR:-/tmp}/pptx-preview-lo-profile"
FONTCONFIG_FILE="${here}/fontconfig-retro.xml" soffice -env:UserInstallation="file://${profile}" \
  --headless --convert-to pdf --outdir "$work" "$work/deck.pptx" >/dev/null 2>&1
[ -f "$work/deck.pdf" ] || { echo "pptx-preview: LibreOffice 沒有產生 PDF" >&2; exit 1; }

mkdir -p "$work/pages"
pdftoppm -png -scale-to-x 1920 -scale-to-y 1080 "$work/deck.pdf" "$work/pages/p"
for f in "$work"/pages/p-*.png; do
  n="${f##*/p-}"
  mv "$f" "$work/pages/$(printf '%02d' "$((10#${n%.png}))").png"
done

mkdir -p "$out"
rm -rf "$out/pages.new"
mv "$work/pages" "$out/pages.new"
rm -rf "$out/pages"
mv "$out/pages.new" "$out/pages"
printf 'export const stamp = %s;\n' "$(date +%s)" >"$out/stamp.ts.new"
mv "$out/stamp.ts.new" "$out/stamp.ts"
echo "preview -> $out/pages ($(find "$out/pages" -name '*.png' | wc -l | tr -d ' ') pages)"
