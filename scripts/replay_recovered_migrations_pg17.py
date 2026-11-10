#!/usr/bin/env python3
"""Replay recovered production ledger SQL on a disposable local PostgreSQL test DB.

Never connects to Supabase and never writes into supabase/migrations.
Two migrations are deliberately excluded because stock postgres:17 lacks the
Supabase Realtime publication and pg_cron/pg_net extension services.
"""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path

SKIPS = {
    "20261107110343": "Supabase-managed supabase_realtime publication / WAL configuration",
    "20261109185459": "Supabase-managed pg_cron + pg_net scheduler and Vault-backed cron setup",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", default="5432")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--database", required=True)
    args = parser.parse_args()

    input_dir = Path(args.input_dir).resolve()
    manifest_path = input_dir / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit("Recovered migration artifact manifest.json is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if "DO NOT RUN" not in manifest.get("warning", ""):
        raise SystemExit("Refusing replay: artifact does not carry the forensic-only warning")
    if len(manifest.get("migrations", [])) != 26:
        raise SystemExit("Unexpected ledger size; expected the captured 26-entry production ledger")

    applied = []
    skipped = []
    for item in sorted(manifest["migrations"], key=lambda row: row["version"]):
        version = item["version"]
        if not re.fullmatch(r"\d{14}", version):
            raise SystemExit(f"Unsafe migration version in artifact: {version!r}")
        if version in SKIPS:
            skipped.append({"version": version, "name": item["name"], "reason": SKIPS[version]})
            print(f"SKIP {version} {item['name']}: {SKIPS[version]}", flush=True)
            continue

        sql_file = (input_dir / item["file"]).resolve()
        if input_dir not in sql_file.parents or not sql_file.is_file():
            raise SystemExit(f"Missing or unsafe recovered SQL file: {item['file']}")
        print(f"APPLY {version} {item['name']}", flush=True)
        subprocess.run(
            [
                "psql", "-h", args.host, "-p", args.port, "-U", args.user,
                "-d", args.database, "-v", "ON_ERROR_STOP=1", "-f", str(sql_file),
            ],
            env=os.environ.copy(),
            check=True,
        )
        applied.append(version)

    summary = {
        "ledger_entries": len(manifest["migrations"]),
        "applied_to_disposable_postgres17": len(applied),
        "skipped_for_supabase_managed_dependencies": skipped,
        "warning": "Partial replay only. No Supabase production connection or data was used.",
    }
    print(json.dumps(summary, indent=2), flush=True)
    if len(applied) != 24 or len(skipped) != 2:
        raise SystemExit("Unexpected partial replay counts")


if __name__ == "__main__":
    main()
