# 01 · 单文件基础 article

**目的**：最简单的成功路径。任何一步不顺都是严重问题。

## 步骤
1. 用 ⌘O 打开 `main.tex`（或直接把文件拖到 Dock 图标上）。
2. ⌘B。
3. 左侧切到"大纲"。
4. 在正文里双击 "Double-click this sentence"，再在 PDF 上双击同一段。
5. ⌘J、⌘点击 也各试一次。
6. 光标放在 `\ref{` 里按 ⌃Space。

## 预期
- 状态栏显示 `latexmk · pdflatex`，几秒内变绿 `✓ 编译完成`，警告数为 0。
- 目录（TOC）第一次编译就有内容（latexmk 自动跑两遍）。
- 大纲有 Introduction / Mathematics / Aligned equations / Deep nesting（三级缩进）/ Lists and text / Second-pass content，点击大纲章节编辑器跳行且 PDF 同步。
- 双向 SyncTeX 目标都居中显示，PDF 端有黄色闪烁框，1 秒后消失不残留。
- `\ref{` 补全列出 `sec:intro`、`sec:math`、`eq:euler`、`eq:second`。
- 光标所在行有淡淡底色；光标停在 `{` 旁时配对的 `}` 常驻高亮。

## 覆盖功能
编译、大纲、SyncTeX 双向、label 补全、当前行高亮、括号高亮、状态栏。
