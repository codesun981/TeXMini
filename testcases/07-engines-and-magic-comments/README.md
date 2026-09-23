# 07 · 引擎选择与魔法注释

**目的**：自动引擎的三层决策（魔法注释 → 内容启发式 → pdflatex 默认）、手选引擎覆盖、`% !TEX root`。

| 文件 | 预期引擎 | 依据 |
|---|---|---|
| `pdflatex-default.tex` | pdflatex | 默认 |
| `xelatex-magic.tex` | xelatex | `% !TEX program = xelatex` |
| `lualatex-magic.tex` | lualatex | `%!TEX program=lualatex`（无空格写法） |
| `fontspec-heuristic.tex` | xelatex | 内容含 fontspec |
| `root-magic/part.tex` | 编译 main.tex | `% !TEX root` |

## 步骤
1. 每个文件打开后 ⌘B，核对状态栏引擎名。
2. `lualatex-magic.tex`：状态栏引擎依次切到 lualatex、pdflatex、自动，各编译一次。
3. `root-magic/part.tex`：⌘B、双击、PDF 双击；再按文件内说明删掉第一行测试推断。
4. ⌘, 里把默认引擎改成 XeLaTeX，回到 `pdflatex-default.tex` ⌘B；再改回自动。

## 预期
- 引擎名与表一致；手选引擎优先于魔法注释（`lualatex-magic` 选 pdflatex 时应报错）。
- 偏好里改默认引擎后状态栏弹出菜单同步变化，反之亦然。
- `root-magic`：状态栏 `… · 主文件 main.tex`，SyncTeX 跨文件正确。
- 魔法注释只在前 30 行内生效（把 `xelatex-magic.tex` 第一行剪切到第 40 行再试，应回退到启发式）。
