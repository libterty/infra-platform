// pptx 簡報範本（pptxgenjs）
// 每一頁示範一種版型，內容都是佔位文字；複製這個資料夾後，改頁面內容與講稿.md 即可。
// 講稿：講稿.md（唯一真相來源；每頁「##」到「出處：」之間的文字就是備忘稿）
// 執行：NODE_PATH=../../node_modules node build.js [out.pptx]
//       python3 ../../fixfonts.py <out.pptx> "Microsoft JhengHei"   # 補上中文字型（pptxgenjs 只寫拉丁字型）
const fs = require("fs");
const path = require("path");
const pptxgen = require("pptxgenjs");

const OUT = process.argv[2] || path.join(__dirname, "deck.pptx");
const SCRIPT = fs.readFileSync(path.join(__dirname, "講稿.md"), "utf8");
const NOTES = SCRIPT.split(/^## \d+｜.*$/m).slice(1).map((sec) => sec.split(/^出處：/m)[0].trim());

const FONT = "Microsoft JhengHei";
const BG = "211F29", CARD = "35303D", TXT = "F7F3EC", MUTED = "C9C3CC", ACC = "F0A882";
const X0 = 0.6, W = 8.8;

const pres = new pptxgen();
pres.layout = "LAYOUT_16x9"; // 10 x 5.625 in
pres.theme = { headFontFace: FONT, bodyFontFace: FONT };
pres.title = "簡報範本";

pres.defineSlideMaster({ title: "STATEMENT", background: { color: BG } });
pres.defineSlideMaster({
  title: "NOTE",
  background: { color: BG },
  slideNumber: { x: 9.0, y: 5.22, w: 0.5, h: 0.22, fontSize: 9, color: MUTED, align: "right" },
  objects: [
    { placeholder: { options: { name: "kicker", type: "body", x: X0, y: 0.38, w: W, h: 0.3, fontSize: 11, bold: true, color: MUTED, charSpacing: 2, margin: 0, valign: "middle", align: "left" }, text: "" } },
    { placeholder: { options: { name: "title", type: "title", x: X0, y: 0.72, w: W, h: 0.7, fontSize: 26, bold: true, color: TXT, margin: 0, valign: "middle", align: "left" }, text: "" } },
  ],
});

let page = 0;
function nextNotes(s) {
  const n = NOTES[page++];
  if (n) s.addNotes(n);
}

// 片段：[{t, a(強調色), b(粗體), c(顏色), br(換行)}]
const runs = (parts, base = {}) => parts.map((p) => ({ text: p.t, options: { ...base, color: p.a ? ACC : p.c || base.color || TXT, bold: p.b ?? base.bold, breakLine: !!p.br } }));

function cite(s, text) {
  s.addText(text, { x: X0, y: 4.98, w: 8.2, h: 0.3, fontSize: 10, color: MUTED, margin: 0, valign: "bottom", isTextBox: true, objectName: "citation" });
}

function note(kicker, title) {
  const s = pres.addSlide({ masterName: "NOTE" });
  nextNotes(s);
  s.addText(kicker, { placeholder: "kicker" });
  s.addText(title, { placeholder: "title" });
  return s;
}

function box(s, x, y, w, h, name) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, fill: { color: CARD }, line: { type: "none" }, rectRadius: 0.08, objectName: name });
}

function text(s, t, o) {
  s.addText(t, { margin: 0, isTextBox: true, valign: "top", color: TXT, ...o });
}

// 卡片：label（標題）＋ body（字串或片段）
function card(s, { x, y, w, h, label, hot = false, body, bodySize = 14, name }) {
  box(s, x, y, w, h, name);
  const bodyRuns = typeof body === "string" ? [{ text: body, options: { fontSize: bodySize, color: TXT } }] : runs(body, { fontSize: bodySize });
  s.addText([{ text: label, options: { fontSize: 15, bold: true, color: hot ? ACC : TXT, breakLine: true, paraSpaceAfter: 6 } }, ...bodyRuns],
    { x: x + 0.22, y: y + 0.18, w: w - 0.44, h: h - 0.36, valign: "top", margin: 0, isTextBox: true, lineSpacingMultiple: 1.15 });
}

