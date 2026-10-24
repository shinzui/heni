#!/bin/sh
set -eu
# Explicit cross-package validation; the core package does not depend on CLI.
cabal build heni-cli:exe:heni -j1
HENI_CLI_EXE=$(cabal list-bin heni-cli:exe:heni)
HENI_MIGRATION_RESULTS=${HENI_MIGRATION_RESULTS:-"$(pwd)/.heni-runs/migration-results.json"}
export HENI_CLI_EXE HENI_MIGRATION_RESULTS
cabal test heni:heni-migration -f migration-tests -j1 --test-show-details=direct "$@"
