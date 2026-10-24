"""Validate published JSON Schemas and real emitted fixtures (development only)."""
import argparse
import json
import sys
import os
from pathlib import Path
from jsonschema import Draft202012Validator

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--corpus", type=Path, default=root / "heni-cli/test/corpus")
parser.add_argument("reports", nargs="*")
args = parser.parse_args()
assert args.corpus.is_dir(), "supply --corpus from the extracted heni-cli archive"
assert list(args.corpus.glob("*.json")), "manifest corpus is empty"

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result

manifest_schema = json.loads((root / "schemas/manifest-v1.schema.json").read_text())
Draft202012Validator.check_schema(manifest_schema)
manifest_validator = Draft202012Validator(manifest_schema)
for path in args.corpus.glob("*.json"):
    try:
        value = json.loads(path.read_text(), object_pairs_hook=unique_object)
        valid = manifest_validator.is_valid(value)
    except ValueError:
        valid = False
    assert valid == path.name.startswith("valid-"), path.name
manifest_validator.validate(json.loads((root / "examples/minimal/heni.json").read_text()))
manifest_validator.validate(json.loads((root / "examples/standalone/target/heni.json").read_text()))
for path in (root / "examples/adapters").glob("*.json"):
    manifest_validator.validate(json.loads(path.read_text()))
for path in (root / "examples/migrations").glob("*/heni.json"):
    manifest_validator.validate(json.loads(path.read_text()))
schema = json.loads((root / "schemas/report-v1.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)
for argument in args.reports:
    value = json.loads(Path(argument).read_text())
    validator.validate(value)
    invalid = dict(value, schemaVersion=999)
    assert not validator.is_valid(invalid), "unknown report version accepted"
    invalid = dict(value, unexpected=True)
    assert not validator.is_valid(invalid), "unknown report field accepted"
print("Manifest corpus, report schema and emitted fixtures passed")

evidence_schema = json.loads((root / "schemas/test-evidence-v1.schema.json").read_text())
Draft202012Validator.check_schema(evidence_schema)
evidence_validator = Draft202012Validator(evidence_schema)
if os.environ.get("HENI_SCHEMA_EVIDENCE"):
    for line in Path(os.environ["HENI_SCHEMA_EVIDENCE"]).read_text().splitlines():
        evidence_validator.validate(json.loads(line, object_pairs_hook=unique_object))
    print("Emitted test evidence schema passed")
