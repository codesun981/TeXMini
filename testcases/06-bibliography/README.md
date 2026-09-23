# 06 · 参考文献：BibTeX 与 biber

**目的**：最常见的"第一次编译引用是问号"问题；清理后重编译能否恢复；bib 补全。

## 步骤
1. 打开 `bibtex-natbib/paper.tex`，⌘B。看 PDF 末尾有没有 References，正文引用是不是 `[1]` 而不是 `[?]`。
2. 在 `\cite{}` 里按 ⌃Space。
3. 打开 `biblatex-biber/paper.tex`，⌘B。
4. ⌥⌘B（清理并重新编译）。
5. 打开侧栏"文件"页，确认 `.bbl/.bcf/.run.xml` 这类文件不显示，`refs.bib` 显示为紫色图标。
6. 在 `refs.bib` 里新增一条 `@misc{newkey, title={x}, year={2026}}` 保存，回到 paper.tex 在 `\cite{` 补全里看是否有 `newkey`。

## 预期
- 两种后端一次 ⌘B 都得到完整参考文献，无 `[?]`。
- 编译期间状态栏 spinner 一直转，日志里能看到 bibtex/biber 的输出。
- ⌥⌘B 后引用不丢。
- 修改 .bib 保存后，补全缓存失效并列出新 key（可能需要重新触发一次 ⌃Space）。
