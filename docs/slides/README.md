# slides

做簡報用的工具與範本。實際的簡報內容含客戶與內部專案資訊，只放在本機，不進這個 repo（見根目錄 `.gitignore`）。

| 路徑 | 內容 |
|---|---|
| `templates/pptx-deck/` | pptxgenjs 簡報範本：10 種版型，講稿 md 自動帶進備忘稿 |
| `open-slide-redesign/` | [open-slide](https://www.npmjs.com/package/@open-slide/core) 工作區；repo 裡只有官方範例 `getting-started` |
| `fixfonts.py` | 補上中文字型：pptxgenjs 只寫拉丁字型（`<a:latin>`），中文要另外寫 `<a:ea>` |
| `pptx-preview.sh` | 把 pptx 轉成每頁一張 1920×1080 的 PNG（LibreOffice + poppler），給 open-slide 當預覽：`pptx-preview.sh deck.pptx open-slide-redesign/slides/<id>/assets`。在 watch 腳本裡每次重建 pptx 後呼叫它，瀏覽器就會跟著顯示最新的 pptx |
| `fontconfig-retro.xml` | 用 LibreOffice 把 pptx 轉成 PDF 或圖檔預覽時，讓它找得到使用者字型目錄裡的中文字型 |
| `package.json` | pptx 範本用的 pptxgenjs |

## 用 pptx 範本做一份簡報

```bash
cd docs/slides
npm install

cp -r templates/pptx-deck <你的簡報資料夾>
cd <你的簡報資料夾>
# 改 build.js 的頁面內容，以及講稿.md（每頁一個「## N｜標題」，頁數要跟 build.js 一樣）
NODE_PATH=<docs/slides>/node_modules node build.js deck.pptx
python3 <docs/slides>/fixfonts.py deck.pptx "Microsoft JhengHei"
```

`講稿.md` 裡每頁「出處：」之後的文字只給講者查證用，不會放進備忘稿。

預覽（需要 LibreOffice 與 poppler）：

```bash
FONTCONFIG_FILE=<docs/slides>/fontconfig-retro.xml soffice --headless --convert-to pdf deck.pptx
pdftoppm -png -r 60 deck.pdf page
```

macOS 沒有 `Microsoft JhengHei`。預覽時可以另存一份 pptx，用 `fixfonts.py` 改成 `"Noto Sans TC"` 再轉。

## 用 open-slide

```bash
cd docs/slides/open-slide-redesign
npm install
npm run dev
```

新簡報放在 `slides/<id>/index.tsx`，寫法見 `open-slide-redesign/README.md`。除了 `getting-started`，`slides/` 底下的其他資料夾都不會進 repo。
