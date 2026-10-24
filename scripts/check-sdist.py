"""Local release validation. Never uploads; retains failed extractions and logs."""
import argparse
import atexit
import hashlib
from html.parser import HTMLParser
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
from urllib.parse import unquote, urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--archives", type=Path, help="validate existing archives instead of creating them")
parser.add_argument("--bounds", choices=["lower", "newest"], default="newest")
parser.add_argument("--output", type=Path, default=Path("dist-release"))
args = parser.parse_args()
checkout = Path(__file__).resolve().parent.parent
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
fresh = Path(tempfile.mkdtemp(prefix="heni-sdist-"))
print(f"Fresh extraction: {fresh}", flush=True)
checks = []


def retain_evidence():
    evidence = output / "evidence"
    evidence.mkdir(exist_ok=True)
    for pattern in ["*.log", "*-plan.json", "core-closure.json", "migration-results.json"]:
        for path in fresh.glob(pattern):
            shutil.copyfile(path, evidence / path.name)
    (evidence / "state.json").write_text(json.dumps({"extraction": str(fresh), "bounds": args.bounds, "checks": checks}, indent=2) + "\n")


atexit.register(retain_evidence)


def run(label, argv, cwd, env=None, expected=0):
    print(label, flush=True)
    start = time.monotonic()
    with (fresh / (label + ".log")).open("w") as log:
        result = subprocess.run(argv, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    checks.append({"check": label, "exit": result.returncode, "expected": expected, "seconds": time.monotonic() - start})
    assert result.returncode == expected, f"{label}: see {fresh / (label + '.log')}"


def project(path, packages):
    versions = {"base": "4.21.2.0", "text": "2.1.4", "containers": "0.7", "bytestring": "0.12.2.0", "directory": "1.3.10.1", "filepath": "1.5.5.0", "unix": "2.8.8.0", "process": "1.6.26.1", "crypton": "2.2.5", "aeson": "2.3.2.0", "stm": "2.5.3.1", "tasty": "1.5.5", "tasty-hunit": "0.10.2", "hspec": "2.11.18", "hspec-core": "2.11.18", "hspec-api": "2.11.18", "QuickCheck": "2.19.0.0"}
    if args.bounds == "newest":
        versions.update(containers="0.8.1", directory="1.3.11.0", process="1.6.30.0")
    constraints = ", ".join(name + " ==" + version for name, version in versions.items())
    policy = ""
    if os.environ.get("HENI_CI_WERROR") == "1":
        policy = "".join("package " + name + "\n  ghc-options: -Werror\n" for name in ["heni", "heni-cli", "heni-tasty", "heni-hspec"])
    path.write_text("packages: " + " ".join(packages) + "\nwrite-ghc-environment-files: never\nconstraints: " + constraints + "\n" + policy)


archives = args.archives.resolve() if args.archives else output
if not args.archives:
    run("sdist", ["cabal", "sdist", "all", "--output-directory", str(archives)], checkout)
names = ["heni", "heni-cli", "heni-tasty", "heni-hspec"]
hashes = {}
for name in names:
    archive = archives / (name + "-0.1.0.0.tar.gz")
    hashes[archive.name] = hashlib.sha256(archive.read_bytes()).hexdigest()
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            path = Path(member.name)
            assert not path.is_absolute() and ".." not in path.parts
            assert member.isfile() or member.isdir(), f"nonregular archive member: {member.name}"
        bundle.extractall(fresh)  # members were restricted to contained regular paths above
packages = {name: fresh / (name + "-0.1.0.0") for name in names}
for name, package in packages.items():
    for required in ["LICENSE", "CHANGELOG.md", name + ".cabal"]:
        assert (package / required).is_file(), (name, required)
    for path in package.rglob("*"):
        assert not path.is_symlink(), path
        if path.is_file():
            # Match an absolute reference, not a relative path whose suffix
            # happens to share the checkout basename (e.g. test/runner).
            reference = rb"(?<![A-Za-z0-9_.-])" + re.escape(str(checkout).encode()) + rb"(?:/|[\s\"'])"
            assert re.search(reference, path.read_bytes()) is None, f"checkout reference: {path}"
    run("check-" + name, ["cabal", "check"], package)
core = packages["heni"]
for required in ["schemas/manifest-v1.schema.json", "examples/minimal/src/Capacity.hs", "examples/standalone/target/heni.json", "test/process/Main.hs", "test/migration/Main.hs"]:
    assert (core / required).is_file(), required

# Construct a tool path explicitly, without enumerating the compiler store or
# inheriting Git, Nix, Mori, OKF, Python, or a consumer mutation runner.
tools = fresh / "core-tools"
tools.mkdir()
for command in "cabal ghc ghc-pkg runghc runhaskell hsc2hs cc gcc clang as ld ar ranlib strip libtool make sh pkg-config xcrun xcodebuild install tar gzip uname rm mkdir cp mv cat sed awk perl tr touch chmod sort cut head tail env readlink dirname basename pwd find ln getconf sw_vers xattr dsymutil otool nm lipo codesign expr echo grep date".split():
    found = shutil.which(command)
    if found:
        (tools / command).symlink_to(found)
minimal = os.environ.copy()
minimal["PATH"] = str(tools)
minimal.pop("HENI_REQUIRE_GIT", None)
minimal["HENI_SCHEMA_REPORT"] = str(fresh / "core-report.json")
minimal["HENI_SCHEMA_RESOURCE"] = str(fresh / "resource-report.json")
minimal["HENI_SCHEMA_EVIDENCE"] = str(fresh / "test-evidence.jsonl")
for command in ["git", "nix", "mori", "okf", "python3"]:
    assert shutil.which(command, path=minimal["PATH"]) is None

project(core / "cabal.project", ["."])
run("core-independent", ["cabal", "test", "all", "-j1", "--test-show-details=direct"], core, minimal)
plan = json.loads((core / "dist-newstyle/cache/plan.json").read_text())
nodes = {item["id"]: item for item in plan["install-plan"]}
reachable = set()


def visit(key):
    if key in reachable:
        return
    reachable.add(key)
    node = nodes[key]
    for dependency in node.get("depends", []) + node.get("exe-depends", []):
        visit(dependency)


for node in nodes.values():
    if node["pkg-name"] == "heni":
        visit(node["id"])
closure = {nodes[key]["pkg-name"] for key in reachable}
assert not closure.intersection({"heni-cli", "heni-tasty", "heni-hspec", "tasty", "hspec", "hspec-core"}), closure
# Released Aeson itself depends on QuickCheck; this is not a reporter dependency.
(fresh / "core-closure.json").write_text(json.dumps(sorted(closure), indent=2) + "\n")
shutil.copyfile(core / "dist-newstyle/cache/plan.json", fresh / "core-plan.json")
patch_env = os.environ.copy()
patch_env["HENI_REQUIRE_GIT"] = "1"
run("optional-git-patches", ["cabal", "test", "heni-workspace", "heni-runner", "-j1", "--test-show-details=direct"], core, patch_env)

cli = packages["heni-cli"]
project(cli / "cabal.project", [".", "../heni-0.1.0.0"])
run("cli-with-core-archive", ["cabal", "test", "heni-cli:heni-cli-test", "-j1", "--test-show-details=direct"], cli)
project(fresh / "cabal.project", [p.name for p in packages.values()])
run("optional-reporters", ["cabal", "test", "heni-tasty:heni-tasty-test", "heni-hspec:heni-hspec-test", "-j1", "--test-show-details=direct"], fresh)
run("haddock", ["cabal", "haddock", "all", "--haddock-for-hackage", "--haddock-executables", "-j1"], fresh)
text = (fresh / "haddock.log").read_text()
for line in text.splitlines():
    if "% (" in line and "in 'Test.Heni" in line:
        assert "100%" in line, line
for module in ["Test-Heni.html", "Test-Heni-Resource.html", "Test-Heni-Tasty.html", "Test-Heni-Hspec.html"]:
    assert list((fresh / "dist-newstyle").rglob(module)), module


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.links.extend(value for key, value in attrs if key == "href")


for page in (fresh / "dist-newstyle").rglob("Test-Heni*.html"):
    links = Links()
    links.feed(page.read_text())
    for href in links.links:
        parsed = urlsplit(href)
        path = unquote(parsed.path)
        if not parsed.scheme and (path.startswith("Test-Heni") or path.startswith("src/")):
            assert (page.parent / path).is_file(), (page, href)
schema_env = os.environ.copy()
schema_env["HENI_SCHEMA_EVIDENCE"] = str(fresh / "test-evidence.jsonl")
run("schema-agreement", [os.environ.get("HENI_SCHEMA_PYTHON", "python3"), str(core / "scripts/check-schemas.py"), "--corpus", str(cli / "test/corpus"), str(fresh / "core-report.json"), str(fresh / "resource-report.json")], fresh, schema_env)

binary = subprocess.check_output(["cabal", "list-bin", "heni-cli:exe:heni"], cwd=fresh, text=True).strip()
run("version-without-git", [binary, "--version"], fresh, minimal)
run("help", [binary, "--help"], fresh)
consumer = fresh / "consumer"
shutil.copytree(core / "examples/standalone", consumer)
project(consumer / "cabal.project", [".", "../heni-0.1.0.0"])
run("standalone-library", ["cabal", "run", "consumer", "-j1"], consumer, minimal)
for case, exit_code, verdict in [("caught", 0, "caught"), ("survivor", 1, "survived"), ("wrong", 1, "wrong-failure")]:
    destination = consumer / ("cli-" + case)
    run("standalone-cli-" + case, [binary, "run", "target/heni.json", "--case", case, "--output", str(destination), "--json"], consumer, minimal, exit_code)
    report = json.loads((destination / "report.json").read_text())
    assert report["result"]["cases"][0]["verdict"] == verdict
run("standalone-config-exit", [binary, "run", "target/heni.json", "--case", "absent"], consumer, minimal, 2)
migration_env = os.environ.copy()
migration_env["HENI_CLI_EXE"] = binary
migration_env["HENI_MIGRATION_RESULTS"] = str(fresh / "migration-results.json")
run("migration-archives", ["cabal", "test", "heni:heni-migration", "-f", "migration-tests", "-j1", "--test-show-details=direct"], fresh, migration_env)
shutil.copyfile(fresh / "dist-newstyle/cache/plan.json", fresh / "combined-plan.json")
for filename in ["core-plan.json", "combined-plan.json"]:
    for item in json.loads((fresh / filename).read_text())["install-plan"]:
        source = item.get("pkg-src", {})
        if source.get("type") == "local":
            assert Path(source["path"]).resolve().is_relative_to(fresh.resolve()), source
        else:
            assert not source or source.get("type") == "repo-tar", source
for archive in (fresh / "dist-newstyle").rglob("*-docs.tar.gz"):
    shutil.copyfile(archive, output / archive.name)
    hashes[archive.name] = hashlib.sha256(archive.read_bytes()).hexdigest()
summary = {"bounds": args.bounds, "extraction": str(fresh), "archives": hashes, "compiler": subprocess.check_output(["ghc", "--numeric-version"], text=True).strip(), "cabal": subprocess.check_output(["cabal", "--numeric-version"], text=True).strip(), "checks": checks}
(output / "archive-validation.json").write_text(json.dumps(summary, indent=2) + "\n")
print(f"Archive validation passed; evidence: {output / 'archive-validation.json'}", flush=True)