// 結語：一行灰字＋強調字
function line(s, parts, y = 4.4, size = 15) {
  s.addText(runs(parts), { x: X0, y, w: W, h: 0.45, fontSize: size, margin: 0, valign: "top", isTextBox: true, objectName: "takeaway" });
}

function arrow(s, x, y, w, name) {
  s.addShape(pres.shapes.RIGHT_ARROW, { x, y, w, h: 0.28, fill: { color: MUTED }, line: { type: "none" }, objectName: name });
}

// 表格式的列：cols = [{w, size, bold, hot, muted}]，rows = [[...cells]]，header 可省略
function grid(s, { y, rowH, cols, rows, header, gap = 0.1 }) {
  let cy = y;
  if (header) {
    let cx = X0;
    header.forEach((h, i) => {
      text(s, h, { x: cx + 0.2, y: cy, w: cols[i].w - 0.3, h: 0.3, fontSize: 12, bold: true, color: MUTED, valign: "middle" });
      cx += cols[i].w;
    });
    cy += 0.36;
  }
  rows.forEach((r, ri) => {
    box(s, X0, cy, W, rowH, `row-${ri}`);
    let cx = X0;
    r.forEach((cell, i) => {
      const c = cols[i];
      text(s, cell, { x: cx + 0.2, y: cy, w: c.w - 0.3, h: rowH, fontSize: c.size || 14, bold: !!c.bold, color: c.hot ? ACC : c.muted ? MUTED : TXT, valign: "middle", lineSpacingMultiple: 1.1 });
      cx += c.w;
    });
    cy += rowH + gap;
  });
}

// ---------- 1 封面 ----------
{
  const s = pres.addSlide({ masterName: "STATEMENT" });
  nextNotes(s);
  text(s, "TOPIC · 簡報類型", { x: X0, y: 0.7, w: W, h: 0.35, fontSize: 13, bold: true, color: MUTED, charSpacing: 3 });
  s.addText(runs([{ t: "簡報標題", br: true }, { t: "一句話講出主張", a: true }], { bold: true }), { x: X0, y: 1.5, w: W, h: 1.95, fontSize: 40, margin: 0, valign: "middle", isTextBox: true, objectName: "cover-title" });
  text(s, "副標：補充範圍或對象", { x: X0, y: 3.65, w: W, h: 0.45, fontSize: 18, color: MUTED });
  text(s, "YYYY-MM", { x: X0, y: 4.75, w: W, h: 0.3, fontSize: 12, color: MUTED });
}

// ---------- 2 結論列 ----------
{
  const s = note("結論", "標題直接寫結論");
  grid(s, {
    y: 1.6, rowH: 0.78, gap: 0.14,
    cols: [{ w: 1.9, size: 16, bold: true, muted: true }, { w: 6.9, size: 16 }],
    rows: [
      ["問題", "一句話描述現在的問題"],
      ["做法", "一句話描述建議的做法"],
      ["今天要決定", "請聽眾決定或確認的事"],
    ],
  });
  s.addShape(pres.shapes.RECTANGLE, { x: X0, y: 1.6 + 2 * 0.92, w: 0.06, h: 0.78, fill: { color: ACC }, line: { type: "none" }, objectName: "ask-mark" });
}

// ---------- 3 三張卡片 ----------
{
  const s = note("現況", "三張卡片：並列三個觀察");
  const cw = (W - 0.3) / 3;
  card(s, { x: X0, y: 1.6, w: cw, h: 1.6, label: "觀察一", body: "一到兩行說明", name: "card-0" });
  card(s, { x: X0 + cw + 0.15, y: 1.6, w: cw, h: 1.6, label: "觀察二", body: "一到兩行說明", name: "card-1" });
  card(s, { x: X0 + 2 * (cw + 0.15), y: 1.6, w: cw, h: 1.6, label: "最重要的觀察", hot: true, body: "用強調色標出重點", name: "card-2" });
  line(s, [{ t: "結語用一行收尾，", c: MUTED }, { t: "重點用強調色", a: true, b: true }], 3.6);
}

