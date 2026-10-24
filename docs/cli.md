# CLI quickstart

Build with ordinary Cabal and run from this checkout:

```sh
cabal build heni-cli:exe:heni
cabal run heni-cli:exe:heni -- check examples/minimal/heni.json
cabal run heni-cli:exe:heni -- list examples/minimal/heni.json
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case guard-bypass --output .heni-runs/cli-example
cabal run heni-cli:exe:heni -- report .heni-runs/cli-example/report.json
```

Use a new output directory each time. The selected guard mutation is caught;
the example's survivor and unrelated compile-error cases deliberately fail the
contract. `check` checks structure, command availability and edit applicability
in disposable copies. It does not run builds, tests, discovery or baselines.
`list` reads definitions without launching commands. `report` only reads stored
evidence. `report DIRECTORY --recover` reconstructs an explicitly incomplete
journal snapshot without executing or resuming anything.

Manifest source roots are relative to the manifest's directory, defaulting to
`.`; mutation targets and command working directories are relative to the
snapshot root. An explicit CLI `--output` path is relative to the caller's
directory. Without it, output is SOURCE/mutation-results, a default excluded
name. A custom nested output location must be excluded from source capture.

Repeat `--case` and `--tag` freely. Values within each kind form a union; the
case and tag sets are intersected. Selection retains author order. Unknown
explicit IDs and empty intersections fail before execution. The current
default is serial fresh-copy execution. `--jobs N` selects 1–256 workers and
overrides manifest `execution.workers`; resource capacities still apply.

`run` exits 0 only when the library reports a trustworthy met contract, 1 for
contract failure, and 2 for configuration or infrastructure failure. SIGINT
exits 130 after partial evidence finalization. `check` exits 2 when applicability
or configuration fails. `list` and successful `report` rendering exit 0 even
when the rendered run failed; use `run` for the CI gate.

All commands support `--json`, with JSON on stdout and progress/errors on stderr.
Run JSON contains schemaVersion, reportPath, selectionRule and the library result.
Report JSON is the full stored report envelope. Human output includes verdict
counts, unresolved cases, witnesses and separate run failures. `--color auto`
uses ANSI only on a terminal; `always` and `never` override human output, while
machine JSON remains uncolored. `--version` comes from the Cabal package and
works without Git. Shell wrappers can use the installed `heni` executable;
Python callers should invoke argv and inspect its exit/JSON instead of rebuilding
mutation orchestration.

Version-one manifests reject unknown keys at every level, unsupported versions,
duplicate object keys, unsafe targets, bad budgets, duplicate IDs and unknown
references. Missing timeoutSeconds defaults to 30; outputLimitBytes defaults to
1048576 per stream; arguments, sensitiveArguments and tags default to empty;
replacement occurrences defaults to exactly one. Explicit null is accepted only
for nullable fields such as selector, test and workingDirectory. Effective
microsecond budgets and output limits appear in reports. Command environment
values are redacted; sensitiveArguments lists zero-based argv indexes to redact.

The [manifest schema](../schemas/manifest-v1.schema.json) defines wire shape;
the decoder also checks semantic references and edit/expectation constraints.
Generic diagnostics, intentional build rejection, unchanged controls, named-test
protocol adapters, required replay and attempt-bound crash probes are supported.
Custom Haskell functions and build-tool observation verifiers cannot be serialized.
Scoped resource commands and baseline reuse use the shared runner. Unsupported features never silently
fall back to ordinary diagnostic matching.

Named-test adapters, required replay and explicit crash probes are described in
[adapter contracts](design/adapters.md), with runnable manifests in examples/adapters.

See [scheduling and resource contracts](design/scheduling.md) for portable resource
claims, baseline reuse identities, external reset obligations and build-job budgets.
