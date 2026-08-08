> [English version](README.md)

<p align="center">
  <img src="assets/icon.png" width="128" alt="GitAgent icon">
</p>

# GitAgent

**集 GitHub 浏览、AI 聊天和内置终端于一体的原生应用——支持 iPhone 和 Mac。**

GitAgent 正在成长为一个面向 Git 的智能体，可以操作你各个设备上的仓库。现在它已经可以用来浏览 GitHub、与 LLM 聊你的代码、打开本地和 SSH 终端、把仓库关联到真实的工作树，以及一张表单完成仓库部署。

## 功能

**浏览你的仓库** —— 通过 GitHub OAuth Device Flow 登录（token 存系统钥匙串）；你自己的、私有的和星标的仓库，外加带贡献图的个人主页。

**用浏览器式 Pages 并行工作** —— 从紧凑的入口页开始，同时保留多个任务，切换时不会丢失各 Page 的导航状态；macOS 使用工具栏标签，iPhone 使用带实时预览的 Safari 式 Pages 总览。

**阅读与探索代码** —— README 和文件均以完整 Markdown 渲染（数学公式、语法高亮、锚点跳转）；图片（PNG/JPEG/GIF/WebP 等）和 PDF 均有内置查看器；文件、文件夹和仓库的链接全部在应用内打开。

**与 AI 聊你的代码** —— 支持 Kimi Code、Moonshot AI、OpenAI、DeepSeek、Anthropic 或任何兼容 OpenAI 的端点，模型列表自动拉取；输入 `@` 引用仓库，再输入 `/` 附加文件或文件夹；回答流式输出、Markdown 渲染，会话本地持久化，API key 只存钥匙串。

**终端——本地与 SSH** —— macOS 上的原生本地 shell，表现与 Terminal.app 一致（dotfiles、Homebrew、conda 全都能用）；粘贴 `ssh` 命令行即可添加主机，支持密码或应用生成的 Ed25519 密钥、支持跳板机；各平台共用同一个 xterm.js 终端，凭据只存钥匙串。

**把仓库关联到工作树** —— 将 GitHub 仓库关联到这台 Mac 上的文件夹或 SSH 主机上的路径，并自动验证；可直接在应用内浏览已连接的工作树，或打开位于该仓库路径的终端。

