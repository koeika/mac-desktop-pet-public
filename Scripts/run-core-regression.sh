#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
build_dir="$(swift build --show-bin-path)"
runner="$(mktemp -d)/core-regression"
swiftc -parse-as-library -enable-testing -I "$build_dir/Modules" \
  Tests/Standalone/Runner.swift Tests/CodexPetCoreTests/*.swift \
  "$build_dir"/CodexPetCore.build/*.swift.o "$build_dir"/FSRS.build/*.swift.o \
  -o "$runner"
"$runner"
