# GitAgent — 开发笔记

> [English version](Development.md)

从 README 移出的面向开发者的记录：愿景、详细功能状态、架构决策、路线图和项目结构。

## 愿景

Git 无处不在，但驱动它仍然靠手工：每台设备有各自的仓库、各自的状态、各自的终端。GitAgent 把 iOS/macOS 设备变成控制中心：

- **智能体优先，而非界面优先** —— 主要交互方式是表达意图（"给我看办公室的 Mac 从昨天以来改了什么"、"把 NAS 上的修复提交并推送"），而不是按钮和菜单
- **覆盖整个局域网** —— 发现并操作局域网内其他设备上的 git 仓库：查状态、拉取、提交，远程处理日常操作
- **线上仓库也一样** —— 同一个智能体通过 API 驱动托管仓库（GitHub），本地和远程的工作集中在一处
- **运行在你所在的地方** —— iOS 和 macOS 原生 Swift 应用，局域网操作不需要云端中转

## 当前进展

现有代码库是智能体赖以构建的地基——一个原生 GitHub 客户端：

- 通过 OAuth Device Flow 登录 GitHub（应用内浏览器或系统浏览器，token 存系统钥匙串）
- 浏览你自己的/私有仓库以及星标仓库；Starred 列表按添加 Star 的时间排列（最近添加在前），不按仓库更新时间排列
- 应用内仓库浏览器：README 和文件预览，完整 Markdown 渲染、文档内锚点跳转，链接路由全部留在应用内（文件、文件夹和仓库都在固定的 README/Files 切换器下方打开）
- 个人主页视图，带 GitHub 贡献图（GraphQL）

**AI 聊天已接入：**

- 多 LLM 提供商支持 —— Kimi Code、Moonshot AI、OpenAI、DeepSeek、Anthropic，或任何兼容 OpenAI 的端点（Custom）。菜单选择提供商；模型列表自动从 API 拉取
- 多个聊天会话本地持久化；回答流式输出，完整 Markdown 渲染
- **通过 @ 和 / 引用仓库上下文** —— 输入 `@` 选择仓库（把它的 README 加入 prompt），再输入 `/` 附加其中的文件或文件夹（文件夹有 README 时会附带其 README）。prompt 模板把你的文字放在前面，引用内容放在后面
- API key 始终由用户手动输入并存入系统钥匙串——绝不随应用打包

**本地与 SSH 终端已就绪：**

- 在 macOS 上，Terminal 包含 **This Mac**，在原生伪终端中启动用户的登录 shell；不需要配置 localhost SSH 账号或远程登录。它与 Terminal.app 一致：dotfiles 会加载，shell 从 home 目录（或直接在某个仓库文件夹）启动，你的完整工具链（Homebrew、conda 等）都能用——macOS 应用刻意**不使用沙盒**，因为沙盒里的子 shell 这些全都做不到
- 粘贴 `ssh` 命令行即可添加主机（如 `ssh -o PubkeyAuthentication=no user@host -p 2222`）——自动解析出用户/主机/端口；可选的显示名称之后可以修改
- 省略 `-p` 时，GitAgent 保持命令为 `ssh user@host` 原样，不会在编辑器或主机列表里补 `:22` 或 `-p 22`；连接仍使用 SSH 标准默认端口 22
- 非默认 SSH 端口必须用 `-p <port>` 显式指定，指定后会被保留并显示
- 密码存入系统钥匙串，点一下主机行即可连接
- 本地和远程 shell 共用同一个应用内 xterm.js 渲染器（已 vendored，离线可用），终端尺寸变化会同步到活动 PTY，iOS 上支持惯性触摸滚动
- iOS/macOS 可以跨局域网连接 Mac/Linux SSH 主机；首次出现的主机公钥会通过 TOFU 精确固定，之后任何密钥变化都会被拒绝（指纹确认 UI 仍待实现）
- 已保存的目标在 UI 中仍是独立设备，同时可以选择通过另一台已保存的 SSH 主机中转（例如 iPhone → Linux 跳板机 → Mac）；直连的跳板机可用密码，目标机使用 Ed25519 密钥

### iPhone → Linux 跳板机 → Mac 配置

当校园网或访客 Wi-Fi 允许两台设备都访问某台 Linux 主机、但把 iPhone 与
Mac 直接隔离时，使用这条路径：

