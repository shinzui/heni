"""Validate published JSON Schemas and real emitted fixtures (development only)."""
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator

root = Path(__file__).resolve().parent.parent
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
print("Report schema and emitted fixtures passed")
