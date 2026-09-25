#!/bin/zsh
# Typechecks the whole app target with swiftc, using the target's Swift
# settings — a quick check that works where xcodebuild can't run.
# Usage: Scripts/typecheck-app.sh
set -euo pipefail
cd "${0:A:h}/.."

DEV=$(xcode-select -p)
SDK=$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
OUT=${TMPDIR:-/tmp}/luam-typecheck
mkdir -p $OUT

$DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -typecheck \
  -sdk $SDK -target arm64-apple-macosx26.0 -module-cache-path $OUT/mc \
  -module-name LUAM -parse-as-library -swift-version 6 \
  -default-isolation MainActor -strict-concurrency=complete \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances \
  LUAM/**/*.swift
echo "Typecheck OK"
