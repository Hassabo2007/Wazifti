#!/usr/bin/env python3
"""Read-only guardrails for active Supabase migration files in pull requests."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
HEAD = sys.argv[2] if len(sys.argv) > 2 else "HEAD"

changed = subprocess.check_output(
    ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{BASE}...{HEAD}"],
    cwd=ROOT, text=True,
).splitlines()

migration_paths = [p for p in changed if p.startswith("supabase/migrations/") and p.endswith(".sql")]
errors = []
name_pattern = re.compile(r"^\d{14}_[a-z0-9_]+\.sql$")

for rel in migration_paths:
    path = ROOT / rel
    if not name_pattern.fullmatch(path.name):
        errors.append(f"{rel}: expected 14-digit timestamp and lowercase descriptive name")
        continue
    sql = path.read_text(encoding="utf-8")
    if not sql.strip():
        errors.append(f"{rel}: empty migration")
    if re.search(r"(?im)^\s*\\(include|i|ir)\b", sql):
        errors.append(f"{rel}: psql file inclusion is not permitted in migrations")
    # Historical recovery SQL is evidence only and must never be reintroduced as active migrations.
    if "production-ledger-archive" in rel or "recovered-production-migrations" in rel:
        errors.append(f"{rel}: recovered historical SQL must remain outside supabase/migrations")

# Catch duplicate version prefixes across the complete active migration directory.
all_versions = {}
for path in sorted((ROOT / "supabase/migrations").glob("*.sql")):
    match = re.match(r"^(\d{14})_", path.name)
    if match:
        all_versions.setdefault(match.group(1), []).append(path.name)
for version, names in all_versions.items():
    if len(names) > 1:
        errors.append(f"duplicate migration version {version}: {', '.join(names)}")

if not migration_paths:
    print("No active migration SQL changed; migration-specific checks not applicable.")
else:
    print(f"Checking {len(migration_paths)} changed migration file(s).")
if errors:
    print("\nMIGRATION SAFETY CHECK FAILED:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)
print("Migration filename, uniqueness, non-empty, and archive-separation checks passed.")
