#!/usr/bin/env python3
"""Read-only reconciliation of the captured production migration ledger and repo SQL files."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/audits/supabase-production-migration-ledger-2026-11-10.json"
MIGRATIONS = ROOT / "supabase/migrations"

ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
files = sorted(MIGRATIONS.glob("*.sql"))
assert len({row["version"] for row in ledger}) == len(ledger), "Duplicate versions in production ledger"
assert all(row.get("statements") for row in ledger), "Ledger entry missing stored SQL"

def normalize_sql(sql):
    sql = re.sub(r"/\\*.*?\\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\\n]*", " ", sql)
    sql = re.sub(r"^\\s*begin\\s*;", "", sql, flags=re.I)
    sql = re.sub(r";\\s*commit\\s*;?\\s*$", ";", sql, flags=re.I)
    return re.sub(r"\\s+", " ", sql).strip().lower()

source = {path: path.read_text(encoding="utf-8").strip() for path in files}
applied_sql = {
    (row["version"], row["name"], statement.strip())
    for row in ledger for statement in row.get("statements", []) if statement.strip()
}
matched = set()
print(f"Production ledger entries: {len(ledger)}")
print(f"Repository migration files: {len(files)}")
print("\nExact content matches:")
for path, sql in source.items():
    matches = [(v, n) for v, n, applied in applied_sql if sql == applied]
    if matches:
        matched.update(matches)
        for version, name in matches:
            prefix = path.name.split("_", 1)[0]
            status = "version-aligned" if prefix == version else "CONTENT MATCH / VERSION FILENAME DRIFT"
            print(f"  {path.name} -> {version} {name}: {status}")
    else:
        normalized = [(v, n) for row in ledger for statement in row.get("statements", [])
                      if normalize_sql(sql) == normalize_sql(statement)
                      for v, n in [(row["version"], row["name"])]]
        if normalized:
            matched.update(normalized)
            print(f"  {path.name} -> {', '.join(v + ' ' + n for v, n in normalized)}: NORMALIZED TEXT MATCH (comments/whitespace/transaction wrapper only)")
        else:
            print(f"  {path.name}: NO EXACT OR NORMALIZED TEXT MATCH")

print("\nProduction ledger entries without an exact repository file:")
for row in ledger:
    if (row["version"], row["name"]) not in matched:
        print(f"  {row['version']} {row['name']}")

print("\nThis is a read-only content comparison. It does not repair migration history or execute SQL.")
