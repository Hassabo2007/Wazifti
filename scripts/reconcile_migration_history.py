#!/usr/bin/env python3
"""Read-only reconciliation of the captured production migration ledger and repo SQL files."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/audits/supabase-production-migration-ledger-2026-11-10.json"
MIGRATIONS = ROOT / "supabase/migrations"

ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
files = sorted(MIGRATIONS.glob("*.sql"))
assert len({row["version"] for row in ledger}) == len(ledger), "Duplicate versions in production ledger"
assert all(row.get("statements") for row in ledger), "Ledger entry missing stored SQL"

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
        print(f"  {path.name}: NO EXACT APPLIED-SQL MATCH")

print("\nProduction ledger entries without an exact repository file:")
for row in ledger:
    if not any((row["version"], row["name"], (statement or "").strip()) in matched
               for statement in row.get("statements", [])):
        print(f"  {row['version']} {row['name']}")

print("\nThis is a read-only content comparison. It does not repair migration history or execute SQL.")
