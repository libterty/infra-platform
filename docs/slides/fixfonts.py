"""pptxgenjs 只寫 <a:latin>，中文走的是 <a:ea>。補上 ea/cs，並填 theme 的東亞字型。"""
import re, shutil, sys, zipfile
from pathlib import Path

CJK = sys.argv[2] if len(sys.argv) > 2 else "PingFang TC"
src = Path(sys.argv[1])
tmp = src.with_suffix(".tmp.pptx")

latin_self = re.compile(r'<a:latin typeface="([^"]*)"\s*/>')
latin_open = re.compile(r'<a:latin typeface="([^"]*)"\s*>.*?</a:latin>', re.S)


def add_ea(xml: str) -> str:
    def rep(m):
        whole = m.group(0)
        # 後面若已經有 ea 就不重複加（由呼叫端的順序保證，這裡只看自己）
        return f'{whole}<a:ea typeface="{CJK}"/><a:cs typeface="{CJK}"/>'
    xml = latin_self.sub(rep, xml)
    return xml


with zipfile.ZipFile(src) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        data = zin.read(item.filename)
        name = item.filename
        if name.startswith("ppt/slides/slide") and name.endswith(".xml"):
            xml = data.decode("utf-8")
            xml = re.sub(r'<a:ea typeface="[^"]*"\s*/>', "", xml)
            xml = re.sub(r'<a:cs typeface="[^"]*"\s*/>', "", xml)
            data = add_ea(xml).encode("utf-8")
        elif name.startswith("ppt/theme/") and name.endswith(".xml"):
            xml = data.decode("utf-8")
            xml = xml.replace('<a:ea typeface=""/>', f'<a:ea typeface="{CJK}"/>')
            xml = xml.replace('<a:cs typeface=""/>', f'<a:cs typeface="{CJK}"/>')
            data = xml.encode("utf-8")
        zout.writestr(item, data)

shutil.move(str(tmp), str(src))
print(f"ea/cs typeface -> {CJK}: {src.name}")
