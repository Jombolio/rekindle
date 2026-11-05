#!/usr/bin/env python3
"""Builds the English dictionary both clients ship, from the WordNet database files.

    python tools/build_wordnet.py path/to/WordNet/dict

Download the database from https://wordnet.princeton.edu/download/current-version
(wn3.1.dict.tar.gz), unpack it, and pass its dict folder. The output is reproducible:
the same input gives byte-identical files.
"""
import gzip
import re
import sqlite3
import sys
import tempfile
from pathlib import Path

OUTPUT = Path(__file__).resolve().parent.parent / "desktop" / "assets" / "dictionary"
POS = {"noun": "n", "verb": "v", "adj": "a", "adv": "r"}
SCHEMA_VERSION = 1


def split_gloss(gloss):
    """A gloss is a definition, then any examples in quotes, separated by semicolons."""
    quote = gloss.find('"')
    definition = (gloss if quote < 0 else gloss[:quote]).strip().rstrip(";").strip()
    example = re.search(r'"([^"]+)"', gloss)
    return definition, example.group(1) if example else None


def data_lines(path):
    # The licence header is the only part of these files indented with two spaces.
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("  "):
            yield line


def licence(path):
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("  "):
            break
        # Each header line is "  <number> <text>".
        lines.append(re.sub(r"^\s+\d+\s?", "", line).rstrip())
    return "\n".join(lines).strip() + "\n"


def build(source, database):
    db = sqlite3.connect(database)
    db.executescript(
        f"""
        PRAGMA page_size = 4096;
        PRAGMA user_version = {SCHEMA_VERSION};
        CREATE TABLE synsets (id INTEGER PRIMARY KEY, definition TEXT NOT NULL, example TEXT);
        CREATE TABLE senses (
            word TEXT NOT NULL, pos TEXT NOT NULL, sense INTEGER NOT NULL, synset INTEGER NOT NULL,
            PRIMARY KEY (word, pos, sense)
        ) WITHOUT ROWID;
        CREATE TABLE exceptions (form TEXT NOT NULL, lemma TEXT NOT NULL, PRIMARY KEY (form, lemma)) WITHOUT ROWID;
        """
    )

    next_id = 1
    for name, pos in POS.items():
        synsets = {}
        for line in data_lines(source / f"data.{name}"):
            offset = line.split(" ", 1)[0]
            definition, example = split_gloss(line.split(" | ", 1)[1])
            db.execute("INSERT INTO synsets VALUES (?, ?, ?)", (next_id, definition, example))
            synsets[offset] = next_id
            next_id += 1

        for line in data_lines(source / f"index.{name}"):
            parts = line.split()
            word = parts[0].replace("_", " ")
            # lemma pos synset_cnt p_cnt ptr... sense_cnt tagsense_cnt offset...
            # The offsets are in sense order, most common first.
            pointers = int(parts[3])
            offsets = parts[6 + pointers:]
            db.executemany(
                "INSERT INTO senses VALUES (?, ?, ?, ?)",
                [(word, pos, i, synsets[o]) for i, o in enumerate(offsets)],
            )

        for line in (source / f"{name}.exc").read_text(encoding="utf-8").splitlines():
            form, *lemmas = line.split()
            db.executemany(
                "INSERT OR IGNORE INTO exceptions VALUES (?, ?)",
                [(form.replace("_", " "), lemma.replace("_", " ")) for lemma in lemmas],
            )

    db.commit()
    db.execute("VACUUM")
    counts = [db.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in ("synsets", "senses", "exceptions")]
    db.close()
    return counts


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1])
    OUTPUT.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as temp:
        database = Path(temp) / "wordnet.db"
        synsets, senses, exceptions = build(source, database)
        raw = database.read_bytes()

    target = OUTPUT / "wordnet.db.gz"
    with target.open("wb") as out:
        # filename and mtime left empty so the output doesn't vary between builds.
        with gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=out, mtime=0) as gz:
            gz.write(raw)

    (OUTPUT / "LICENSE-WordNet.txt").write_text(licence(source / "index.noun"), encoding="utf-8", newline="\n")

    print(f"{synsets} synsets, {senses} senses, {exceptions} exceptions")
    print(f"database {len(raw) / 1048576:.1f} MB, compressed {target.stat().st_size / 1048576:.1f} MB")


if __name__ == "__main__":
    main()
