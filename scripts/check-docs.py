"""Development-only checks for OKF profiles, indexes, links, and evidence paths.

Run from any directory with Python 3, OKF >=0.9.0.0, Dhall, and Git available.
This command does not execute campaigns or modify the source bundles.
"""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit


root = Path(__file__).resolve().parent.parent
bundles = [Path("docs/capabilities"), Path("docs/user")]
errors = []


def run(argv):
    return subprocess.check_output(argv, cwd=root, text=True)


def markdown_links(text):
    # Ignore example code when checking actual inline Markdown navigation.
    prose = re.sub(r"(?ms)^```[^\n]*\n.*?^```[^\n]*$", "", text)
    return re.findall(r"!?\[[^\]]*\]\(([^\s)]+)\)", prose)


concepts = {}
for bundle in bundles:
    print(f"Checking {bundle}", flush=True)
    subprocess.run(
        ["okf", "validate", str(bundle), "--strict", "--profile",
         str(bundle / "profile.dhall"), "--profile-enforce", "--log-enforce"],
        cwd=root, check=True,
    )
    concepts[bundle] = json.loads(run(["okf", "concepts", str(bundle), "--json"]))
    # Generate into a disposable copy so a stale index fails without fixing it.
    with tempfile.TemporaryDirectory(prefix="heni-doc-index-") as temporary:
        copy = Path(temporary) / "bundle"
        shutil.copytree(root / bundle, copy)
        run(["okf", "index", str(copy), "--write"])
        for index in copy.rglob("index.md"):
            original = root / bundle / index.relative_to(copy)
            if not original.is_file() or original.read_bytes() != index.read_bytes():
                errors.append(f"{original.relative_to(root)}: stale generated index; run okf index {bundle} --write")

paths = run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.md"]).splitlines()
for relative in sorted(set(paths)):
    page = root / relative
    if not page.is_file():
        continue  # Deleted locations in a documentation move remain in the index.
    for target in markdown_links(page.read_text()):
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        destination = (page.parent / unquote(parsed.path)).resolve()
        if not destination.is_relative_to(root) or not destination.exists():
            errors.append(f"{relative}: missing or escaping Markdown target {target}")

for bundle, records in concepts.items():
    for record in records:
        ident = record.get("capabilityId", record.get("docId"))
        for field in ["evidence", "sources"]:
            for item in record.get(field, []):
                resource = item["resource"]
                if urlsplit(resource).scheme:
                    continue
                path = (root / resource).resolve()
                if not path.is_relative_to(root) or not path.is_file():
                    errors.append(f"{ident}: missing or escaping {field} resource {resource}")

capability_pages = {}
for page in (root / "docs/capabilities").glob("*.md"):
    match = re.search(r"(?m)^capabilityId: (CAP-[0-9]+)$", page.read_text())
    if match:
        capability_pages[match[1]] = page
for record in concepts[Path("docs/capabilities")]:
    page = capability_pages[record["capabilityId"]]
    targets = {
        (page.parent / urlsplit(target).path).resolve()
        for target in markdown_links(page.read_text())
        if not urlsplit(target).scheme
    }
    for requirement in record.get("requires", []):
        if requirement.startswith("mori:"):
            if requirement not in markdown_links(page.read_text()):
                errors.append(f"{record['capabilityId']}: mirror requires {requirement} as a body link")
        elif capability_pages[requirement].resolve() not in targets:
            errors.append(f"{record['capabilityId']}: mirror requires {requirement} as a body link")

if errors:
    raise SystemExit("\n".join(errors))
print("Documentation checks passed: profiles, logs, indexes, Markdown links, evidence, and capability dependency links.")
