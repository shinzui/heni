# One campaign ledger and portable evidence

Status: accepted. Date: 2026-10-24.

The library owns the complete baseline/edit/build/test/classify lifecycle and
the selected-ID ledger. CLI and optional framework paths consume it. Baseline
and candidate configuration must match; failed baselines never produce mutant
kills. Only a successful build permits semantic tests. Checked hooks may enrich
evidence but cannot override actual outcome, timeout, diagnostic, source-change
or cleanup validity. Every external stage, including Git, uses the supervisor.

Write a sequenced ledger snapshot before work and after meaningful observations;
finalize summaries by atomic rename. Include baseline/patch evidence separately
from candidate classification inputs, retain secondary cleanup/report errors,
and fill all queued IDs on interruption. Recovery is read-only and explicitly
untrustworthy; a journal is evidence, not permission to resume commands.

Use explicit versioned codecs and relative artifact paths. Reject duplicate JSON
keys before map conversion, and reject malformed ledgers and escaping/missing
artifacts when reading. Preserve exact witnesses independently of bounded logs.
Reports redact environment values and explicitly sensitive argv indexes without
claiming complete secret-bearing reproducibility. Consumers own what their
commands emit. Atomic rename does not promise durability when storage refuses IO.

The cost of full ledger snapshots is larger journals. The initial serial runner
chooses inspectable recovery and fresh workspace isolation before optimizing
scheduling or reuse. Later scheduling must preserve these accounting invariants.
