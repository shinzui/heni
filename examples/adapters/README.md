# Framework examples

The fixture executables are built in the optional packages. Add their executable
directories to PATH (obtain paths using `cabal list-bin heni-tasty-fixture` and
`cabal list-bin heni-hspec-fixture`), then run `heni run examples/adapters/tasty.json`,
`heni run examples/adapters/hspec.json`, or `heni run examples/adapters/property.json`.
The fixtures use the same reporter installation a consumer test main uses.
See [adapter contracts](../../docs/design/adapters.md) for identity and selector rules.
