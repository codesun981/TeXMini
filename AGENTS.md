# TeXMini — 给 AI 助手与贡献者的说明

TeXMini 是一个 macOS 原生的 LaTeX 编辑器（Objective-C + AppKit + PDFKit，无 Xcode 工程，用 `build.sh` 直接 `clang` 编译）。

## 核心理念：轻量、极速、易用

这三条是产品的宪法。任何功能提案、代码改动、依赖引入都先用它们过一遍；三者冲突时按 **易用 > 极速 > 轻量** 取舍，但不能有任何一条被明显牺牲。

### 1. 轻量（Lightweight）
- 单一 `.app`，无第三方运行时、无 Electron/Web 视图、无后台常驻进程。
- 不引入第三方库（现有唯一例外是 `vendor/synctex` 的 C 解析器）。优先用系统能力：`NSTextFinder`、`NSSplitViewController`、`PDFKit`、系统拼写检查、原生补全弹窗。
- 代码规模克制：新增一个功能应尽量落在已有的 Model / Service / View 分层里，而不是新起一套框架。
- **明确不做**：内置 TeX 发行版安装器、Git 面板、云同步/协作、可视化公式编辑器（WYSIWYG）、片段管理器、插件系统。这些与"轻量"冲突，交给别的工具。

### 2. 极速（Fast）
- 启动即用：冷启动到可编辑 < 1 秒，打开文件不弹向导。
- 编辑不卡：语法高亮按段落增量重算，大文件（>1 万行）滚动和输入不能掉帧。
- 编译反馈快：`latexmk` 后台运行，可取消（⌘.），状态栏实时显示；停止输入后自动编译可选。
- PDF 刷新保留视口，SyncTeX 双向跳转都要居中显示目标，不闪烁重载。
- 性能回归视为 bug。任何在主线程做 I/O、全量重高亮、同步扫描目录的改动都不接受。

### 3. 易用（Easy）
- 目标用户是"想写论文，不想折腾编辑器"的人。零配置可用：自动识别 MacTeX、自动推断主文件、中文内容自动切 XeLaTeX。
- 遵循 macOS 惯例：快捷键（⌘F 查找、⌘/ 注释、⌘B 编译、⌘. 取消）、菜单结构、原生外观（含深色模式）。
- 常用操作 ≤ 2 步可达；错误要能一键跳到出错行。
- 界面文案中文，克制、直接，不堆砌按钮；能自动做对的事就不要问用户。
- 复杂功能优先做成"默认正确 + 一个开关"，而不是一整页偏好设置。

## 仓库结构

```
build.sh            唯一真实构建入口；新增 .m 文件必须加进这里
Makefile            build / run / install / test / clean
src/AppDelegate.m   菜单、快捷键、启动流程
src/Controllers/    TMMainWindowController（单窗口主控制器）
src/Models/         TMDocument（文档/模板/保存）、TMOutlineItem
src/Services/       无 UI 依赖的纯逻辑：编译、SyncTeX、日志解析、魔法注释、
                    补全、大纲解析、项目/主文件推断、文件监视、最近文件
src/Views/          编辑器、高亮、行号、PDF 视图、大纲/文件侧栏、日志抽屉、状态栏
vendor/synctex/     synctex_parser (C)
tests/              TMTests.m（单元）、TMCompileIntegration.m（需要 latexmk）、run_tests.sh
```

## 开发约定

- 最低系统 macOS 14。构建：`./build.sh`；测试：`make test`（`tests/run_tests.sh`）；安装：`make install`。
- 纯逻辑放 `Services/` 或 `Models/`，先写测试再写实现；UI 改动用 `./build.sh` 编译后手动冒烟。
- 不要驱动 GUI 做自动化截图/点击测试；改完给出人工验证步骤即可。
- UI 文案中文；快捷键遵循 macOS 惯例，新增快捷键前检查与系统/已有快捷键是否冲突。
- 每个功能单独 commit，commit message 用 `feat:` / `fix:` / `chore:` 前缀。
- 用户偏好用 `NSUserDefaults`，key 以 `TM` 前缀命名，并在 `restorePersistedPreferences` 里恢复。

## 评估新功能的清单

提案前回答这四个问题，答不上来就不做：
1. 它让"写论文"这件事更快或更省心了吗？（易用）
2. 它能用系统 API 或 < 300 行代码实现吗？（轻量）
3. 它会在主线程做重活、或让启动/编译/滚动变慢吗？（极速）
4. 它是 Overleaf / TeXShop / TeXstudio 用户默认期待的"基础功能"，还是重度用户的"高级功能"？优先前者。
