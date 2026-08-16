#!/usr/bin/env bash
#
# Datum ecosystem release driver.
#
#   tool/release.sh              # check versions + run tests + dry-run everything
#   tool/release.sh --skip-tests # check versions + dry-run only
#   tool/release.sh --publish    # all checks, then publish for real (in order)
#
# Publish order respects the dependency graph and waits for pub.dev to serve
# each package before publishing its dependents.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES=(datum datum_generator datum_test datum_sqlite datum_hive)

PUBLISH=false
SKIP_TESTS=false
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    *) echo "unknown flag: $arg (use --publish and/or --skip-tests)"; exit 2 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }

pubspec_version() {
  grep '^version:' "$ROOT/packages/$1/pubspec.yaml" | awk '{print $2}'
}

changelog_head() {
  grep -m1 -E '^#+ ' "$ROOT/packages/$1/CHANGELOG.md" | sed -E 's/^#+ //'
}

# ---------------------------------------------------------------- versions --
bold "1/4 Version sync"
VERSION="$(pubspec_version datum)"
[ -n "$VERSION" ] || fail "could not read datum's version"
for p in "${PACKAGES[@]}"; do
  v="$(pubspec_version "$p")"
  [ "$v" = "$VERSION" ] || fail "$p is $v, expected $VERSION — versions must be synced"
  head="$(changelog_head "$p")"
  [ "$head" = "$VERSION" ] || fail "$p CHANGELOG top section is '$head', expected '$VERSION'"
  [ -f "$ROOT/packages/$p/LICENSE" ] || fail "$p is missing a LICENSE file"
  [ -f "$ROOT/packages/$p/README.md" ] || fail "$p is missing a README.md"
done
# Dependents must accept the synced version.
for p in datum_generator datum_test datum_sqlite datum_hive; do
  constraint="$(grep -E '^  datum: ' "$ROOT/packages/$p/pubspec.yaml" | awk '{print $2}' || true)"
  if [ -n "$constraint" ] && [ "$constraint" != "^$VERSION" ]; then
    fail "$p depends on 'datum: $constraint', expected '^$VERSION'"
  fi
done
ok "all packages at $VERSION with matching changelogs, LICENSE, README"

# ------------------------------------------------------------------- tests --
if $SKIP_TESTS; then
  bold "2/4 Tests — skipped (--skip-tests)"
else
  bold "2/4 Tests"
  (cd "$ROOT" && flutter pub get >/dev/null)
  for p in "${PACKAGES[@]}"; do
    if [ "$p" = "datum_generator" ]; then
      # Pure-Dart build_runner tests can't run under `flutter test`
      # (Isolate.resolvePackageUri); CI analyzes this package instead.
      (cd "$ROOT/packages/$p" && dart analyze >/dev/null) || fail "$p analyze failed"
      ok "$p (analyze)"
    else
      (cd "$ROOT/packages/$p" && flutter test >/dev/null 2>&1) || fail "$p tests failed"
      ok "$p tests"
    fi
  done
fi

# ---------------------------------------------------------------- dry runs --
bold "3/4 Publish dry-runs"
for p in "${PACKAGES[@]}"; do
  out="$(cd "$ROOT/packages/$p" && flutter pub publish --dry-run 2>&1 || true)"
  if echo "$out" | grep -qE "Package validation found the following( [0-9]+)? error|Sorry, your package"; then
    echo "$out" | tail -20
    fail "$p dry-run reported errors"
  fi
  warnings="$(echo "$out" | grep -oE 'Package has [0-9]+ warning' | grep -oE '[0-9]+' || echo 0)"
  # Uncommitted-file warnings are expected until the release commit exists;
  # anything else must be inspected.
  if [ "${warnings:-0}" != "0" ] && ! echo "$out" | grep -q "Consider committing these files"; then
    echo "$out" | tail -20
    fail "$p dry-run has non-git warnings"
  fi
  ok "$p dry-run"
done

# ----------------------------------------------------------------- publish --
if ! $PUBLISH; then
  bold "4/4 Publish — skipped (pass --publish to release for real)"
  echo "Release candidate $VERSION is ready."
  exit 0
fi

bold "4/4 Publishing $VERSION"
if [ -n "$(cd "$ROOT" && git status --porcelain)" ]; then
  fail "working tree is dirty — commit the release changes first"
fi

wait_for_pub_dev() { # package version
  local p="$1" v="$2"
  for _ in $(seq 1 30); do
    if curl -sf "https://pub.dev/api/packages/$p" | grep -q "\"version\":\"$v\""; then
      return 0
    fi
    echo "  waiting for $p $v to appear on pub.dev..."
    sleep 10
  done
  fail "$p $v never appeared on pub.dev"
}

for p in "${PACKAGES[@]}"; do
  bold "Publishing $p $VERSION"
  (cd "$ROOT/packages/$p" && flutter pub publish --force) || fail "$p publish failed"
  # Dependents can't resolve until pub.dev serves this version.
  wait_for_pub_dev "$p" "$VERSION"
  ok "$p $VERSION is live"
done

ok "All packages published at $VERSION"
