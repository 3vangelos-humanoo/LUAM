#!/bin/zsh
# Builds LUAM/Markdown as a library and runs LUAMTests against it without
# xcodebuild — fast feedback for parser work. Usage: Scripts/run-parser-tests.sh
set -euo pipefail
cd "${0:A:h}/.."

DEV=$(xcode-select -p)
TC=$DEV/Toolchains/XcodeDefault.xctoolchain/usr
P=$DEV/Platforms/MacOSX.platform/Developer
SDK=$P/SDKs/MacOSX.sdk
OUT=${TMPDIR:-/tmp}/luam-tests
TARGET=arm64-apple-macosx26.0
mkdir -p $OUT

$TC/bin/swiftc -sdk $SDK -target $TARGET -module-cache-path $OUT/mc \
  -module-name LUAM -enable-testing -emit-module -emit-library -parse-as-library \
  -default-isolation MainActor -swift-version 6 -Onone \
  -emit-module-path $OUT/LUAM.swiftmodule -o $OUT/libLUAM.dylib \
  -Xlinker -install_name -Xlinker @rpath/libLUAM.dylib \
  LUAM/Markdown/*.swift LUAM/Editor/MarkdownEditing.swift LUAM/Editor/BlockFormatting.swift LUAM/Editor/EditingExtras.swift LUAM/Editor/TableFormatter.swift \
  LUAM/Outline/DocumentOutline.swift LUAM/Preview/PreviewPage.swift LUAM/Theme/PreviewTheme.swift LUAM/Settings/AppSettings.swift

cat > $OUT/main.swift <<'EOF'
import Testing
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
EOF

$TC/bin/swiftc -sdk $SDK -target $TARGET -module-cache-path $OUT/mc \
  -parse-as-library -swift-version 6 -Onone \
  -F $P/Library/Frameworks -plugin-path $TC/lib/swift/host/plugins/testing \
  -I $OUT -L $OUT -lLUAM \
  -Xlinker -rpath -Xlinker $P/Library/Frameworks -Xlinker -rpath -Xlinker $OUT \
  -o $OUT/runner $OUT/main.swift LUAMTests/*.swift

$OUT/runner "$@"