**用 RepoLaunch 部署仓库** —— 把任意 git URL 克隆到这台 Mac 或 SSH 主机，流程清晰可见（预检 → checkout → setup/build/test → 验证）；绝不覆盖本地修改；部署成功后自动在新的工作树中打开终端。灵感来自微软的 [RepoLaunch](https://github.com/microsoft/RepoLaunch)。

**用 Coder 智能体写代码** —— 在任意已连接的工作树上运行交互式编码 CLI 会话（Kimi Code、Claude Code 或 Codex），基于 tmux，可附带初始任务；会话在应用重启后依然存在，随时在完整终端中重新接管——iOS 上提供对话式输入条，因为在手机上直接操作终端键盘太痛苦；一轮对话完成后会标记会话并发送通知。

## 应用导览

### macOS

*应用启动后显示 New Page，并默认收起侧边栏。不同功能可在独立页面标签中打开和切换，不会替换当前页面。*

<p>
  <img src="assets/mac/pages.png" width="700" alt="macOS —— New Page 与页面标签">
</p>

*打开 Repositories 即可浏览自己的、私有的和星标的仓库，每行右侧是终端位置状态标记。*

<p>
  <img src="assets/mac/homepage.png" width="560" alt="macOS —— 仓库列表">
</p>

*打开一个仓库：README 以完整 Markdown 渲染，Files 标签页可以浏览目录树并显示最近提交信息。*

<p>
  <img src="assets/mac/read.png" width="410" alt="macOS —— README 渲染">
  <img src="assets/mac/files.png" width="410" alt="macOS —— 文件浏览器">
</p>

*Chat 标签页与你选择的 LLM 对话——输入 `@` 引用仓库，再输入 `/` 附加文件或文件夹。*

<p>
  <img src="assets/mac/chat.png" width="560" alt="macOS —— AI 聊天">
</p>

*Terminal 标签页列出 This Mac（原生本地 shell）和你保存的 SSH 主机。*

<p>
  <img src="assets/mac/terminal.png" width="270" alt="macOS —— 终端主机">
</p>

*仓库位置把 GitHub 仓库关联到经过验证的工作树——在这台 Mac 上或某台 SSH 主机上。*

<p>
  <img src="assets/mac/local.png" width="420" alt="macOS —— 仓库位置">
</p>

*Agent 目录：RepoLaunch 在本地或通过 SSH 克隆并准备好一个仓库；Coder 在已连接的工作树上运行交互式编码 CLI 会话。*

<p>
  <img src="assets/mac/agent.png" width="560" alt="macOS —— Agent 目录">
</p>

*Coder：选择 CLI 和工作副本，可选填初始任务——一轮对话完成后会在会话列表中标记。*

<p>
  <img src="assets/mac/coder.png" width="800" alt="macOS —— Coder 会话">
</p>

*RepoLaunch 的部署分阶段执行、经过验证，并保存在持久历史中。*

<p>
  <img src="assets/mac/repo.png" width="400" alt="macOS —— RepoLaunch 部署历史">
</p>

*设置：字号，以及 AI 聊天的提供商、Base URL 和模型。*

<p>
  <img src="assets/mac/setting.png" width="340" alt="macOS —— 设置">
</p>

### iOS

*GitAgent 启动后显示紧凑的 New Page 入口。底部工具栏左侧是返回，中间是菜单，右侧是新建 Page 和 Pages 总览。*

<p>
  <img src="assets/ios/homepage.png" width="220" alt="iOS —— New Page 入口">
</p>

*Safari 式 Pages 总览会显示已打开内容的真实预览；可以切换、关闭或新建 Page，而不会丢掉其他 Page。*

<p>
  <img src="assets/ios/pages.png" width="400" alt="iOS —— 带实时预览的 Pages 总览">
</p>

*在应用内浏览 GitHub 仓库、渲染 README，并沿目录树查看文件。*

<p>
  <img src="assets/ios/repos.png" width="200" alt="iOS —— 仓库列表">
  <img src="assets/ios/read.png" width="200" alt="iOS —— README 渲染">
  <img src="assets/ios/files.png" width="200" alt="iOS —— 文件浏览器">
</p>

*关联到 SSH 工作树的仓库也可以直接在 iPhone 上浏览，包括 Markdown 链接和文件预览。*

<p>
  <img src="assets/ios/local.png" width="400" alt="iOS —— 浏览已连接 SSH 工作树中的 README">
</p>

*终端支持直连和多跳路由；打开已连接的位置时，shell 会直接进入对应仓库。*

<p>
  <img src="assets/ios/terminal.png" width="200" alt="iOS —— 终端主机">
</p>

*Agent 目录（RepoLaunch 和 Coder），以及 iPhone 上的 Coder 会话列表。*

<p>
  <img src="assets/ios/agent.jpg" width="200" alt="iOS —— Agent 目录">
  <img src="assets/ios/coder.jpg" width="200" alt="iOS —— Coder 会话">
</p>

*iOS 上的设置：字号和 AI 聊天配置。*

<p>
  <img src="assets/ios/setting.png" width="200" alt="iOS —— 设置">
</p>

## 环境要求

- iOS 26+ / macOS 15.7+
- 从源码构建需要 Xcode 26+
- 运行 RepoLaunch 部署的机器需要 `tmux`（macOS：`brew install tmux`）

## 配置

GitHub 登录使用 OAuth Device Flow，需要你自己的 OAuth App：

1. 打开 <https://github.com/settings/developers> → **OAuth Apps** → **New OAuth App**（名称随意，URL 可填占位值），然后在该应用的设置中启用 **Device Flow**。
2. 创建两个**被 gitignore 的**文件，填入你的个人值：

   项目根目录的 `Local.xcconfig`（Apple 签名）：

   ```
   DEVELOPMENT_TEAM = ABCDEFGHIJ        # 你的 Apple team ID（iOS 真机需要）
   CODE_SIGN_IDENTITY[sdk=macosx*] = Apple Development
   ```

   `GitAgent/Auth/LocalSecrets.swift`（GitHub OAuth）：

   ```swift
   enum GitAgentSecrets {
       static let clientID = "Ov23..."  // 你的 OAuth App Client ID
   }
   ```

3. 打开 `GitAgent.xcodeproj`，选择 **My Mac** 或 iPhone 模拟器，运行（⌘R）。

**AI 聊天（可选）：** 打开 Settings → **AI Chat**，选择提供商并粘贴你的 API key。Base URL 和模型会自动填充；密钥只存钥匙串。

## 文档

架构、路线图、项目结构和开发笔记都在 [`GitAgent/Docs/`](GitAgent/Docs/)——从 [Development.zh.md](GitAgent/Docs/Development.zh.md) 开始。

## 许可证

GPL-3.0 —— 见 [LICENSE](LICENSE)。