1. 在 GitAgent 中保存 Linux 主机并确认能连上。第一跳可以使用密码或 SSH
   密钥。
2. 用 Mac 正常的局域网地址和用户名把 Mac 保存为另一台主机，然后在
   **Jump Host** 下选择已保存的 Linux 主机。
3. Mac 目标必须使用 **SSH Key** 认证。在主机编辑器中生成它的 Ed25519
   密钥并使用 **Copy Setup Command**，然后在 Mac 的 Terminal 中粘贴并运
   行该命令。
4. 保存 Mac 主机并正常连接。GitAgent 仍然把 Mac 显示为独立设备，同时
   在后台以 iPhone → Linux → Mac 的路径打开连接。

如果使用的是 **Copy Public Key**，在公钥到达剪贴板后（例如通过接力剪
贴板），在 Mac 上运行等价的手动命令：

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
pbpaste | grep '^ssh-ed25519 ' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

生成的私钥永远不会离开 iOS 钥匙串。复制出去的公钥可以安全地安装到
Mac 上。不要把登录密码或私钥复制到文档、版本库或消息中。更多细节见
[`GitAgent/SSH/SSH.md`](../SSH/SSH.md)。

**仓库位置（Repository Locations）已就绪：**

- 每个 GitHub 仓库都有一个 Terminal 状态按钮：绿色表示至少一个已配置的工作树通过了当前验证规则；红色表示没有
- 一个仓库可以关联多个工作树——在这台 Mac 上直接选择的文件夹，或已保存的 Mac/Linux SSH 主机上的路径
- macOS 文件夹通过系统文件夹选择器选取，并以 security-scoped bookmark 持久化；由于应用未沙盒化，这只是为了方便重新打开文件夹，而不是文件访问限制
- 本地验证检查所选目录、Git 元数据以及 GitHub 远程地址的精确匹配，然后发起一次不带缓存的 GitHub API 认证请求，以证明目标仓库当前可达
- SSH 验证登录所选主机，解析 Git 根目录，核对远程身份，从该主机执行非交互式 `git ls-remote`，并通过 GitHub API 确认仓库
- 选中一个已连接的工作树会关闭位置面板、切换到 Terminal，并在仓库路径打开对应的本地或 SSH shell（本地 shell 直接在该路径启动；SSH shell 在 PTY 就绪后执行 `cd`）
- 位置面板固定提供三个动作：连接已有工作树、通过 RepoLaunch 再部署一份、关闭面板
- 直接的本地位置会打开原生 macOS shell，并在终端会话存续期间保留文件夹的 security-scoped bookmark；不需要预先保存 localhost SSH 主机
- 本地验证直接读取 Git 元数据而不运行 Git，因此"Mac 的命令行 Git 凭据能否拉取"的验证与连接检查是相互独立的

**RepoLaunch 部署已就绪：**

- Agent → RepoLaunch 可把任意 HTTPS/HTTP/SSH/Git clone URL 部署到这台 Mac 上选择的目录，或已保存 SSH 主机上的路径
- 部署按可见阶段执行：预检、clone/安全更新与 ref checkout、可选 setup/build/test 命令、最终 Git 根目录/remote/commit 验证
- 已有工作树只有在 `origin` 匹配且 tracked 文件干净时才会更新；RepoLaunch 不会覆盖本地修改
- 阶段、输出、commit、目标路径和失败信息持久化到 Application Support；带 HTTP 凭据的 URL 会被拒绝，避免 secret 进入历史记录
- 没有部署历史时直接进入 Deploy 表单；ref 与 setup/build/test 命令收在 Advanced Options 中
- 部署成功后会登记对应的 GitHub 仓库位置（如适用），关闭表单、切换到 Terminal，并在部署后的目录自动启动本地或 SSH shell

## 智能体架构——既定路线

**远程编码 CLI 是大脑；应用是脸和手。**
重任务（编译、测试、在工作副本上迭代）通过 **SSH** 派发给运行在 Mac/Linux 上的无头编码 CLI（`claude`、Kimi Code）；应用把 NDJSON 事件流回聊天界面。没有守护进程，也没有云端中转——SSH 连接目标机器自带的 `sshd` 是 iOS 与 macOS 的唯一远程传输通道。macOS 原生本地 Terminal 仍是交互式 shell，不冒充未来的无头 Agent relay。行为从 CLI 外部引导：system prompt、`AGENTS.md`/`CLAUDE.md`、skills、hooks 和工具白名单。

