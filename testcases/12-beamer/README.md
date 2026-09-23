# 12 · Beamer 幻灯片

**目的**：非 article 类文档：横向页面在 PDF 视图里的缩放、overlay 造成的页数膨胀、beamer 特有的辅助文件清理、大纲对 frame 的处理。

## 步骤
1. 打开 `slides.tex`，⌘B。
2. 视图 ▸ 适合宽度 / 实际大小 各试一次；⌘+ ⌘- 缩放。
3. ⌥⌘↓ 翻页，看状态栏页码。
4. 在 Overlays 那一帧的源码双击，看 PDF 跳到第几页。
5. 在 PDF 公式上双击。
6. ⌘K 后在访达（⇧⌘R 显示 PDF 后看同目录）确认 `.nav .snm .vrb .toc` 都被删了。
7. ⇧⌘F 在 PDF 里搜 "slide 2"。

## 预期
- 横向页面"适合宽度"时整页可见不需要横向滚动。
- 页码总数 = 帧数 + overlay 额外页。
- 清理后只剩 `slides.tex` 和 `slides.pdf`。
- 大纲里显示 3 个 section（不显示 frame，记录是否需要）。
