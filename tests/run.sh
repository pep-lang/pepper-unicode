#!/usr/bin/env bash
# Runs the package's tests (the [Test] functions in tests/, with pepper test).
#
# Usage: tests/run.sh [path/to/pepper]   (default: pepper on PATH)
set -euxo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pepper="${1:-pepper}"

# tests/pep.toml makes tests/ a project that depends on the package, so the
# package's build script runs and makes its generated module: a package on
# the import path (-I) gets none. The fixture tests read tests/fixtures/
# relative to the root.
cd "$root"
"$pepper" test tests
