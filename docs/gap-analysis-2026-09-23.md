# TeXMini 易用性缺口分析（2026-09-23）

对照对象：Overleaf、TeXShop、Texifier、TeXstudio、Texmaker、VS Code + LaTeX Workshop。
标准："至少 3 个主流编辑器都有、普通用户默认期待"的基础功能，剔除与「轻量」冲突的重功能。
参考资料：见文末。

## 一、TeXMini 现状盘点

| 领域 | 已有 |
|---|---|
| 编辑 | 语法高亮（段落增量）、行号、括号/`$` 自动配对与跳过、`\begin` 回车自动补 `\end`、保持缩进、⌘/ 注释、⌘] ⌘[ 缩进、⌘L 跳转行、NSTextFinder 查找替换、系统拼写检查、字体缩放、括号匹配闪烁 |
| 补全 | ⌃Space 及 `\cite{` `\ref{` `\begin{` 后自动弹出；命令 / 环境 / label / bib key，跨文件扫描并缓存 |
| 编译 | latexmk / xelatex / pdflatex 三选一（状态栏）、`% !TEX program/root` 魔法注释、中文自动 XeLaTeX、停止输入后自动编译、⌘. 取消、⌘K 清理辅助文件、日志抽屉（纯文本）、状态栏错误/警告计数、点击跳到第一个错误 |
| PDF | 连续滚动、缩放、适合宽度/实际大小、翻页、SyncTeX 双向（⌘J / 双击 / ⌘点击 / 大纲点击）、刷新保留视口、导出、打印、在访达中显示 |
| 项目 | 文件夹作为项目的文件浏览器、大纲侧栏、主文件推断、最近文件、外部修改检测 |
| 模板 | 内置 3 个（论文 / 中文报告 / 空白） |
| 偏好 | 无偏好窗口；仅静默记住引擎、字号、自动编译开关、窗口/分栏位置 |

## 二、缺口（按"基础程度 × 实现代价"排序）

### 第一梯队：所有对手都有、代价小、每天都用

> **状态：已于 2026-09-23 在分支 feature/tier1-usability 全部实现**（7 个 commit）。下面保留原始分析。

1. **可点击的错误/警告列表 + 行号槽标记**
   现状是纯文本日志和"跳到第一个错误"。六个编辑器全部提供解析后的问题列表，点一条跳一行；TeXstudio / Texmaker 还在行号槽标红。`TMLogParser` 已产出 `TMLogIssue`，只差一个 `NSTableView` 和 `TMLineNumberRulerView` 里画标记。
2. **极简偏好窗口（⌘,）**
   当前无法改字体家族、默认引擎、latexmk 附加参数。一页就够：字体、默认引擎、自动编译、自动换行、`-shell-escape` / 自定义参数、拼写语言。
3. **`-shell-escape` / 自定义 latexmk 参数**（menu 开关或 `% !TEX options`），minted / TikZ externalize 用户第一天就会撞上。
4. **引擎菜单补 LuaLaTeX**：现在只能靠魔法注释。
5. **"清理并重新编译"一键**（⌥⌘B）：TeXShop 的 Trash Aux & Typeset、VS Code 的 clean-and-retry，解决 aux 损坏这一经典卡点。
6. **文件浏览器右键菜单**：新建 .tex/.bib、重命名、删除（移到废纸篓）、在访达中显示。现在只能看不能改。
7. **最近项目（文件夹）**：`TMRecentFiles` 只记文件；打开过的文件夹应可一键回到。
8. **拖图片进编辑器 → 自动插入 `\includegraphics` figure 骨架**（图片在项目外时复制进 `figures/`）。Overleaf / TeXstudio 都有，代码量很小却是"易用"感最强的一项。
9. **PDF 内搜索**（PDF 聚焦时 ⌘F 走 `PDFView` 查找）。
10. **PDF 深色反色**：Texifier / VS Code / Overleaf 都有，夜间写作刚需，`CIColorInvert` 即可。
11. **当前行高亮、括号常驻高亮、自动换行开关**：编辑器基础观感，均为几十行改动。

### 第二梯队：基础但需要一点架构工作

12. **多文档/多窗口 + 自动保存与崩溃恢复**：每个桌面编辑器都能同时开两个文件；TeXMini 是单窗口。迁移到 `NSDocument` 顺带获得自动保存、版本、窗口恢复，是"不丢数据"的根基。
13. **项目内查找/替换**：论文多文件是常态，Overleaf / Texifier / TeXstudio / VS Code 都支持。可先做"只查找、结果列表点击跳转"。
14. **行操作快捷键**：上下移动行（⌥↑↓）、复制行、删除行；选区套环境/命令（选中后输入 `\textbf{` 已包裹，但没有"套 `\begin{}`"）。
15. **列表中回车自动补 `\item`**（VS Code、TeXstudio）。
16. **用户模板目录**（`~/Library/Application Support/TeXMini/Templates`），模板菜单自动列出。TeXShop / Texifier / Overleaf 都以模板起步。
17. **保存时轻量检查**：`\begin/\end` 不配对、括号不平衡、`$` 不闭合，编译前就在状态栏提示（Overleaf Code Check 的 20% 代码解决 80% 问题）。
18. **快速打开项目文件**（⇧⌘O 模糊搜索文件名）。
19. **拼写语言切换入口**：菜单加"显示拼写和语法"（⌘:），走系统面板即可。

### 第三梯队：常见但偏重，暂缓或做极简版

- **符号面板**：TeXstudio 1000+ 符号太重。可选做法：补全里加常用希腊字母/运算符（`\alpha`→α 预览），或一个可搜索的小面板。
- **代码折叠**：有用但改动 layout manager，先不做。
- **公式悬停预览 / 内联渲染**：需要独立小编译或 MathJax，与"轻量"冲突。
- **表格/图片向导对话框**：用带占位符的片段替代。

### 明确不做（与定位冲突，见 AGENTS.md）

WYSIWYG / 可视化编辑、Git 面板、云同步与协作、历史版本 UI、语法（LanguageTool）检查、多发行版管理、插件系统、片段管理器。

## 三、建议的下一批实施顺序

1. 错误列表 + 槽标记（#1） 2. 偏好窗口 + shell-escape + LuaLaTeX（#2 #3 #4） 3. 清理并重编（#5）
4. 文件浏览器右键 + 最近项目（#6 #7） 5. 拖图插入（#8） 6. PDF 搜索 + 反色（#9 #10） 7. 编辑器观感三件套（#11）
之后再评估 NSDocument 迁移（#12）。

## 参考资料

- Overleaf 文档：keyboard shortcuts、code check、file outline、inserting figures、symbols、templates
  https://docs.overleaf.com/navigating-in-the-editor/keyboard-shortcuts · https://docs.overleaf.com/troubleshooting-and-support/code-check · https://docs.overleaf.com/navigating-in-the-editor/file-outline · https://www.overleaf.com/blog/an-easier-way-to-insert-figures-in-overleaf
- TeXShop：https://pages.uoregon.edu/koch/texshop/about.html · https://pages.uoregon.edu/koch/texshop/changes_3.html
- Texifier：https://www.texifier.com/mac
- TeXstudio：https://www.texstudio.org/ · https://texstudio-org.github.io/editing.html · https://texstudio-org.github.io/compiling.html
- Texmaker：https://www.xm1math.net/texmaker/ · 用户手册 https://stuff.mit.edu/afs/athena/software/texmaker_v5.0.2/share/texmaker/usermanual_en.html
- LaTeX Workshop：https://github.com/James-Yu/LaTeX-Workshop（wiki: Compile / View / Intellisense / Snippets / Hover）
- 社区对比：https://tex.stackexchange.com/questions/193480/texmaker-vs-texstudio-comparison · https://www.reddit.com/r/LaTeX/comments/18ebloa/recommendation_on_latex_editors
