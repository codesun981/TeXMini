#!/usr/bin/env bash
# 编译并运行 TeXMini 单元测试（仅覆盖无 UI 依赖的 Models / Services）。
set -e
cd "$(dirname "$0")/.."
mkdir -p build

clang -fobjc-arc -O0 -g -Wno-gnu-zero-variadic-macro-arguments \
    -framework Foundation \
    -framework CoreText \
    -Isrc/Models \
    -Isrc/Services \
    src/Models/TMDocument.m \
    src/Models/TMOutlineItem.m \
    src/Services/TMLineIndex.m \
    src/Services/TMWordCounter.m \
    src/Services/TMCompileTargetResolver.m \
    src/Services/TMOutlineParser.m \
    src/Services/TMLaTeXScanner.m \
    src/Services/TMMarkdownScanner.m \
    src/Services/TMFormatActions.m \
    src/Services/TMEditActions.m \
    src/Services/TMMagicComments.m \
    src/Services/TMLogParser.m \
    src/Services/TMRecentFiles.m \
    src/Services/TMProject.m \
    src/Services/TMCompletionProvider.m \
    src/Services/TMPreferences.m \
    src/Services/TMCompiler.m \
    src/Services/TMFontSettings.m \
    src/Services/TMFontCatalog.m \
    tests/TMTests.m \
    -o build/tmtests

build/tmtests

# 集成测试：需要 MacTeX（latexmk）。没有就跳过。
if [ -x /Library/TeX/texbin/latexmk ] || command -v latexmk >/dev/null 2>&1; then
    clang -fobjc-arc -O0 -g \
        -framework Foundation \
        -Isrc/Services \
        src/Services/TMCompiler.m \
        src/Services/TMMagicComments.m \
        src/Services/TMLogParser.m \
        tests/TMCompileIntegration.m \
        -o build/tmintegration
    build/tmintegration
else
    echo "integration: skipped (latexmk not found)"
fi
