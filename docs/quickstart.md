# First caught mutation and survivor

Use GHC 9.12.4 and Cabal with released dependencies. From this checkout, build
the packages normally; Nix and repository indexing tools are optional developer
tooling. Heni is currently unreleased, so Hackage installation is a later step.

First observe the unchanged target passing:

```bash
cd examples/minimal
cabal test fixture-test --offline -j1 --test-show-details=direct
cd ../..
```

Then check the manifest's structure and edit applicability. This command does
not run tests or discovery:

```bash
cabal run heni-cli:exe:heni -- check examples/minimal/heni.json
```

Run one capacity-guard mutation. Heni first builds/tests the unchanged snapshot,
then edits and tests a separate disposable copy:

```bash
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case guard-bypass --output .heni-runs/quickstart-caught
```

Expect `caught` and exit 0, with the precise full-capacity assertion diagnostic.
The report and logs are under the chosen output directory. A harmless marker
change demonstrates a survivor:

```bash
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case survivor --output .heni-runs/quickstart-survivor
```

Expect `survived` and exit 1. A survivor means the valid change was not detected;
it does not establish equivalence. Use fresh output paths when repeating these
commands. `heni report PATH/report.json` renders evidence without rerunning it.

For Haskell, [Definitions.hs](../examples/library/Definitions.hs) shows short
case definitions and [Main.hs](../examples/library/Main.hs) calls the same
`runCampaign` API. Construct options with `defaultRunOptions` and update named
fields. The library returns `RunResult` and leaves application exits/rendering
to the caller:

```bash
cabal run heni:exe:heni-library-example -- --output .heni-runs/quickstart-library
```

That example returns caught, survivor and unrelated compiler-failure evidence.
See [CLI usage](cli.md), [migration patterns](migration-guide.md),
[named adapters and replay](design/adapters.md), and
[resource ownership](design/scheduling.md) for stronger integrations.
