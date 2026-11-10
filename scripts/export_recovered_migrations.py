#!/usr/bin/env python3
"""Export captured production migration SQL to a temporary, non-runnable audit artifact.

This script never writes into supabase/migrations and never connects to Supabase.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/audits/supabase-production-migration-ledger-2026-11-10.json"
MIGRATIONS = ROOT / "supabase/migrations"


def normalize_sql(sql: str) -> str:
    sql = re.sub(r"/\*[\s\S]*?\*/", " ", sql)
    sql = re.sub(r"--[^\n]*", " ", sql)
    sql = re.sub(r"^\s*begin\s*;", "", sql, flags=re.I)
    sql = re.sub(r";\s*commit\s*;?\s*$", ";", sql, flags=re.I)
    return re.sub(r"\s+", " ", sql).strip().lower()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True, help="Temporary artifact directory outside supabase/migrations")
    args = parser.parse_args()

    ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
    versions = [row["version"] for row in ledger]
    if len(versions) != len(set(versions)):
        raise SystemExit("Duplicate versions in production migration ledger")

    output = Path(args.output_dir).resolve()
    if output == MIGRATIONS.resolve() or MIGRATIONS.resolve() in output.parents:
        raise SystemExit("Refusing to write recovered SQL inside supabase/migrations")
    output.mkdir(parents=True, exist_ok=True)

    repo_files = sorted(MIGRATIONS.glob("*.sql"))
    repo_by_version = {}
    for path in repo_files:
        match = re.match(r"^(\d{14})_", path.name)
        if match:
            repo_by_version.setdefault(match.group(1), []).append(path)

    applied_normalized = {
        row["version"]: normalize_sql("\n".join(row.get("statements", [])))
        for row in ledger
    }
    manifest = []
    classifications = {
        "same_version_exact": [],
        "same_version_content_drift": [],
        "content_match_timestamp_drift": [],
        "missing_repository_file": [],
        "repository_only_file": [],
    }

    for row in ledger:
        version, name = row["version"], row["name"]
        statements = row.get("statements") or []
        if not re.fullmatch(r"\d{14}", version) or not re.fullmatch(r"[a-zA-Z0-9_]+", name):
            raise SystemExit(f"Unsafe ledger filename fields: {version!r} {name!r}")
        if len(statements) != 1 or not statements[0].strip():
            raise SystemExit(f"Unexpected SQL statement structure for {version} {name}")
        sql = statements[0].strip() + "\n"
        filename = f"{version}_{name}.sql"
        target = output / filename
        target.write_text(sql, encoding="utf-8")
        digest = hashlib.sha256(sql.encode("utf-8")).hexdigest()
        normalized = normalize_sql(sql)

        same_version = repo_by_version.get(version, [])
        if same_version:
            if len(same_version) != 1:
                classification = "same_version_content_drift"
                classifications[classification].append(version)
            elif normalize_sql(same_version[0].read_text(encoding="utf-8")) == normalized:
                classification = "same_version_exact"
                classifications[classification].append(version)
            else:
                classification = "same_version_content_drift"
                classifications[classification].append(version)
        else:
            other_matches = [
                v for v, content in applied_normalized.items()
                if v != version and content == normalized
            ]
            if other_matches:
                classification = "content_match_timestamp_drift"
                classifications[classification].append({"version": version, "matches": other_matches})
            else:
                classification = "missing_repository_file"
                classifications[classification].append(version)

        manifest.append({
            "version": version,
            "name": name,
            "file": filename,
            "sha256": digest,
            "classification": classification,
        })

    ledger_versions = set(versions)
    for path in repo_files:
        match = re.match(r"^(\d{14})_", path.name)
        if match and match.group(1) not in ledger_versions:
            classifications["repository_only_file"].append(path.name)

    payload = {
        "source": "captured Supabase production migration ledger",
        "warning": "FORENSIC AUDIT ARTIFACT ONLY — DO NOT RUN OR COPY INTO supabase/migrations",
        "migration_count": len(manifest),
        "repository_migration_file_count": len(repo_files),
        "classifications": classifications,
        "migrations": manifest,
    }
    (output / "manifest.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "exported_migrations": len(manifest),
        "repository_migration_files": len(repo_files),
        "classifications": {key: len(value) for key, value in classifications.items()},
        "artifact_directory": str(output),
        "warning": payload["warning"],
    }, indent=2))


if __name__ == "__main__":
    main()
