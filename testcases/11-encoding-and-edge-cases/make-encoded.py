#!/usr/bin/env python3
"""生成需要特定字节形态的测试文件：latin1.tex（ISO-8859-1）与 crlf.tex（CRLF 换行）。"""
import os
here = os.path.dirname(os.path.abspath(__file__))

latin1 = r"""\documentclass{article}
\usepackage[latin1]{inputenc}
\usepackage[T1]{fontenc}
\begin{document}
Diese Datei ist in ISO-8859-1 gespeichert: Grüße aus Köln, Straße, Äpfel, Öl, Übung.
Français : élève, château, naïve, garçon, où, Noël.
Wenn der Editor dies als UTF-8 liest, erscheinen hier Ersatzzeichen oder ein Fehler.
\end{document}
"""
with open(os.path.join(here, "latin1.tex"), "wb") as f:
    f.write(latin1.encode("latin-1"))

crlf = "\r\n".join([
    r"\documentclass{article}",
    r"\begin{document}",
    r"\section{CRLF line endings}",
    "Every line in this file ends with CR LF (Windows style).",
    "Line 5: the gutter must say 5 here and SyncTeX must map to line 5.",
    "",
    r"\section{Second section}",
    "If the editor shows stray CR characters or doubles the line count, that is a bug.",
    r"\end{document}",
]) + "\r\n"
with open(os.path.join(here, "crlf.tex"), "wb") as f:
    f.write(crlf.encode("utf-8"))

open(os.path.join(here, "empty.tex"), "wb").close()
print("wrote latin1.tex, crlf.tex, empty.tex")
