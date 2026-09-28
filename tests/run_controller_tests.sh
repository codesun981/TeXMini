#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
./build.sh
OBJECTS=()
SOURCES=(vendor/synctex/synctex_parser.c vendor/synctex/synctex_parser_utils.c)
while IFS= read -r source; do SOURCES+=("$source"); done < <(find src -name '*.m' ! -name 'main.m' | sort)
for source in "${SOURCES[@]}"; do
    obj="build/obj/$(echo "${source%.*}" | tr '/' '_').o"
    OBJECTS+=("$obj")
done
clang -fobjc-arc -mmacosx-version-min=14.0 -O0 -g \
    -Isrc/Models -Isrc/Services -Isrc/Controllers \
    -framework Cocoa -framework PDFKit -framework QuartzCore -framework CoreText \
    -framework CoreImage -framework UniformTypeIdentifiers -lz \
    "${OBJECTS[@]}" tests/TMControllerLifecycle.m -o build/tmcontroller-tests
build/tmcontroller-tests
