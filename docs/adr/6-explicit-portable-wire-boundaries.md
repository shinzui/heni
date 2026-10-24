# Explicit portable input and thin CLI

Status: accepted. Date: 2026-10-24.

Versioned JSON manifests lower into the same validated Campaign as Haskell
definitions. The CLI owns arguments, rendering and exit mapping, while the
library owns applicability, execution, classification and report reading.
Reject unsupported versions, unknown/duplicate keys, invalid references and
unsupported hooks before execution. Defaults apply only to missing nonnullable
fields, not explicit nulls. JSON Schema describes shape; the decoder additionally
checks semantic relationships that schema cannot express.

Anchor source paths to the manifest file. Keep explicit caller-relative output
paths deliberate and document their different role. Repeat filters by union
within each kind and intersection between case/tag kinds, retaining author
order. Empty selection is an error. Check/list/report never imply a baseline
or execute mutation tests. Recovery is read-only. New adapter/resource syntax
must wait for real execution support rather than silently doing nothing.

Machine output remains clean JSON; observation and errors use stderr. Human
color follows terminal detection by default. Package version identity comes
from Cabal archives without Git. These boundaries follow the small applicable
parts of mori://shinzui/haskell-jitsurei/docs/cli-overview and preserve the
library-owned behavior established in docs/adr/1-framework-neutral-core.md.