// ---------- 4 左右對照 ----------
{
  const s = note("比較", "左右對照：兩個選項或兩種情況");
  const cw = (W - 0.2) / 2;
  card(s, {
    x: X0, y: 1.6, w: cw, h: 2.5, label: "選項 A", hot: true, name: "left",
    body: [{ t: "主要特性", br: true }, { t: "補充說明用灰字", c: MUTED, br: true }, { t: " ", br: true }, { t: "第二個特性", br: true }, { t: "補充說明", c: MUTED }],
  });
  card(s, {
    x: X0 + cw + 0.2, y: 1.6, w: cw, h: 2.5, label: "選項 B", name: "right",
    body: [{ t: "主要特性", br: true }, { t: "補充說明用灰字", c: MUTED, br: true }, { t: " ", br: true }, { t: "第二個特性", br: true }, { t: "補充說明", c: MUTED }],
  });
  line(s, [{ t: "比較完的判斷，", c: MUTED }, { t: "寫在這一行", a: true, b: true }], 4.35);
}

// ---------- 5 流程 ----------
{
  const s = note("流程", "流程：三個步驟加箭頭");
  const gap = 0.45, cw = (W - gap * 2) / 3;
  const step = (i, label, body, hot) => {
    const x = X0 + i * (cw + gap);
    card(s, { x, y: 1.65, w: cw, h: 1.25, label, hot, body, name: `step-${i}` });
    if (i < 2) arrow(s, x + cw + 0.07, 1.65 + 0.48, gap - 0.14, `step-arrow-${i}`);
  };
  step(0, "步驟一", "做什麼");
  step(1, "步驟二", "做什麼");
  step(2, "結果", "得到什麼", true);
  text(s, "下方可以放兩句補充", { x: X0, y: 3.15, w: W, h: 0.3, fontSize: 12, bold: true, color: MUTED });
  text(s, [{ text: "補充說明第一句", options: { breakLine: true } }, { text: "補充說明第二句" }], { x: X0, y: 3.5, w: W, h: 0.9, fontSize: 16, lineSpacingMultiple: 1.35 });
  cite(s, "引用來源：作者，標題，出處，年份");
}

// ---------- 6 前後對照表 ----------
{
  const s = note("效果", "表格：現在與改變後");
  grid(s, {
    y: 1.5, rowH: 0.55, gap: 0.08,
    header: ["", "現在", "改變後"],
    cols: [{ w: 2.2, size: 13, bold: true, muted: true }, { w: 2.9, size: 13 }, { w: 3.7, size: 13, hot: true }],
    rows: [
      ["項目一", "目前的做法", "改變後的做法"],
      ["項目二", "目前的做法", "改變後的做法"],
      ["項目三", "目前的做法", "改變後的做法"],
      ["項目四", "目前的做法", "改變後的做法"],
    ],
  });
  line(s, [{ t: "表格下方寫限制或前提，", c: MUTED }, { t: "重點用粗體", b: true }], 4.45, 14);
}

