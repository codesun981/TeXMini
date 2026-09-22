# TeXMini 日常可用性补全 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 TeXMini 从"能跑通"补到"日常可用"：不丢数据、编辑器基础功能齐全、编译预览顺手、状态可持久化。

**Architecture:** 保持现有 AppKit + Objective-C 单窗口架构。纯逻辑（编辑动作、魔法注释、日志解析）抽成无 UI 依赖的 Services/Models 类，用 clang 直接编译的极简测试程序做 TDD；UI 改动通过 `./build.sh` 编译并启动 App 做冒烟验证。

**Tech Stack:** Objective-C, AppKit, PDFKit, synctex_parser (C), clang 脚本构建，NSUserDefaults。

**Spec:** 本计划直接来源于 2026-09-22 的功能缺口分析（对话记录），要点复述在各任务里。

## Global Constraints

- 最低系统 macOS 14，`build.sh` 是唯一真实构建入口，新增 .m 文件必须加进 `build.sh`。
- 不引入第三方依赖，不改成 Xcode 工程。
- UI 文案保持中文，快捷键遵循 macOS 惯例（⌘F 查找、⌘/ 注释、⌘. 取消）。
- 每个任务结束时 `./build.sh` 必须成功，`tests/run_tests.sh` 必须全绿。
- 每个任务单独 commit。仓库目前零提交，Task 0 先提交基线。

---

### Task 0: 测试脚手架 + 基线提交

**Files:**
- Create: `tests/TMTests.m`, `tests/run_tests.sh`
- Modify: `Makefile`（加 `test` 目标）

**Interfaces:**
- Produces: 宏 `TM_TEST(name)`、`TM_ASSERT_EQ_STR(a,b)`、`TM_ASSERT_EQ_INT(a,b)`、`TM_ASSERT_TRUE(x)`、`TM_ASSERT_NIL(x)`；`run_tests.sh` 编译 `tests/TMTests.m` + 所列 Services/Models 源文件。

- [ ] Step 1: 写 `tests/TMTests.m`，包含最小断言宏和一个 TMDocument 模板非空的 smoke 测试。
- [ ] Step 2: 写 `tests/run_tests.sh`：`clang -fobjc-arc -framework Foundation -Isrc/Models -Isrc/Services src/Models/TMDocument.m tests/TMTests.m -o build/tmtests && build/tmtests`。
- [ ] Step 3: 运行，期望 `1 passed, 0 failed`。
- [ ] Step 4: `git add -A && git commit -m "chore: baseline snapshot + test harness"`。

### Task 1: 未保存追踪、关闭/退出/替换确认、修复 /tmp 静默保存、加载时清撤销栈

**Files:**
- Modify: `src/Models/TMDocument.h/.m`（加 `isScratch`，`displayName`）
- Modify: `src/Controllers/TMMainWindowController.m`（dirty、confirm、windowShouldClose、title、undo）
- Modify: `src/AppDelegate.m`（`applicationShouldTerminate:`）
- Test: `tests/TMTests.m`

**Interfaces:**
- Produces: `TMDocument.isScratch` (BOOL)，`TMDocument.displayName` (NSString)，`- (BOOL)saveToURL:error:` 清 isScratch；`TMMainWindowController - (BOOL)confirmDiscardChangesWithTitle:` 返回 YES 表示可以继续；`- (void)markDirty`；`- (BOOL)hasUnsavedChanges`。

- [ ] Step 1: 测试：`documentWithDefaultTemplate` 的 `displayName` 为 `未命名文档.tex`；`saveToURL:` 到 tmp 后 `isScratch=YES`（通过 `saveScratchToURL:`）时 displayName 仍为未命名；正式 `saveToURL:` 后 `isScratch=NO`。
- [ ] Step 2: 实现 `TMDocument`：
  ```objc
  @property (nonatomic, assign) BOOL isScratch;
  - (BOOL)saveScratchToURL:(NSURL *)url error:(NSError **)error; // 写文件，设 fileURL，isScratch=YES，不清 isDirty
  - (NSString *)displayName; // isScratch || !fileURL ? @"未命名文档.tex" : fileURL.lastPathComponent
  ```
