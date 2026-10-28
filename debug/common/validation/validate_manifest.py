#!/usr/bin/env python3
"""Validate debug/tests/manifest.json against debug/schemas/test-manifest.schema.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path

DEBUG_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = DEBUG_ROOT / "tests" / "manifest.json"
DEFAULT_SCHEMA = DEBUG_ROOT / "schemas" / "test-manifest.schema.json"


def _load(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def validate(manifest_path=DEFAULT_MANIFEST, schema_path=DEFAULT_SCHEMA):
    manifest_path = Path(manifest_path)
    schema_path = Path(schema_path)
    try:
        manifest = _load(manifest_path)
        schema = _load(schema_path)
    except (OSError, json.JSONDecodeError) as exc:
        return [f"could not load input: {exc}"]

    # Prefer jsonschema when it is installed.
    try:
        import jsonschema  # type: ignore

        validator_cls = jsonschema.validators.validator_for(schema)
        validator = validator_cls(schema)
        return [f"{err.json_path}: {err.message}" for err in validator.iter_errors(manifest)]
    except ImportError:
        pass
    except Exception as exc:  # pragma: no cover - defensive
        return [f"jsonschema error: {exc}"]

    # Basic structural fallback mirroring the shipped schema.
    errors: list[str] = []
    if not isinstance(manifest, list):
        return ["$: expected array"]
    item_schema = schema.get("items", {}) if isinstance(schema.get("items"), dict) else {}
    required = item_schema.get("required", [])
    properties = item_schema.get("properties", {})
    for index, item in enumerate(manifest):
        if not isinstance(item, dict):
            errors.append(f"[{index}]: expected object")
            continue
        for key in required:
            if key not in item:
                errors.append(f"[{index}]: missing required '{key}'")
        for key, prop in properties.items():
            if key not in item:
                continue
            typ = prop.get("type")
            value = item[key]
            if typ == "string" and not isinstance(value, str):
                errors.append(f"[{index}].{key}: expected string")
            if "enum" in prop and value not in prop["enum"]:
                errors.append(f"[{index}].{key}: {value!r} not in {prop['enum']}")
    return errors


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    manifest_path = Path(argv[0]) if len(argv) > 0 else DEFAULT_MANIFEST
    schema_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_SCHEMA

    errors = validate(manifest_path, schema_path)
    if errors:
        for error in errors:
            print(error)
        print(f"validate_manifest: FAILED ({len(errors)} error(s))")
        return 1
    print("validate_manifest: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