// ---------- 7 分層 ----------
{
  const s = note("架構", "分層：由上往下的四層");
  const bw = 6.9, h = 0.6, gap = 0.1, y0 = 1.55;
  const layer = (i, n, d, hot) => {
    const y = y0 + i * (h + gap);
    box(s, X0, y, bw, h, `layer-${i}`);
    text(s, n, { x: X0 + 0.25, y, w: 2.9, h, fontSize: 15, bold: true, color: hot ? ACC : TXT, valign: "middle" });
    text(s, d, { x: X0 + 3.15, y, w: bw - 3.3, h, fontSize: 13, color: hot ? ACC : TXT, valign: "middle" });
  };
  layer(0, "第四層", "負責什麼");
  layer(1, "第三層", "負責什麼");
  layer(2, "第二層", "負責什麼");
  layer(3, "第一層（基礎）", "負責什麼", true);
  const bx = X0 + bw + 0.25;
  const brk = (y, hh, label, sub, name) => {
    s.addShape(pres.shapes.RECTANGLE, { x: bx, y, w: 0.05, h: hh, fill: { color: MUTED }, line: { type: "none" }, objectName: name });
    text(s, [{ text: label, options: { bold: true, breakLine: true } }, { text: sub, options: { color: MUTED, fontSize: 12 } }], { x: bx + 0.18, y, w: 1.5, h: hh, fontSize: 14, valign: "middle" });
  };
  brk(y0, h * 2 + gap, "上半", "特性", "brk-top");
  brk(y0 + 2 * (h + gap), h * 2 + gap, "下半", "特性", "brk-bottom");
  line(s, [{ t: "層與層的關係寫在這裡。", c: MUTED }, { t: "重點用粗體", b: true }], 4.45, 14);
}

// ---------- 8 編號清單 ----------
{
  const s = note("議題", "編號清單：列出要回答的問題");
  const q = (i, t, p) => {
    const y = 1.5 + i * 0.52;
    text(s, [{ text: `0${i + 1}  `, options: { color: MUTED, fontSize: 15 } }, { text: t, options: { bold: true, fontSize: 18 } }], { x: X0, y, w: 7.0, h: 0.46, valign: "middle" });
    text(s, p, { x: X0 + 7.6, y, w: 1.2, h: 0.46, fontSize: 12, color: MUTED, align: "right", valign: "middle" });
  };
  q(0, "第一個問題", "p.9");
  q(1, "第二個問題", "p.9");
  q(2, "第三個問題", "p.10");
  q(3, "第四個問題", "p.10");
  line(s, [{ t: "右側可以標出回答在哪一頁", c: MUTED }], 3.8);
}

// ---------- 9 階段 ----------
{
  const s = note("推動", "四個階段，達到條件才進下一階");
  const gap = 0.3, cw = (W - gap * 3) / 4;
  const phase = (i, label, body, hot) => {
    const x = X0 + i * (cw + gap);
    card(s, { x, y: 1.65, w: cw, h: 1.65, label, hot, body, bodySize: 13, name: `phase-${i}` });
    if (i < 3) arrow(s, x + cw + 0.04, 1.65 + 0.68, gap - 0.08, `phase-arrow-${i}`);
  };
  phase(0, "1 階段一", "做什麼", true);
  phase(1, "2 階段二", "做什麼");
  phase(2, "3 階段三", "做什麼");
  phase(3, "4 階段四", "做什麼");
  line(s, [{ t: "推進的原則，", c: MUTED }, { t: "寫在這一行", a: true, b: true }], 3.7);
}

// ---------- 10 決策與下一步 ----------
{
  const s = note("今天要確認", "需要確認的兩件事");
  const cw = (W - 0.2) / 2;
  card(s, { x: X0, y: 1.5, w: cw, h: 1.3, label: "1　第一個決定", hot: true, name: "ask-1", bodySize: 13, body: "具體要對方決定什麼" });
  card(s, { x: X0 + cw + 0.2, y: 1.5, w: cw, h: 1.3, label: "2　第二個決定", hot: true, name: "ask-2", bodySize: 13, body: "具體要對方決定什麼" });
  text(s, "確認之後的下一步", { x: X0, y: 3.0, w: W, h: 0.3, fontSize: 12, bold: true, color: MUTED });
  grid(s, {
    y: 3.35, rowH: 0.45, gap: 0.06,
    cols: [{ w: 7.2, size: 13 }, { w: 1.6, size: 12, muted: true }],
    rows: [
      ["要做的事，以及期限或檢查點", "負責人"],
      ["要做的事，以及期限或檢查點", "負責人"],
    ],
  });
}

if (page !== NOTES.length) throw new Error(`notes mismatch: used ${page}, have ${NOTES.length}`);

(async () => {
  await pres.writeFile({ fileName: OUT });
  console.log("wrote", OUT, `(${page} slides)`);
})();
