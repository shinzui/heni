# heni-cli

The `heni` executable validates manifests, lists cases, runs mutation campaigns
and renders stored reports through the matching Heni library. Version 0.1.0.0 is
unreleased. Use `heni --help` and the [CLI reference](https://github.com/shinzui/heni/blob/master/docs/cli.md).

`run` exits 0 for a met trustworthy contract, 1 for a failed contract, 2 for
configuration/infrastructure failure, and 130 after SIGINT finalization. Generic
commands need exact diagnostic/exit evidence; optional reporters provide named
assertion evidence. Use fresh output directories; report artifacts move together.
