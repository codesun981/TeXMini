#!/usr/bin/env bash
# 编译并运行 TeXMini 单元测试（仅覆盖无 UI 依赖的 Models / Services）。
set -e
cd "$(dirname "$0")/.."
mkdir -p build

clang -fobjc-arc -O0 -g \
    -framework Foundation \
    -Isrc/Models \
    -Isrc/Services \
    src/Models/TMDocument.m \
    tests/TMTests.m \
    -o build/tmtests

build/tmtests
