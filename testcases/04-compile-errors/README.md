# 04 · 编译错误

**目的**：每个文件恰好一种常见错误。检查问题列表、行号槽标记、状态栏跳转、日志抽屉自动弹出。

| 文件 | 错误 | 应指向的行 |
|---|---|---|
| `undefined-command.tex` | Undefined control sequence | 6 |
| `missing-dollar.tex` | Missing $ inserted | 4（TeX 可能报在 4–5） |
| `unclosed-env.tex` | itemize ended by \end{document} + 括号不平衡 | 3 / 8 |
| `missing-input.tex` | File not found（\input） | 4 |
| `missing-package.tex` | .sty not found | 2 |
| `missing-graphic.tex` | 图片文件不存在 | 6 |
| `two-errors.tex` | 两个错误，-halt-on-error 只报第一个 | 5 |

## 步骤（每个文件）
1. 打开，⌘B。
2. 看状态栏是否变红、错误按钮的行号。
3. 看日志抽屉是否自动展开并停在"问题"页；点击问题行。
4. 看行号槽的红点位置。
5. 修正错误（或在错误行前加 `%`），⌘B，确认红点和错误状态消失。
6. 打开"原始日志"页，确认错误行是红色。

## 预期
- 每个文件的错误行与表中一致，或至少在 ±2 行以内（TeX 自身的定位精度）。
- 修复后重新编译：状态栏变绿，问题列表清空并自动切回"原始日志"页，红点消失。
- 编译失败时右侧 PDF 保留上一次成功的版本（如有），不变成空白。
- 错误信息在问题列表里完整可读，超长时有 tooltip。

## 记录
- `missing-dollar.tex` 报的行号是否让人能找到真正原因？
- 是否希望不用 `-halt-on-error` 以便一次看到多个错误？（在偏好附加参数里填 `-interaction=nonstopmode` 无效，因为 halt-on-error 是我们固定加的；记录需求即可）
