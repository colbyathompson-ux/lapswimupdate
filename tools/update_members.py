#!/usr/bin/env python3
"""Turn the active-membership CSV export into a SQL file for Supabase.

Usage:
    python3 tools/update_members.py path/to/agreements.csv [out.sql]

Reads the "Member" column ("Last, First Middle (YES)" / "Last, First (12345)"),
keeps only rows whose Status is Active, drops anything in parentheses and any
numbers, and writes a SQL file (default: members_load.sql next to the CSV).
Paste that file into the Supabase SQL editor and run it: it sets up the
members table and check function if needed, then replaces the member list.

The SQL file holds members' names. Do not commit it or the CSV to the repo.
"""
import csv
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
SUFFIXES = {"jr", "sr", "ii", "iii", "iv"}


def clean(part):
    s = unicodedata.normalize("NFD", part)
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    s = re.sub(r"\([^)]*\)", " ", s)      # (YES), (25454)
    s = re.sub(r"[0-9]", " ", s)
    s = s.replace("'", "")
    s = re.sub(r"[^a-z\s-]", " ", s)
    return " ".join(w for w in s.replace("-", " ").split() if w not in SUFFIXES)


def load(csv_path):
    seen, out = set(), []
    with open(csv_path, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if (row.get("Status") or "").strip().lower() != "active":
                continue
            member = row.get("Member") or ""
            if "," not in member:
                continue
            last, first = member.split(",", 1)
            last, first = clean(last), clean(first)
            if not last or not first:
                continue
            key = last + "|" + first
            if key not in seen:
                seen.add(key)
                out.append(key)
    out.sort()
    return out


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    csv_path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) == 3 else os.path.join(os.path.dirname(os.path.abspath(csv_path)), "members_load.sql")
    names = load(csv_path)
    if not names:
        sys.exit("No active members found in that file - nothing written.")

    def arr(words):
        # words are only a-z after clean(), so they are safe to quote directly
        return "array[" + ",".join("'%s'" % w for w in words.split()) + "]"

    schema = open(os.path.join(HERE, "members_schema.sql"), encoding="utf-8").read()
    rows = ",\n".join("  (%s, %s)" % (arr(n.split("|")[1]), arr(n.split("|")[0])) for n in names)
    with open(out, "w", encoding="utf-8") as f:
        f.write(schema)
        f.write("\n-- Replace the member list (%d active members)\n" % len(names))
        f.write("begin;\ndelete from public.members;\n")
        f.write("insert into public.members (first_names, last_names) values\n" + rows + ";\ncommit;\n")
    print("Wrote %d active members to %s" % (len(names), out))
    print("Next: open Supabase -> SQL editor, paste that file, and click Run.")


if __name__ == "__main__":
    main()