已完成的与计划中的：

| 部分 | 状态 |
|---|---|
| GitHub 客户端地基（OAuth、仓库/文件浏览、Markdown） | 已完成 |
| 多提供商流式聊天 UI、钥匙串凭据存储 | 已完成 |
| `SSH/` —— SSH 传输（直连/跳板连接、密码/Ed25519 认证、PTY shell、xterm.js 终端、TOFU 主机密钥固定、凭据存钥匙串） | 已完成（基础）；指纹确认 UI、SFTP 待实现 |
| 仓库位置 —— GitHub 仓库 ↔ 本地/SSH 工作树、验证、本地/SSH Terminal 深度跳转 | 已完成（基础） |
| `Agent/RepoLaunch/` —— 本地/SSH 仓库部署、分阶段命令、验证、持久日志 | 已完成（基础） |
| `Agent/` —— 编排（NDJSON 事件模型、会话/恢复、CLI 中继） | 计划中 |
| 远程引导（system prompt、AGENTS.md 同步、skills、hooks、白名单） | 计划中 |
| 长任务存续（远程 `tmux` 派发、重连 + 恢复） | 计划中 |
| 应用内 GitHub 工具循环 + 写操作（Git Data API，带确认） | 计划中，轻任务路径 |
| 设备端 git 引擎（libgit2） | 已推迟——可选的离线补充 |

设计文档：[Agent 层技术路线图](Roadmap.zh.md)（GitTaskBench 式任务执行 + 仓内 benchmark 设施）和[每日摘要技术路线图](Digest.zh.md)（基于反馈个性化的热门仓库简报）。

## 路线图

按构建顺序：

1. ~~**SSH 传输层**（`SSH/`）~~——已完成：直连/跳板连接、密码与应用生成的 Ed25519 认证、交互式 PTY 终端、凭据存钥匙串、自动 TOFU 主机密钥固定；指纹确认 UI 仍待完成
2. ~~**仓库位置层**（`Locations/`）~~——已完成：关联一个或多个本地/SSH 工作树、验证 GitHub 远程、在对应的本地或 SSH Terminal 中打开已连接路径
3. ~~**RepoLaunch 部署基础**（`Agent/RepoLaunch/`）~~——已完成：在本地或 SSH 主机部署在线 Git 仓库，执行显式分阶段命令，验证并登记结果
4. **Agent 编排层**（`Agent/`）——NDJSON 事件解析、任务会话、带引导参数的无头 CLI 调用
5. **远程 CLI 中继**——从 iOS 和 macOS 通过已保存 SSH 主机驱动 Mac/Linux 上的 `claude` / Kimi Code
6. **确认 + 安全闭环**——hooks → 写操作的应用内用户确认；主机隔离（专用用户/容器）
7. **GitHub 上的智能体写操作**——通过 Git Data API 建分支/提交/PR，用于不需要工作副本的任务
8. **本地 git 引擎**（libgit2，已推迟）——设备端工作副本，用于离线编辑

## 项目结构

