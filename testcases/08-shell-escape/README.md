# 08 · Shell Escape

**目的**：`-shell-escape` 开关是否真的传给了 latexmk；关闭时的安全默认；minted 这类依赖外部程序的包。

## 步骤
1. 打开 `write18.tex`，确认 编译 菜单里"允许 Shell Escape"未勾选，⌘B。PDF 应显示 OFF。
2. 勾选后 ⌘B，PDF 应显示 ON，目录里出现 `shell-escape-ok.txt`。
3. ⌘, 里看复选框状态是否和菜单一致；在偏好里取消，再看菜单。
4. 打开 `minted.tex`，未开 shell escape 时 ⌘B。**注意**：TeX Live 2025+ 自带的 minted 3 用受限 shell escape 就能跑通（`latexminted` 在白名单里），所以在这台机器上两种状态都应成功；只有旧版 minted 2 才会报 "You must invoke LaTeX with the -shell-escape flag"。看 PDF 里代码是否有语法着色。
5. 测完取消勾选，删掉 `shell-escape-ok.txt` 和 `_minted*` 目录（`reset.sh` 会做）。

## 预期
- 开关状态在菜单、偏好窗口、实际命令行三处一致（原始日志第一行能看到 latexmk 参数吗？如果看不到，记录为需求：日志开头打印完整命令行）。
- 关闭时 write18 只产生 warning 不产生 error，编译成功。
- minted 在 pygmentize 不在标准 PATH 时给出可理解的错误。
- `_minted*` 缓存目录出现后，文件浏览器是否把它藏起来（它以下划线开头，不是点开头，目前的过滤规则可能不认识它）。

## 记录
- 你的机器上 pygmentize 在哪个路径；如果只在 anaconda，记录"需要偏好里可加 PATH"。
