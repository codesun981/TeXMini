# TeXMini 手工测试用例集

用 GUI 逐个打开这些文件夹里的 .tex，按每个目录的 `README.md` 操作并核对预期。目标是覆盖写 LaTeX 时会遇到的绝大多数情形，把 TeXMini 的问题一次找出来。

## 目录

| # | 目录 | 覆盖 |
|---|---|---|
| 01 | `01-basic-article/` | 最简单的成功路径：编译、大纲、双向 SyncTeX、label 补全、当前行/括号高亮 |
| 02 | `02-chinese-ctex/` | 中文文档自动切 XeLaTeX、字数统计、中文大纲、CJK 下的 SyncTeX |
| 03 | `03-multi-file-project/` | 多文件项目：主文件推断、`% !TEX root`、跨文件引用/补全/问题跳转/反向搜索、二级目录、文件浏览器右键、拖图到子文件 |
| 04 | `04-compile-errors/` | 七种常见编译错误各一个文件：问题列表、行号槽红点、状态栏跳转、抽屉自动弹出 |
| 05 | `05-warnings-and-badboxes/` | 编译成功但有警告/坏盒子：计数、着色、行号解析 |
| 06 | `06-bibliography/` | BibTeX+natbib 与 biblatex+biber：一次编译出全引用、清理后重建、bib 补全 |
| 07 | `07-engines-and-magic-comments/` | 引擎三层决策、手选覆盖、`% !TEX program` 两种写法、`% !TEX root` |
| 08 | `08-shell-escape/` | `-shell-escape` 开关是否真的生效、minted |
| 09 | `09-figures-and-dragdrop/` | 拖图插入 figure 的全部分支 |
| 10 | `10-large-document/` | 5000+ 行大文档：打开、高亮、滚动、编译不阻塞、补全延迟 |
| 11 | `11-encoding-and-edge-cases/` | Latin-1、CRLF、超长行、tab、emoji、无 documentclass、空文件、末尾无换行 |
| 12 | `12-beamer/` | 横向页面、overlay 页数、beamer 辅助文件清理 |
| 13 | `13-math-and-highlighting/` | 语法高亮边界：转义 `$`、注释里的 `$`、跨空行数学、verbatim |
| 14 | `14-editor-behaviours/` | 打字手感：自动配对、环境闭合、缩进、注释、补全、括号匹配、查找替换 |
| 15 | `15-external-modification/` | 文件被外部程序修改的五种情形 |
| 16 | `16-spelling/` | 系统拼写/语法检查在 LaTeX 源码里的表现 |
| — | `_assets/` | 共享素材：两张 PNG、一个 PDF 图 |

## 脚本

```
./verify.sh   # 不经过 GUI，用 latexmk 跑所有能跑的用例，确认"该成功的成功、该失败的失败"（约 1–2 分钟）
./reset.sh    # 删除全部编译产物、拖放复制的图片、shell-escape 生成物；还原被脚本改过的文件；重新生成 big.tex / latin1.tex / crlf.tex
```

`10-large-document/big.tex`、`11-…/latin1.tex`、`crlf.tex`、`empty.tex` 是生成文件，不入库；第一次用之前先跑 `./reset.sh`。

## 建议顺序

01 → 04 → 03 → 06 → 07 → 09 → 14 → 13 → 05 → 12 → 10 → 11 → 08 → 15 → 16 → 02。前七个覆盖日常 90% 的操作，出问题优先级最高。

## 记录问题

每个 README 末尾有"记录"小节，列出已知的模糊点。把发现的问题按下面格式记到 `FINDINGS.md`（不入库也行）：

```
- [04/missing-dollar] 问题列表指向第 7 行，真正原因在第 4 行 —— TeX 自身限制，可考虑同时显示 "l.N" 上下文
- [09/no-graphicx] 拖入 PDF 图后 figure 块能插入但 ⌘Z 需要按两次才撤销完 —— 应合并成一次撤销
```

## 写测试文件时的坑（给以后加用例的人）

- pdflatex 下正文里不能有 ⌘ ⌃ → 这类符号和中文，会直接报 `Unicode character … not set up`。键位用 `Cmd-B` 这种 ASCII 写法；中文放在 `%` 注释里是安全的。
- beamer 里用 `\verb` 的 frame 必须加 `[fragile]`。
- 想在正文里"提到"一个不存在的文件路径，要用 `\verb|…|`，否则 `\input{}` 会真的去找。
- 一个测试文件只放一种错误：`-halt-on-error` 让 TeX 在第一个错误处停下。
