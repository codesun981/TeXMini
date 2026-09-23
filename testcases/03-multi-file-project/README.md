# 03 · 多文件项目（report + chapters/ + appendix/ + refs.bib + images/）

**目的**：论文级项目的日常操作：主文件推断、`% !TEX root`、跨文件引用/引用补全、跨文件的问题跳转与反向搜索、二级目录、文件浏览器右键操作。

## 步骤
1. ⇧⌘O 打开本文件夹（不是打开某个 .tex）。
2. 观察自动打开了哪个文件、侧栏"文件"页的树形结构。
3. 点开 `chapters/intro.tex`，⌘B。
4. 在 `intro.tex` 的 `\cite{` 里按 ⌃Space。
5. 打开 `chapters/method.tex`，⌘B 后打开日志抽屉的"问题"页，点那条 undefined reference 警告。
6. 在 PDF 里双击 Method 章的公式。
7. 打开 `appendix/appendix.tex`，观察文件浏览器的根目录是否还在项目顶层。
8. 侧栏"文件"页右键：新建 `chapters/discussion.tex`，写几行，再重命名成 `chapters/discussion-v2.tex`，最后移到废纸篓。
9. 在 `results.tex` 里按 README 提示拖入外部图片。
10. ⌥⌘B 清理并重新编译，观察 `main.bbl` 等被删后引用是否重新生成。

## 预期
- 打开文件夹后自动选中 `main.tex`（含 `\documentclass` 且被引用最多），浏览器里 `chapters/`、`appendix/`、`images/` 可展开，`.aux/.log` 等不显示。
- 在子文件里 ⌘B：状态栏 `… · 主文件 main.tex`，右侧显示 `main.pdf`。
- `\cite{` 补全含 `knuth1984 lamport1994 goossens1994 unused2020`；`\ref{` 补全含其他文件里的 `sec:method-setup`、`fig:inside`、`tab:results`。
- 问题列表里的警告带文件名 `method.tex`，点击后切到该文件并跳到那一行；`appendix.tex` 的 undefined citation 同理。
- PDF 里双击公式 → 编辑器切到 `method.tex` 并定位。
- 打开 `appendix/appendix.tex` 后浏览器根目录不变。
- 右键新建/重命名/删除后树立即刷新；重命名正在编辑的文件时窗口标题跟着变，⌘S 写到新路径。
- 拖图：figure 块插入 `results.tex`，图片复制到 `03-multi-file-project/figures/`，不重复添加 graphicx。
- `results.tex` 里故意放了一个 `\end{document}`：编译仍成功但附录和参考文献缺失。删掉它后 ⌘B，参考文献出现，且 `\ref{ch:appendix}` 可补全。

## 注意
- `results.tex` 末尾的 `\end{document}` 是故意的，测试完记得删掉。
- 第 9 步会在本目录生成 `figures/`，`reset.sh` 会清掉。
