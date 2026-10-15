"""Builds ui/index.html from index.src.html by embedding the Bangers font (OFL) as base64.
Usage: python build.py path/to/Bangers-Regular.ttf"""
import base64, pathlib, sys

here = pathlib.Path(__file__).parent
font = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else here / "Bangers-Regular.ttf")
src = (here / "index.src.html").read_text(encoding="utf-8")
out = src.replace("/*BANGERS*/", base64.b64encode(font.read_bytes()).decode())
(here / "index.html").write_text(out, encoding="utf-8")
print("wrote", here / "index.html", len(out), "bytes")
