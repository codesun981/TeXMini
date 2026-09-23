# 11 · 编码与边界情况

**目的**：不是"正常论文"的输入：Latin-1 文件、CRLF 换行、超长行、tab、emoji、无 documentclass 片段、空文件、末尾无换行。

| 文件 | 内容 | 看什么 |
|---|---|---|
| `latin1.tex` | ISO-8859-1 编码的德语/法语文本（由 `make-encoded.py` 生成） | 打开不报错、重音字母正确显示；⌘S 后文件变成 UTF-8（这是预期的转换，但需要用户知道吗？记录） |
| `crlf.tex` | Windows 换行 | 行号正确、不出现 `^M`、SyncTeX 行号不偏移、保存后换行是否被改成 LF（记录） |
| `long-lines-tabs-unicode.tex` | 超长行、tab、emoji、CJK、末尾无换行 | 自动换行开关、行号槽、光标列号、当前行高亮 |
| `fragment-no-documentclass.tex` | 无 documentclass 的片段 | 编译失败的错误可读；大纲仍工作 |
| `empty.tex` | 0 字节 | 打开不崩溃，编译报错可读，行号槽显示 1 |

## 步骤
1. 先运行 `python3 make-encoded.py` 生成 `latin1.tex` 与 `crlf.tex`（已生成则跳过）。
2. 逐个打开，按表检查。
3. 对 `empty.tex`：粘贴一段内容 ⌘S，再 ⌘Z 撤销到空，确认撤销栈在打开文件时被清空（不能撤销到"打开前"）。

## 预期
- 没有任何文件导致崩溃或无限等待。
- 非 UTF-8 文件能打开（回退 Latin-1）。
