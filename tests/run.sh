#!/usr/bin/env bash
# Runs the package's tests (the [Test] functions in tests/, with pepper test)
# and builds the table generator.
#
# Usage: tests/run.sh [path/to/pepper]   (default: pepper on PATH)
set -euxo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pepper="${1:-pepper}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The package is the module `unicode`: a folder of that name on the import path.
mkdir "$build/packages"
ln -s "$root" "$build/packages/unicode"
# The fixture tests read tests/fixtures/ relative to the root.
cd "$root"
"$pepper" test -I "$build/packages" tests
# The table generator is run by hand; building it keeps it working.
"$pepper" build generate/main.pep -o "$build/generate"
