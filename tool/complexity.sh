#!/usr/bin/env bash
# Local cognitive-complexity gate (not run in CI). Extra args pass through:
#   tool/complexity.sh                                  # absolute ceilings
#   tool/complexity.sh -v                               # + per-function breakdown
#   tool/complexity.sh --git-diff=main --fail-on-increase   # budgeted ratchet vs main
set -euo pipefail
cd "$(dirname "$0")/.."
cc() { dart run cognitive_complexity@^2.0.1 "$@"; }
cc -f 15 -t 15 "$@" packages/datum/lib packages/datum_sqlite/lib packages/datum_hive/lib \
  packages/datum_generator/lib packages/datum_test/lib/src/local_sync_server.dart
cc -f 40 -t 40 "$@" packages/datum_test/lib # conformance suites are test code
