#!/usr/bin/env bash
set -e

APP_NAME="TeXMini"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
OBJ_DIR="build/obj"

echo "==> 正在编译 ${APP_NAME}..."

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${OBJ_DIR}"

CFLAGS=(-fobjc-arc -O2 -Ivendor/synctex -Isrc -Isrc/Models -Isrc/Services -Isrc/Views -Isrc/Controllers)
FRAMEWORKS=(-framework Cocoa -framework PDFKit -framework QuartzCore -framework CoreText
            -framework CoreImage -framework UniformTypeIdentifiers -lz)

# 源文件自动收集：新增 .m 不用再改这里
SOURCES=(vendor/synctex/synctex_parser.c vendor/synctex/synctex_parser_utils.c)
while IFS= read -r f; do SOURCES+=("$f"); done < <(find src -name '*.m' | sort)

# 增量编译：.o 不存在、比源文件旧、或比它依赖的任一头文件旧（clang -MMD 生成的 .d）时才重编
needs_build() {
    local src="$1" obj="$2" dep="${2%.o}.d"
    [ -f "$obj" ] && [ -f "$dep" ] || return 0
    [ "$src" -nt "$obj" ] && return 0
    for h in $(sed -e 's/\\$//' -e 's/^[^:]*://' "$dep"); do
        [ "$h" -nt "$obj" ] && return 0
    done
    return 1
}

OBJECTS=()
STALE=()
for src in "${SOURCES[@]}"; do
    obj="${OBJ_DIR}/$(echo "${src%.*}" | tr '/' '_').o"
    OBJECTS+=("$obj")
    if needs_build "$src" "$obj"; then STALE+=("$src|$obj"); fi
done

if [ ${#STALE[@]} -gt 0 ]; then
    echo "==> 编译 ${#STALE[@]}/${#SOURCES[@]} 个文件..."
    # 多核并行；任一文件失败则整体失败
    printf '%s\n' "${STALE[@]}" | xargs -P "$(sysctl -n hw.ncpu)" -I{} sh -c '
        src="${1%%|*}"; obj="${1##*|}"; shift
        clang "$@" -MMD -MP -c "$src" -o "$obj"
    ' _ {} "${CFLAGS[@]}"
fi

# 链接：有 .o 变化或可执行文件不存在时
BINARY="${MACOS_DIR}/${APP_NAME}"
if [ ${#STALE[@]} -gt 0 ] || [ ! -f "$BINARY" ]; then
    clang -fobjc-arc "${FRAMEWORKS[@]}" "${OBJECTS[@]}" -o "$BINARY"
fi

cp resources/Info.plist "${CONTENTS_DIR}/Info.plist"

# 复制一份图标（如有）
if [ -f "resources/${APP_NAME}.icns" ]; then
    cp "resources/${APP_NAME}.icns" "${RESOURCES_DIR}/"
fi
if [ -f "resources/icon.png" ]; then
    cp "resources/icon.png" "${RESOURCES_DIR}/"
fi

# Ad-hoc codesign
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || echo "==> 警告：codesign 失败（不影响本机运行）"

# 更新 .app 包目录时间戳，使 Finder 显示的修改时间与实际构建时间一致
touch "${APP_DIR}"

echo "==> 构建完成！生成目录: ${APP_DIR}"
ls -lh "${BINARY}"
