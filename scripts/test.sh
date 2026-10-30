#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 6 -parse-as-library Sources/PowerCore.swift Tests/PowerCoreTests.swift -o .build/core-tests
.build/core-tests
