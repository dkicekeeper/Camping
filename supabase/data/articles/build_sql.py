#!/usr/bin/env python3
"""Статьи из Markdown → SQL для миграции (insert в public.articles).

Файлы: <id>.<ru|kk|en>.md с заголовком
    ---
    title: …
    summary: …
    ---
и порядок, категория, дата — в index.json. Разметка — подмножество Markdown, которое показывает
приложение (см. README.md). Проверяет разметку и печатает SQL в stdout.

    python3 supabase/data/articles/build_sql.py > /tmp/articles.sql
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
LANGS = ("ru", "kk", "en")
CATEGORIES = {"tackle", "knots", "technique", "cooking", "safety", "rules_ethics", "places_seasons"}

# Строки, которые приложение показывает: заголовки ##/###, списки, нумерация, выноска «>», абзацы.
BLOCK = re.compile(r"^(## |### |- |\d+\. |> )")
FORBIDDEN = [
    (re.compile(r"!\["), "картинки"),
    (re.compile(r"<[a-zA-Z/]"), "HTML"),
    (re.compile(r"^\s*\|"), "таблицы"),
    (re.compile(r"^#(?!#)|^####"), "заголовки, кроме ## и ###"),
    (re.compile(r"^```"), "блоки кода"),
    (re.compile(r"^\s+[-*\d]"), "вложенные списки"),
]


def parse(path: Path) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\ntitle: (.+)\nsummary: (.+)\n---\n(.*)$", text, re.S)
    if not match:
        sys.exit(f"{path.name}: нет заголовка title/summary")
    title, summary, body = (part.strip() for part in match.groups())
    for number, line in enumerate(body.splitlines(), start=1):
        for pattern, what in FORBIDDEN:
            if pattern.search(line):
                sys.exit(f"{path.name}:{number}: не поддерживается — {what}")
    if "$md$" in text:
        sys.exit(f"{path.name}: нельзя использовать $md$")
    return title, summary, body


def quote(text: str) -> str:
    return "$md$" + text + "$md$"


def main() -> None:
    index = json.loads((HERE / "index.json").read_text(encoding="utf-8"))
    rows = []
    for article in index:
        if article["category"] not in CATEGORIES:
            sys.exit(f"{article['id']}: неизвестная категория {article['category']}")
        parts = {lang: parse(HERE / f"{article['id']}.{lang}.md") for lang in LANGS}
        values = [f"'{article['id']}'", f"'{article['category']}'", str(article["sort_order"]),
                  f"date '{article['published_on']}'"]
        for field in range(3):
            values += [quote(parts[lang][field]) for lang in LANGS]
        rows.append("  (" + ",\n   ".join(values) + ")")
    print("insert into public.articles\n"
          "  (id, category, sort_order, published_on,\n"
          "   title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en, body_ru, body_kk, body_en)\n"
          "values\n" + ",\n".join(rows) + ";")


if __name__ == "__main__":
    main()