- [ ] Step 3: 控制器：`textDidChange:` 中 `documentModel.isDirty = YES; window.documentEdited = YES`。`loadDocumentIntoEditor` 中 `[self.editorTextView.undoManager removeAllActions]`、`window.documentEdited = NO`、`window.representedURL = isScratch ? nil : fileURL`、标题用 `displayName`。
- [ ] Step 4: `saveCurrentDocument` 改为：`if (!fileURL || isScratch)` 弹存储面板；新增 `saveDocumentAs`。保存成功后 `isDirty=NO`、`documentEdited=NO`。
- [ ] Step 5: `confirmDiscardChangesWithTitle:` NSAlert 三按钮（保存 / 不保存 / 取消），在 `newDocumentAction:`、`openDocumentAtURL:`、三个 `apply*Template:`、`windowShouldClose:` 前调用。AppDelegate `applicationShouldTerminate:` 委托给控制器。
- [ ] Step 6: 初始化时改用 `saveScratchToURL:`；`compileCurrentDocument` 中未命名时也用 scratch。
- [ ] Step 7: `./build.sh && tests/run_tests.sh`，启动 App：改字后关窗弹确认；⌘S 弹存储面板；打开文件后 ⌘Z 不回退到旧文档。
- [ ] Step 8: commit `fix: track unsaved changes, confirm before discarding, stop silent /tmp saves`。

### Task 2: 编译后保留 PDF 视口 + 反向搜索文件校验

**Files:**
- Modify: `src/Views/TMPDFView.m`（`reloadPreservingViewport` 接受新 URL）
- Modify: `src/Controllers/TMMainWindowController.m:428-472`
- Modify: `src/Views/TMStatusBarView.h/.m`（加 `showInfoMessage:`）

**Interfaces:**
- Produces: `TMPDFView - (void)loadPDFFromURL:(NSURL *)url preservingViewport:(BOOL)preserve;`，`TMStatusBarView - (void)showInfoMessage:(NSString *)msg;`

- [ ] Step 1: `loadPDFFromURL:preservingViewport:`：若 preserve 且已有 document，先记录 `currentPage` index 与 `scrollView.contentView.bounds.origin`，设新 document 后 `goToPage` + `scrollPoint`，并在 `dispatch_async(main)` 中再 scroll 一次以覆盖 PDFView 的异步布局。旧的 `loadPDFFromURL:` 转发 `preservingViewport:NO`；删除 `reloadPreservingViewport`。
- [ ] Step 2: `compilerDidFinishSuccess:` 只调 `loadPDFFromURL:pdfURL preservingViewport:YES`。
- [ ] Step 3: 反向搜索：把 `res.sourceFilePath` 解析为绝对路径（相对 PDF 目录），`URLByResolvingSymlinksInPath` 后与 `documentModel.fileURL` 比较；不同则 `showInfoMessage:@"该位置来自 X 第 N 行（当前未打开）"` 并 `NSBeep()`，不跳转。
- [ ] Step 4: 构建、启动、滚到第 2 页改字 ⌘B，确认视口不跳回顶部。
- [ ] Step 5: commit `fix: keep PDF viewport across recompiles; verify inverse-search target file`。

### Task 3: 编辑动作：查找替换、注释切换、缩进、环境自动闭合、括号跳过、跳转到行

**Files:**
- Create: `src/Services/TMEditActions.h/.m`（纯字符串逻辑）
- Modify: `src/Views/TMEditorTextView.h/.m`、`src/AppDelegate.m`（菜单）、`src/Controllers/TMMainWindowController.m`（跳转到行）
- Modify: `build.sh`、`tests/run_tests.sh`
- Test: `tests/TMTests.m`

**Interfaces:**
- Produces:
  ```objc
  @interface TMEditActions : NSObject
  + (NSString *)toggledCommentForLines:(NSString *)lines;            // 全部非空行已注释→去掉 "% "/"%"，否则每行行首加 "% "
  + (NSString *)indentedLines:(NSString *)lines indent:(NSString *)indent;
  + (NSString *)outdentedLines:(NSString *)lines width:(NSUInteger)width; // 去掉最多 width 个前导空格或一个 tab
  + (nullable NSString *)environmentToCloseInLine:(NSString *)line;   // "\begin{X}" 且同一行无 "\end{X}" → X
  + (NSString *)leadingWhitespaceOfLine:(NSString *)line;
  @end
  ```
  `TMEditorTextView`: `- (IBAction)toggleComment:(id)sender; - (IBAction)indentSelection:(id)sender; - (IBAction)outdentSelection:(id)sender;`