```
GitAgent/
├── GitAgentApp.swift         # 应用入口
├── ContentView.swift         # 根视图（恢复中空白页、登录页或主界面）
├── Auth/
│   ├── GitHubConfig.swift    # OAuth Client ID 与端点
│   ├── GitHubAuthManager.swift  # Device Flow 登录、token 生命周期
│   └── KeychainHelper.swift  # 钥匙串存储（GitHub token、LLM API key）
├── API/
│   ├── GitHubClient.swift    # GitHub REST/GraphQL 封装（+ 图片/文本缓存）
│   └── Models.swift          # Codable 模型
├── Chat/
│   ├── ChatClient.swift      # 多提供商流式客户端（OpenAI 兼容 + Anthropic）
│   ├── ChatStore.swift       # 本地多会话聊天持久化
│   ├── ChatView.swift        # 聊天界面（Markdown 渲染的回答、会话）
│   ├── ChatComposer.swift    # 输入栏、@ 仓库选择器、/ 文件选择器、chips
│   ├── ChatReference.swift   # 引用模型 + prompt 模板
│   └── MarkdownBubbleView.swift # 高度自适应的 Markdown 气泡
├── SSH/
│   ├── SSHTerminalSession.swift # SSH 连接（Citadel）+ PTY shell 会话
│   ├── LocalTerminalSession.swift # 原生本地 PTY 中的 macOS 登录 shell
│   ├── SSHHostConfig.swift   # 已保存主机模型（凭据只存钥匙串）
│   ├── SSHHostStore.swift    # 主机列表、跳板路由、凭据解析
│   ├── SSHConnection.swift   # 直连/跳板连接链
│   ├── SSHEd25519Credential.swift # 应用自有 SSH 密钥生成/导出
│   ├── HostKeyStore.swift    # 自动 TOFU 精确固定主机公钥
│   ├── TerminalView.swift    # xterm.js 终端（WKWebView 桥）
│   ├── TerminalLaunchCoordinator.swift # 仓库位置/部署结果 → Terminal 路由
│   ├── SSHView.swift         # 主机列表、主机编辑器、终端界面
│   └── SSH.md                # SSH 层设计笔记 + 待办
├── Locations/
│   ├── RepositoryLocation.swift # 持久化的 GitHub 仓库 ↔ 工作树关联
│   ├── RepositoryLocationVerifier.swift # 本地/SSH 的 Git 与远程检查
│   ├── RepositoryLocationsView.swift # 列出、验证、删除、打开位置
│   └── AddRepositoryLocationView.swift # 关联已有本地/SSH 工作树
├── Agent/
│   ├── AgentView.swift         # Agent 目录
│   └── RepoLaunch/             # 本地/SSH 部署引擎、模型、历史和 UI
├── Docs/                     # 设计文档与开发笔记
│   ├── Development.md        # 本文件——愿景、状态、路线图、结构
│   ├── Agent.md              #（计划中的 Agent 层）已钉死的设计决策
│   ├── Roadmap.md            #（计划中的 Agent 层）分阶段技术路线图（GitTaskBench 式 + Benchmark/）
│   └── Digest.md             #（计划中的每日摘要）设计 + 路线图（反馈驱动的个性化）
├── Views/
│   ├── LoginView.swift       # 设备码登录（应用内或系统浏览器）
│   ├── MainView.swift        # 单导航栈（iPhone）/ 分栏视图（iPad、macOS）
│   ├── RepoListView.swift    # 仓库列表 + Terminal 位置状态
│   ├── RepoDetailView.swift  # README 标签页 + 链接应用内跳转
│   ├── FileContentViews.swift # 文件浏览器 + 文件查看器
│   ├── UserProfileView.swift # 个人主页 + 贡献图
│   ├── WebPageView.swift     # 应用内网页查看器（外部链接、OAuth 页面）
│   └── SettingsView.swift    # 设置（UI/Markdown 字号、LLM 提供商）
├── Rendering/
│   └── WebMarkdownView.swift # WKWebView Markdown 渲染器 + 链接路由
├── Settings/
│   ├── AppSettings.swift     # 应用设置（字号、提供商、钥匙串 key）
│   └── Localization.swift    # UI 字符串表
├── Utilities/
│   ├── PlatformHelpers.swift # 跨平台辅助 + 侧滑返回委托
│   └── AvatarView.swift      # 带认证的头像加载
└── Resources/web/            # 打包的 JS/CSS/字体（markdown-it、KaTeX、highlight.js）
```

## 备注

- macOS 应用未沙盒化（工程中 `ENABLE_APP_SANDBOX = NO`——配合 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`，控制注入沙盒 entitlement 的是这个构建设置，而不是 entitlements 文件）。沙盒中的子 shell 无法读取用户的 dotfiles，也无法运行容器外的工具，因此本地终端永远无法达到 Terminal.app 的效果；请把本地 shell 视为拥有与 Terminal.app 相同的能力。
- 渲染资源随应用打包，首次启动时安装到 Application Support。如果更新了 `Resources/web/` 下的文件，请递增 `Rendering/WebMarkdownView.swift` 中的 `WebAssets.version` 以强制重新安装。
- OAuth token 和 LLM API key 只会存入系统钥匙串。
- iPhone 刻意使用单个 `NavigationStack` 而不是折叠式分栏视图：分栏视图有两套相互竞争的返回手势系统，一次侧滑会弹出两级。
- **个人数据策略：** 个人账号值（Apple team ID、签名身份、GitHub OAuth Client ID）只存在于两个被 gitignore 的文件（`Local.xcconfig`、`GitAgent/Auth/LocalSecrets.swift`）中。被跟踪的 `Build.xcconfig` 通过 `#include?` 引入 `Local.xcconfig`，本身不含任何个人数据。
