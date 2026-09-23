#!/usr/bin/env bash
set -e

APP_NAME="TeXMini"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> 正在编译 ${APP_NAME}..."

mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

clang -fobjc-arc -O2 \
    -framework Cocoa \
    -framework PDFKit \
    -framework QuartzCore \
    -framework CoreText \
    -framework CoreImage \
    -framework UniformTypeIdentifiers \
    -lz \
    -Ivendor/synctex \
    -Isrc \
    -Isrc/Models \
    -Isrc/Services \
    -Isrc/Views \
    -Isrc/Controllers \
    vendor/synctex/synctex_parser.c \
    vendor/synctex/synctex_parser_utils.c \
    src/Models/TMDocument.m \
    src/Models/TMOutlineItem.m \
    src/Services/TMCompiler.m \
    src/Services/TMSyncTeX.m \
    src/Services/TMOutlineParser.m \
    src/Services/TMEditActions.m \
    src/Services/TMMagicComments.m \
    src/Services/TMLogParser.m \
    src/Services/TMRecentFiles.m \
    src/Services/TMProject.m \
    src/Services/TMCompletionProvider.m \
    src/Services/TMLaTeXScanner.m \
    src/Services/TMFileWatcher.m \
    src/Services/TMPreferences.m \
    src/Services/TMFontSettings.m \
    src/Services/TMFontCatalog.m \
    src/Views/TMLineNumberRulerView.m \
    src/Views/TMLaTeXHighlighter.m \
    src/Views/TMCompletionPopup.m \
    src/Views/TMDocumentFontView.m \
    src/Views/TMEditorTextView.m \
    src/Views/TMPDFView.m \
    src/Views/TMStatusBarView.m \
    src/Views/TMLogDrawerView.m \
    src/Views/TMFileBrowserView.m \
    src/Views/TMOutlineSidebarView.m \
    src/Controllers/TMMainWindowController.m \
    src/Controllers/TMPreferencesWindowController.m \
    src/AppDelegate.m \
    src/main.m \
    -o "${MACOS_DIR}/${APP_NAME}"

cp resources/Info.plist "${CONTENTS_DIR}/Info.plist"

# 复制一份图标（如有）
if [ -f "resources/${APP_NAME}.icns" ]; then
    cp "resources/${APP_NAME}.icns" "${RESOURCES_DIR}/"
fi

# Ad-hoc codesign
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "==> 构建完成！生成目录: ${APP_DIR}"
ls -lh "${MACOS_DIR}/${APP_NAME}"
