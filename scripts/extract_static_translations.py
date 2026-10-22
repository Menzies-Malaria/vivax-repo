#!/usr/bin/env python3
"""Extract approved translatable text from rendered website pages."""

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
    def __init__(self, allow_tables: bool = False) -> None:
        super().__init__(convert_charrefs=True)
        self.allow_tables = allow_tables
        self.skip_depth = 0
        self.tag_skips: list[bool] = []
        self.strings: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        classes = set((attrs_dict.get("class") or "").split())
        approved_link = tag == "a" and bool(
            {"country-card", "country-contact-request__link"} & classes
        )
        tag_is_excluded = (
            tag in SKIP_TAGS
            and not (tag == "table" and self.allow_tables)
            and not approved_link
        )
        skip = self.skip_depth > 0 or tag_is_excluded or bool(classes & SKIP_CLASSES)
        if tag in VOID_TAGS:
            return
        self.tag_skips.append(skip)
        if skip:
            self.skip_depth += 1
            return
        for name in ("aria-label", "placeholder", "title"):
            self.add(attrs_dict.get(name) or "")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag_is_excluded = tag in SKIP_TAGS and not (tag == "table" and self.allow_tables)
        if self.skip_depth == 0 and not tag_is_excluded:
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
    root_pages = sorted(path for path in site.glob("*.html") if path.is_file())
    profile_dir = site / "profiles"
    profile_pages = sorted(path for path in profile_dir.glob("*.html") if path.is_file())
    pages = root_pages + profile_pages
    for path in pages:
        # Tables remain excluded everywhere except generated country profiles.
        # This brings approved profile labels and values into scope without
        # translating the Explore-data table or other computed outputs.
        page_parser = StaticTextParser(allow_tables=path.parent == profile_dir)
        page_parser.feed(path.read_text(encoding="utf-8", errors="replace"))
        parser.strings.update(page_parser.strings)

    manual_path = root / "translations" / "map-ui.json"
    if manual_path.exists():
        manual = json.loads(manual_path.read_text(encoding="utf-8"))
        for value in manual.get("strings", []):
            parser.add(value)

    strings = {key_for(value): value for value in sorted(parser.strings, key=str.casefold)}
    payload = {
        "meta": {
            "language": "en",
            "scope": (
                "Static site text plus generated country-profile text; links, emails, URLs, "
                "non-profile tables, plots and code output excluded"
            ),
            "generated_from": [path.relative_to(site).as_posix() for path in pages],
            "manual_source": "translations/map-ui.json",
        },
        "strings": strings,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Extracted {len(strings)} eligible static strings from {len(pages)} rendered pages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
