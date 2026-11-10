#!/usr/bin/env python3
"""Export captured production migration SQL to a temporary, non-runnable audit artifact.

This script never writes into supabase/migrations and never connects to Supabase.
Exact text, normalized text, and timestamp drift are reported separately.
None of these classifications alone proves safe replay or semantic equivalence.
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
    repo_contents = {}
    for path in repo_files:
        raw = path.read_text(encoding="utf-8").strip()
        repo_contents[path] = raw
        match = re.match(r"^(\d{14})_", path.name)
        if match:
            repo_by_version.setdefault(match.group(1), []).append(path)

    manifest = []
    classifications = {
        "same_version_exact": [],
        "same_version_normalized_only": [],
        "same_version_content_drift": [],
        "timestamp_drift_exact": [],
        "timestamp_drift_normalized_only": [],
        "no_repository_content_match": [],
        "repository_only_timestamp_drift_exact": [],
        "repository_only_timestamp_drift_normalized": [],
        "unmatched_repository_only_file": [],
    }

    for row in ledger:
        version, name = row["version"], row["name"]
        statements = row.get("statements") or []
        if not re.fullmatch(r"\d{14}", version) or not re.fullmatch(r"[a-zA-Z0-9_]+", name):
            raise SystemExit(f"Unsafe ledger filename fields: {version!r} {name!r}")
        if len(statements) != 1 or not statements[0].strip():
            raise SystemExit(f"Unexpected SQL statement structure for {version} {name}")

        sql = statements[0].strip()
        normalized = normalize_sql(sql)
        filename = f"{version}_{name}.sql"
        (output / filename).write_text(sql + "\n", encoding="utf-8")
        digest = hashlib.sha256((sql + "\n").encode("utf-8")).hexdigest()

        same_version = repo_by_version.get(version, [])
        same_name = same_version[0].name if len(same_version) == 1 else None
        same_raw = repo_contents[same_version[0]] if len(same_version) == 1 else None
        exact_timestamp_matches = [
            path.name for path, raw in repo_contents.items()
            if path.name.split("_", 1)[0] != version and raw == sql
        ]
        normalized_timestamp_matches = [
            path.name for path, raw in repo_contents.items()
            if path.name.split("_", 1)[0] != version and normalize_sql(raw) == normalized
        ]

        if len(same_version) > 1:
            classification = "same_version_content_drift"
            classifications[classification].append(version)
        elif len(same_version) == 1 and same_raw == sql:
            classification = "same_version_exact"
            classifications[classification].append(version)
        elif len(same_version) == 1 and normalize_sql(same_raw) == normalized:
            classification = "same_version_normalized_only"
            classifications[classification].append(version)
        elif len(same_version) == 1:
            classification = "same_version_content_drift"
            classifications[classification].append(version)
        elif exact_timestamp_matches:
            classification = "timestamp_drift_exact"
            classifications[classification].append({
                "applied_version": version, "applied_name": name,
                "repository_files": exact_timestamp_matches,
            })
        elif normalized_timestamp_matches:
            classification = "timestamp_drift_normalized_only"
            classifications[classification].append({
                "applied_version": version, "applied_name": name,
                "repository_files": normalized_timestamp_matches,
            })
        else:
            classification = "no_repository_content_match"
            classifications[classification].append(version)

        manifest.append({
            "version": version,
            "name": name,
            "file": filename,
            "sha256": digest,
            "classification": classification,
            "repository_file_same_version": same_name,
            "timestamp_drift_exact_matches": exact_timestamp_matches,
            "timestamp_drift_normalized_matches": normalized_timestamp_matches,
        })

    ledger_versions = set(versions)
    for path, raw in repo_contents.items():
        match = re.match(r"^(\d{14})_", path.name)
        if not match or match.group(1) in ledger_versions:
            continue
        exact_matches = [
            {"version": row["version"], "name": row["name"]}
            for row in ledger if raw == row["statements"][0].strip()
        ]
        normalized_matches = [
            {"version": row["version"], "name": row["name"]}
            for row in ledger if normalize_sql(raw) == normalize_sql(row["statements"][0])
        ]
        if exact_matches:
            classifications["repository_only_timestamp_drift_exact"].append({
                "file": path.name, "matches": exact_matches,
            })
        elif normalized_matches:
            classifications["repository_only_timestamp_drift_normalized"].append({
                "file": path.name, "matches": normalized_matches,
            })
        else:
            classifications["unmatched_repository_only_file"].append(path.name)

    payload = {
        "source": "captured Supabase production migration ledger",
        "warning": "FORENSIC AUDIT ARTIFACT ONLY — DO NOT RUN OR COPY INTO supabase/migrations",
        "interpretation": "Exact and normalized text matches are content evidence only; normalized matches and timestamp drift do not prove semantic equivalence or safe replay.",
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