- [ ] Step 1: 写测试（每个方法 2–3 例，含空行、已注释、混合缩进）。
- [ ] Step 2: 运行，期望编译失败（类不存在）。
- [ ] Step 3: 实现 `TMEditActions`���
- [ ] Step 4: 测试通过。
- [ ] Step 5: `TMEditorTextView`：`usesFindBar=YES; incrementalSearchingEnabled=YES`；`toggleComment:` 等三个 action 用 `lineRangeForRange:` 取整行，`shouldChangeTextInRange:replacementString:` → `replaceCharactersInRange:` → `didChangeText`，保持选区覆盖替换后文本；Tab/Shift-Tab 在多行选区时调用 indent/outdent；`insertText:` 中：闭合字符与下一字符相同则前移光标；回车时若 `environmentToCloseInLine:` 非 nil，插入 `\n<indent>  ` + `\n<indent>\end{X}` 并把光标放中间行；`deleteBackward:` 中光标夹在 `{}`/`[]`/`()`/`$$` 之间时删除两个字符。
- [ ] Step 6: 菜单（AppDelegate 编辑菜单）：查找… ⌘F、查找下一个 ⌘G、查找上一个 ⇧⌘G、查找并替换… ⌥⌘F、使用所选内容查找 ⌘E（action `performTextFinderAction:`，tag 分别 `NSTextFinderActionShowFindInterface/NextMatch/PreviousMatch/ShowReplaceInterface/SetSearchString`）；分隔；切换注释 ⌘/、增加缩进 ⌘]、减少缩进 ⌘[；跳转到行… ⌘L（原"切换日志抽屉"改为 ⇧⌘L）；拼写检查 `toggleContinuousSpellChecking:`。跳转到行用 NSAlert + NSTextField accessory。
- [ ] Step 7: 构建、启动逐项手测。
- [ ] Step 8: commit `feat: find/replace, comment toggle, indent, env auto-close, goto line`。

### Task 4: 高亮范围扩展、括号匹配、字数统计、编辑器字号

**Files:**
- Modify: `src/Views/TMLaTeXHighlighter.h/.m`、`src/Views/TMEditorTextView.m`、`src/Views/TMStatusBarView.m`、`src/Controllers/TMMainWindowController.m`、`src/AppDelegate.m`

**Interfaces:**
- Produces: `TMLaTeXHighlighter + (void)setBaseFontSize:(CGFloat)size; + (CGFloat)baseFontSize;`；`TMEditorTextView - (void)setEditorFontSize:(CGFloat)size;`；`TMStatusBarView - (void)setCursorLine:column:totalChars:words:`（words 替换原 totalChars 显示）。

- [ ] Step 1: 高亮范围：`highlightTextStorage:inRange:` 把 range 向前后扩到最近空行（段落边界），上限各 200 行。新增正则：`\\\[[\s\S]*?\\\]`、`\\\([\s\S]*?\\\)`、`\\begin\{(equation|align|gather|multline|eqnarray|displaymath)\*?\}[\s\S]*?\\end\{\1\*?\}` 着 math 色；`\\verb(.)(.*?)\1` 着 secondary 色。字体从 `baseFontSize` 取。
- [ ] Step 2: 括号匹配：`setSelectedRanges:` 末尾，若光标左/右字符是 `{}[]()`，向对应方向扫描（跳过 `\{`），找到后 `showFindIndicatorForRange:` 一次（限制扫描 20000 字符）。
- [ ] Step 3: 字数：控制器 `textDidChange:` 里复用 0.25s 大纲 debounce，统计 `NSStringEnumerationByWords` 数量并更新状态栏 `行 x, 列 y | n 词`。
- [ ] Step 4: 视图菜单加 "编辑器字体放大 ⌥⌘=" / "缩小 ⌥⌘-"，范围 9–30，调用 `setEditorFontSize:`（更新 highlighter 基准字号 + rehighlightAll + ruler 重绘）。
- [ ] Step 5: 构建、手测：多行 `\[ \]` 着色，括号闪烁，字号变化。
- [ ] Step 6: commit `feat: paragraph-scoped highlighting, bracket match, word count, editor font size`。

### Task 5: 编译：魔法注释、latexmk 统一多遍、警告解析、取消、MacTeX 检测、自动编译

**Files:**
- Create: `src/Services/TMMagicComments.h/.m`、`src/Services/TMLogParser.h/.m`
- Modify: `src/Services/TMCompiler.h/.m`、`src/Controllers/TMMainWindowController.m`、`src/AppDelegate.m`、`src/Views/TMStatusBarView.m`、`src/Views/TMLogDrawerView.m`、`build.sh`、`tests/run_tests.sh`
- Test: `tests/TMTests.m`

**Interfaces:**
- Produces:
  ```objc
  @interface TMMagicComments : NSObject
  + (NSDictionary<NSString *, NSString *> *)magicCommentsInString:(NSString *)s; // 前 30 行，key 小写：program/root/encoding
  + (nullable NSURL *)rootFileURLForDocumentURL:(NSURL *)url content:(NSString *)content; // root 相对 url 目录解析；无 root 返回 nil
  @end

  typedef NS_ENUM(NSInteger, TMLogIssueKind) { TMLogIssueError, TMLogIssueWarning, TMLogIssueBadBox };
  @interface TMLogIssue : NSObject
  @property TMLogIssueKind kind; @property NSString *message; @property NSInteger line; // 0 = 未知
  @end
  @interface TMLogParser : NSObject
  + (NSArray<TMLogIssue *> *)issuesFromLog:(NSString *)log;
  @end
  ```
  `TMCompilerDelegate`：`compilerDidFinishSuccess:pdfURL:issues:`（替换旧签名）、`compilerDidFailWithError:line:fullLog:issues:`。`TMCompiler.compileOnSave` 不放这里，放控制器。
- [ ] Step 1: 测试 `magicCommentsInString:`（`% !TEX program = xelatex`、`%!TEX root=../main.tex`、大小写、超过 30 行不识别）；`issuesFromLog:`（`! Undefined control sequence.` + `l.12`、`LaTeX Warning: Reference `x' on page 1 undefined on input line 7.`、`Overfull \hbox (12pt too wide) in paragraph at lines 20--21`、`Package hyperref Warning: ...`）。
- [ ] Step 2: 运行失败 → 实现两个类 → 通过。
- [ ] Step 3: `TMCompiler`：`compileFileAtURL:` 读内容，`root` 存在则改编译 root 文件（delegate 回调里的 pdfURL 随之变化）；引擎解析顺序：用户显式选 xelatex/pdflatex → 若 latexmk 可用则 `latexmk -xelatex`/`-pdf`，否则直接引擎单遍；latexmk(auto) → `program` 魔法注释 → ctex 启发式 → `-pdf`。`lualatex` 映射为 `-lualatex`。失败/成功回调均带 `issues`。
- [ ] Step 4: 状态栏成功文案 `✓ 编译完成 (1.2s) · 2 警告`（0 警告不显示）；日志抽屉 `appendLogText:` 按行着色：`! ` 开头红色、`Warning` 橙色、`Overfull|Underfull` 黄色。
- [ ] Step 5: 编译菜单加 "取消编译 ⌘."（`validateMenuItem:` 仅编译中可用）；`compilerDidCancel` 回调让状态栏回到就绪。
- [ ] Step 6: AppDelegate 启动时 `![TMCompiler isMacTeXInstalled]` → NSAlert（按钮 "前往下载" 打开 `https://tug.org/mactex/`，"稍后"）。
- [ ] Step 7: 自动编译：控制器 `autoCompileEnabled`（NSUserDefaults `TMAutoCompile`），编译菜单 "自动编译（停止输入后）" 带勾选；开启时 `textDidChange:` 起 1.5s timer → `compileCurrentDocument`；编译中再触发则等本次结束后补一次。
- [ ] Step 8: 构建、手测：在 sample 加 `% !TEX program = xelatex` 后 ⌘B 日志显示 xelatex；引用未定义时看到警告数；⌘. 能取消。
- [ ] Step 9: commit `feat: magic comments, latexmk-driven engines, warning parsing, cancel, auto-compile`。

### Task 6: PDF 预览：页码、翻页、适合宽度/实际大小、打印

**Files:**
- Modify: `src/Views/TMPDFView.h/.m`、`src/Views/TMStatusBarView.h/.m`、`src/Controllers/TMMainWindowController.m`、`src/AppDelegate.m`

**Interfaces:**
- Produces: `TMStatusBarView - (void)setPageIndex:(NSInteger)idx pageCount:(NSInteger)count;`；控制器 `- (void)pdfNextPage; - (void)pdfPreviousPage; - (void)pdfFitWidth; - (void)pdfActualSize; - (void)printPDF;`

- [ ] Step 1: 控制器监听 `PDFViewPageChangedNotification` 与 `PDFViewDocumentChangedNotification`，更新状态栏 `第 3 / 12 页`（无 PDF 时隐藏）。
- [ ] Step 2: 视图菜单：上一页 ⌥⌘↑、下一页 ⌥⌘↓、适合宽度 ⌘0（`autoScales=YES`）、实际大小 ⌥⌘0（`autoScales=NO; scaleFactor=1`）。
- [ ] Step 3: 文件菜单 "打印… ⌘P" → `[pdfView printWithInfo:[NSPrintInfo sharedPrintInfo] autoRotate:YES]`；无 PDF 时菜单置灰。
- [ ] Step 4: 构建、手测。
- [ ] Step 5: commit `feat: page indicator, page navigation, fit modes, print`。

### Task 7: 持久化与菜单补全

**Files:**
- Modify: `src/Controllers/TMMainWindowController.m`、`src/AppDelegate.m`、`src/Views/TMStatusBarView.m`

**Interfaces:**
- Produces: NSUserDefaults 键：`TMEngine`(int)、`TMEditorFontSize`(double)、`TMAutoCompile`(bool)、`TMOutlineWidth`(double)、`TMOutlineCollapsed`(bool)、`TMRecentFiles`(array of path)。`AppDelegate - (void)noteRecentFile:(NSURL *)url;`

- [ ] Step 1: 窗口 `setFrameAutosaveName:@"TMMainWindow"`；内层 `splitView.autosaveName=@"TMContentSplit"`；大纲宽度与折叠状态在变化时写 defaults、启动时读。
- [ ] Step 2: 引擎选择、字号、自动编译读写 defaults（Task 4/5 已定义的属性在此接入）。
- [ ] Step 3: 文件菜单 "打开最近" 子菜单：AppDelegate 作为 NSMenuDelegate 在 `menuNeedsUpdate:` 里用 `TMRecentFiles` 重建（最多 10 条，末尾 "清除菜单"）；打开/保存成功时 `noteRecentFile:`，不存在的文件在打开时提示并移除。
- [ ] Step 4: 文件菜单加 "另存为… ⇧⌘S"；`validateMenuItem:` 对 导出 PDF / 打印 / 取消编译 置灰。
- [ ] Step 5: 构建、重启 App 验证窗口位置、分栏、引擎、最近文件均恢复。
- [ ] Step 6: commit `feat: persist window/layout/engine/font, recent files, save as`。

### Task 8: 工程清理

**Files:**
- Delete: `Package.swift`、`Sources/TeXMini/`、`.build/`
- Move: `Sources/CSynctex/` → `vendor/synctex/`，更新 `build.sh` 的 `-I` 与源文件路径
- Modify: `Makefile`（`test` 目标）、`.gitignore`（保留 `references/` 忽略）

- [ ] Step 1: 移动/删除，改 build.sh。
- [ ] Step 2: `./build.sh && tests/run_tests.sh` 全绿。
- [ ] Step 3: commit `chore: drop dead SwiftPM target, vendor synctex under vendor/`。

---

## Self-Review

- 覆盖：分析中"一、二、三、四"全部条目均有任务；"五"由 Task 8 覆盖。明确不做：多窗口多文档、偏好设置窗口、日志逐行点击跳转、PDF 内搜索（后续计划）。
- 占位符扫描：无 TBD/TODO。
- 类型一致性：`loadPDFFromURL:preservingViewport:`、`TMLogIssue`、`TMEditActions` 签名在各任务一致。
