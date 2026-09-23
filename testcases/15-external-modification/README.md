# 15 · 外部修改检测

**目的**：文件被别的程序改了（git、云盘、另一个编辑器）时不丢数据、不误报。

## 步骤
按 `watched.tex` 里的 Case A–E 操作，脚本：
```
./append.sh      # 追加一行
./touch-only.sh  # 只改时间戳
```

## 预期
- A：静默重载 + 状态栏提示，光标不跳。
- B：弹窗二选一，两种选择的结果都符合描述，且不会对同一次改动重复弹窗。
- C：无任何提示。
- D：不崩溃、不清空编辑器。
- E：回到窗口时也能检测到。

## 清理
测完用 git 还原本文件：`git checkout -- testcases/15-external-modification/watched.tex`（`reset.sh` 会做）。
