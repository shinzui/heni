"""Validate published JSON Schemas and real emitted fixtures (development only)."""
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator

root = Path(__file__).resolve().parent.parent

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
for path in (root / "heni-cli/test/corpus").glob("*.json"):
    try:
        value = json.loads(path.read_text(), object_pairs_hook=unique_object)
        valid = manifest_validator.is_valid(value)
    except ValueError:
        valid = False
    assert valid == path.name.startswith("valid-"), path.name
manifest_validator.validate(json.loads((root / "examples/minimal/heni.json").read_text()))
schema = json.loads((root / "schemas/report-v1.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)
for argument in sys.argv[1:]:
    value = json.loads(Path(argument).read_text())
    validator.validate(value)
    invalid = dict(value, schemaVersion=999)
    assert not validator.is_valid(invalid), "unknown report version accepted"
    invalid = dict(value, unexpected=True)
    assert not validator.is_valid(invalid), "unknown report field accepted"
print("Manifest corpus, report schema and emitted fixtures passed")
