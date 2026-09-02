#!/usr/bin/env python3
"""Extract translatable static text from rendered, non-profile website pages."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path


SKIP_TAGS = {
    "a", "canvas", "code", "figure", "iframe", "math", "pre", "script",
    "style", "svg", "table", "textarea",
}
VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}
SKIP_CLASSES = {
    "cell", "cell-output", "cell-output-display", "cell-output-stdout",
    "datatables", "figure", "form-embed", "html-widget", "plotly",
    "sourceCode", "vivax-chart", "vivax-chart-payload",
}
URL_OR_EMAIL = re.compile(r"(?:https?://|www\.|\b[^\s@]+@[^\s@]+\.[^\s@]+)", re.I)
HAS_WORD = re.compile(r"[A-Za-z]{2,}")


def normalise(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


class StaticTextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.tag_skips: list[bool] = []
        self.strings: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        classes = set((attrs_dict.get("class") or "").split())
        skip = self.skip_depth > 0 or tag in SKIP_TAGS or bool(classes & SKIP_CLASSES)
        if tag in VOID_TAGS:
            return
        self.tag_skips.append(skip)
        if skip:
            self.skip_depth += 1
            return
        for name in ("aria-label", "placeholder", "title"):
            self.add(attrs_dict.get(name) or "")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.skip_depth == 0 and tag not in SKIP_TAGS:
            attrs_dict = dict(attrs)
            for name in ("aria-label", "placeholder", "title"):
                self.add(attrs_dict.get(name) or "")

    def handle_endtag(self, tag: str) -> None:
        if not self.tag_skips:
            return
        skipped = self.tag_skips.pop()
        if skipped:
            self.skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.skip_depth == 0:
            self.add(data)

    def add(self, value: str) -> None:
        value = normalise(value)
        if (
            value
            and HAS_WORD.search(value)
            and "@" not in value
            and not URL_OR_EMAIL.search(value)
            and len(value) <= 1500
        ):
            self.strings.add(value)


def key_for(value: str) -> str:
    return "static." + hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    site = root / "_site"
    output = root / "translations" / "en.json"
    if not site.exists():
        print("Rendered site not found; retaining the existing translation manifest.")
        return 0

    parser = StaticTextParser()
    pages = [path for path in site.glob("*.html") if path.is_file()]
    for path in sorted(pages):
        parser.feed(path.read_text(encoding="utf-8", errors="replace"))

    strings = {key_for(value): value for value in sorted(parser.strings, key=str.casefold)}
    payload = {
        "meta": {
            "language": "en",
            "scope": "Static non-output text; links, emails, URLs, tables, plots and R output excluded",
            "generated_from": [path.name for path in sorted(pages)],
        },
        "strings": strings,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Extracted {len(strings)} eligible static strings from {len(pages)} rendered pages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
