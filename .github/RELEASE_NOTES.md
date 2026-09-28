TeXMini 1.0.0（构建 1）是首个公开版本：一个轻量、原生的 macOS LaTeX 编辑器，使用 AppKit 和 PDFKit，专注于写作、编译与 PDF 预览。

## 主要功能

- 中文界面，支持语法高亮、大纲、补全、查找和常用编辑快捷键。
- 自动推断主文件，中文内容自动选择 XeLaTeX，支持后台编译与取消。
- PDF 预览与 SyncTeX 双向跳转，刷新时保留阅读位置。
- 按项目与文件隔离编译缓存，编译错误可跳转到源码位置；切换文档时同步更新日志与预览状态。

## 下载与安装

要求 **macOS 14 或更高版本**。请按处理器选择附件：

| 你的 Mac | 文件名中的架构 |
| --- | --- |
| Apple 芯片（M 系列） | `arm64` |
| Intel 处理器 | `x86_64` |

打开 `.dmg`，将 TeXMini 拖入「Applications」即可安装；也可下载 `.zip`，解压后将 TeXMini.app 放入「应用程序」。`SHA256SUMS.txt` 提供四个安装包的 SHA-256 校验值。GitHub 自动附带的 Source code 文件是源码，直接安装应用时无需下载。

编译 LaTeX 需要自行安装 [MacTeX](https://www.tug.org/mactex/)；TeXMini 不内置 TeX 发行版。

此版本使用本地临时签名（ad-hoc），**尚未使用 Apple Developer ID 签名，也未经过 Apple 公证**。首次打开若被 macOS 阻止，请确认下载来源为本项目的 GitHub Releases，然后在「系统设置 → 隐私与安全性」中选择「仍要打开」。

## 验证范围

发布前已在本地 Apple 芯片 Mac 上通过 168 项单元测试、真实 TeX 编译集成测试和控制器测试。两种架构的发行包均由 GitHub Actions 构建，并检查打包完整性及临时签名；Intel 版本的验证范围限于构建、打包和签名检查，尚未进行人工使用验证。GitHub Actions 不安装 MacTeX，也不运行真实 TeX 编译集成测试。

本项目采用 [MIT 许可证](https://github.com/codesun981/TeXMini/blob/main/LICENSE)，第三方组件声明见 [THIRD_PARTY_NOTICES.md](https://github.com/codesun981/TeXMini/blob/main/THIRD_PARTY_NOTICES.md)。欢迎通过 [Issues](https://github.com/codesun981/TeXMini/issues) 反馈问题。
