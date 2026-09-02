#!/usr/bin/env python3
"""Build reviewed-later, local-only interface translations with Argos Translate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


def canonical_hash(strings: dict[str, str]) -> str:
    payload = json.dumps(strings, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_source(path: Path) -> dict[str, str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    strings = payload.get("strings")
    if not isinstance(strings, dict) or not strings:
        raise ValueError("Translation source must contain a non-empty 'strings' object.")

    for key, value in strings.items():
        if not isinstance(key, str) or not isinstance(value, str) or not value.strip():
            raise ValueError(f"Invalid translation entry: {key!r}")
        if "@" in value or re.search(r"(?:https?://|www\.)", value, re.IGNORECASE):
            raise ValueError(f"URL or email is outside the translation scope: {key}")
        if len(value) > 1500:
            raise ValueError(f"Static text is unexpectedly long: {key}")
    return strings


def cache_is_current(output: Path, source_hash: str, target: str) -> bool:
    if not output.exists():
        return False
    try:
        payload = json.loads(output.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    meta = payload.get("meta", {})
    return meta.get("source_hash") == source_hash and meta.get("language") == target


def ensure_model(source: str, target: str) -> None:
    import argostranslate.package

    installed = argostranslate.package.get_installed_packages()
    if any(pkg.from_code == source and pkg.to_code == target for pkg in installed):
        return

    print(f"Argos model {source}->{target} is not installed; downloading it once...")
    argostranslate.package.update_package_index()
    candidates = [
        package
        for package in argostranslate.package.get_available_packages()
        if package.from_code == source and package.to_code == target
    ]
    if not candidates:
        raise RuntimeError(f"No direct Argos model is available for {source}->{target}.")
    candidates[0].install()


def translate(strings: dict[str, str], source: str, target: str) -> dict[str, str]:
    import argostranslate.package
    import argostranslate.translate
    import ctranslate2

    package = next(
        pkg for pkg in argostranslate.package.get_installed_packages()
        if pkg.from_code == source and pkg.to_code == target
    )
    translator = ctranslate2.Translator(str(package.package_path / "model"), device="cpu")

    class NoSplit:
        @staticmethod
        def split_sentences(text: str) -> list[str]:
            return [text]

    result: dict[str, str] = {}
    for key, value in strings.items():
        # We split locally so Argos never tries to download Stanza sentence data.
        chunks = re.split(r"(?<=[.!?])\s+", value)
        translated = " ".join(
            argostranslate.translate.apply_packaged_translation(
                package, chunk, translator, NoSplit(), num_hypotheses=1
            )[0].value.strip()
            for chunk in chunks
            if chunk.strip()
        ).strip()
        if not translated:
            raise RuntimeError(f"Argos returned an empty translation for {key}.")
        result[key] = translated
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="translations/en.json")
    parser.add_argument("--output", default="assets/translations/es.json")
    parser.add_argument("--from-language", default="en")
    parser.add_argument("--to-language", default="es")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    source_path = Path(args.source)
    output_path = Path(args.output)
    strings = load_source(source_path)
    source_hash = canonical_hash(strings)
    character_count = sum(len(value) for value in strings.values())
    print(f"Local Argos manifest: {len(strings)} strings, {character_count} characters.")

    if not args.force and cache_is_current(output_path, source_hash, args.to_language):
        print(f"Translation cache is current: {output_path}")
        return 0

    if args.check_only:
        print(f"Translation cache requires regeneration: {output_path}")
        return 3

    ensure_model(args.from_language, args.to_language)
    translated = translate(strings, args.from_language, args.to_language)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "meta": {
            "language": args.to_language,
            "source_language": args.from_language,
            "source_hash": source_hash,
            "engine": "Argos Translate",
            "review_status": "machine draft - human review required",
            "string_count": len(strings),
            "source_character_count": character_count,
        },
        "strings": translated,
    }
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote machine-draft translations to {output_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Translation build failed: {exc}", file=sys.stderr)
        raise
