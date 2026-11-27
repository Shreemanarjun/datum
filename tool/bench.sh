#!/usr/bin/env bash
# Pure-Dart benchmarks for datum, datum_sqlite and datum_hive, JIT and AOT.
#
#   tool/bench.sh                    # working tree, runs 3,10
#   RUNS=3,5,10 tool/bench.sh main   # also benchmark git ref `main` (baseline)
#   PKGS=datum tool/bench.sh main     # only some packages (space-separated)
#
# Each ref is checked out into a temporary worktree; the current benchmark
# sources and pubspec.lock are copied in, so old code is measured with
# today's harness and dependency versions.
# Packages that are not pure Dart at a ref (datum_hive before hive_ce) are
# skipped there. Output is markdown on stdout.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNS=${RUNS:-3,10}
PKGS=${PKGS:-datum datum_sqlite datum_hive}
TMP=$(mktemp -d)
trap 'for w in "$TMP"/wt_*; do [ -d "$w" ] && git -C "$ROOT" worktree remove --force "$w"; done; rm -rf "$TMP"' EXIT

BENCHES=(
  "datum benchmark/sync_benchmark.dart"
  "datum_sqlite benchmark/sqlite_benchmark.dart"
  "datum_hive benchmark/hive_benchmark.dart"
)

run_tree() { # <tree root> <label>
  local tree=$1 label=$2
  echo; echo "## $label"
  (cd "$tree" && dart pub get >/dev/null)
  (cd "$tree/packages/datum_hive" && dart pub get >/dev/null 2>&1) || true
  for entry in "${BENCHES[@]}"; do
    read -r pkg file <<<"$entry"
    [[ " $PKGS " == *" $pkg "* ]] || continue
    local dir="$tree/packages/$pkg"
    if grep -q "hive_ce_flutter" "$dir/pubspec.yaml"; then
      echo; echo "_${pkg}: skipped — not pure Dart at this ref_"; continue
    fi
    (cd "$dir" && dart run "$file" --runs "$RUNS" | grep -v '^$') || echo "_${pkg} JIT failed_"
    local exe="$TMP/${label//[^a-zA-Z0-9]/_}_$pkg"
    (cd "$dir" && dart compile exe -o "$exe" "$file" >/dev/null && "$exe" --runs "$RUNS" | grep -v '^$') || echo "_${pkg} AOT failed_"
  done
}

run_tree "$ROOT" "working tree"
for ref in "$@"; do
  wt="$TMP/wt_$ref"
  git -C "$ROOT" worktree add -q --detach "$wt" "$ref"
  for entry in "${BENCHES[@]}"; do
    read -r pkg file <<<"$entry"
    mkdir -p "$wt/packages/$pkg/benchmark"
    cp "$ROOT/packages/$pkg/$file" "$wt/packages/$pkg/$file"
  done
  cp "$ROOT/packages/datum_test/lib/src/bench.dart" "$wt/packages/datum_test/lib/src/bench.dart"
  # Same dependency versions as the working tree (the lock file is not in
  # git): otherwise a ref is measured with whatever resolves today.
  cp "$ROOT/pubspec.lock" "$wt/pubspec.lock" 2>/dev/null || true
  run_tree "$wt" "$ref"
done
