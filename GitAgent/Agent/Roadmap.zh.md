# Agent 层 — 技术路线

> [English version](Roadmap.md)

方向：为 GitAgent 带来 **GitTaskBench 式的能力**——用户用自然语言描述一个真实任务；远程编码 CLI 理解目标仓库、搭建环境、执行，并交付一个可验证的结果。benchmark 评测工具本身也纳入本仓库（任务定义、runner、评分器），但**不编译进 app**——它是宿主机侧的评测工具。

本文档是对 `Agent.md` 中已定决策的扩展（远程 CLI 是大脑、SSH 是唯一传输、exec 通道上跑 NDJSON 事件流），不重新讨论这些决策。

## 1. GitTaskBench 的启示

[GitTaskBench](https://github.com/QuantaAlpha/GitTaskBench)（NeurIPS 2025 生态，arXiv:2508.18993）用 54 个真实任务评测 agent，每个任务把一个固定的 GitHub 仓库和一套人工制定的自动化评测装置配对。三条经验驱动本设计：

1. **任务模型是（query + 仓库 + 评测装置）。** 任务不只是一段 prompt；它是一条自然语言 query、一个锁定的的工作树、外加一个自动化的通过/失败检查。GitAgent 已经拥有前三分之二：`Chat/` 承载 query，`Locations/` 锁定已验证的工作树。
2. **环境搭建是主要失败模式。** 论文中超过一半的 agent 失败来自依赖解析和环境配置，而不是推理能力。relay 必须把环境准备当作一等、可检查的阶段——而不是不可见的副作用。
3. **结果必须机器可判定。** 指标是 Execution Completion Rate（是否产出了有效结果）和 Task Pass Rate（产出是否满足任务特定标准）。因此 GitAgent 的交付以一个产物 + 一次检查结束，而不是以一条聊天消息结束。

该 benchmark 的当前前沿：OpenHands+Claude 3.7 任务通过率 48.15%，RepoMaster+Claude 3.5 为 62.96%——仓库利用型任务远未解决，预期要相应收敛。

## 2. 目标架构

```
┌───────────────────────── GitAgent app (iOS/macOS) ─────────────────────────┐
│ ChatView ── AgentViewModel ── AgentSession ── CLIRelay                     │
│   卡片          事件            生命周期        调用构建器                    │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    │ SSH exec 通道 (Citadel)，NDJSON
┌───────────────────────────────────┴──────────────────────────── 远程主机 ──┐
│ 可选 shim（JSON-lines 协议、会话持久化、权限回调）                            │
│   └── 无头编码 CLI（claude -p / kimi，stream-json）                          │
│         └── 已验证工作树（RepositoryLocation.path）                          │
│               └── 任务产物（输出文件、日志、patch）                           │
└────────────────────────────────────────────────────────────────────────────┘
```

- **仓库锚点：** 每个 agent 任务绑定一个已连接的 `RepositoryLocation`（已验证的工作树，`hostID` 选定 SSH 主机；`hostID == nil` 表示 macOS 本地树）。没有验证过的 location 就不能跑任务——复用现有验证流水线，而不是信任路径字符串。
- **传输：** 每个任务一条 SSH exec 通道（按 `Agent.md`）。长任务通过派发/轮询模型撑过 iOS 的 socket 挂起（主机上 `tmux`/`nohup`，app 按 session id 重连），`SSH.md` 已有记录。
- **行为驾驭：** 调用时的 system-prompt 标志（app 身份、仓库状态、环境画像）、目标仓库里的 `AGENTS.md`、工具白名单、max-turns 上限。hooks 实现写确认回路。
- **交付：** 任务产物经 SFTP 拉回（Citadel `openSFTP`，在 `SSH.md` 中列为待办），以带机器可判定状态的结果卡片呈现——对齐 benchmark 的产物 + 评测装置模型。

## 3. 阶段计划

### Phase 0 — 安全闸门（阻塞项）

agent 执行会放大未沙箱 shell 的爆炸半径。按 `AGENTS.md`，不得在 `.acceptAnything()` 之上构建 agent 执行。

- [ ] `HostKeyStore.swift` — TOFU 主机密钥验证 + 指纹确认 UI（`SSH.md` 已规划）。
- [ ] `SSHKeyManager.swift` — 公钥认证；agent 任务不应依赖驻留内存的密码认证。
- [ ] 宿主机隔离策略成文并在设置流程中强制执行：专用用户或容器（Docker/Lima），只挂载目标仓库（`Agent.md` 已定）。

### Phase 1 — 最小 relay（一次性任务）

目标：从一个已连接的仓库 location 派发自然语言任务，进度以聊天卡片流式呈现，可干净取消。

- [ ] `Agent/AgentEvent.swift` — NDJSON 事件模型：text / tool call / tool result / error（+ 产物引用，见 Phase 2）。
- [ ] `Agent/CLIRelay.swift` — 构建无头调用：prompt 组装、`--output-format stream-json`、白名单、max turns、工作目录取自 `RepositoryLocation.path`。
- [ ] `Agent/AgentSession.swift` — 生命周期：派发、流式、经 CLI session id 恢复、取消；iOS 后台挂起后的派发/轮询重连。
- [ ] `Agent/AgentHost.swift` — 执行目标模型：把 `RepositoryLocation` 解析为（SSH 主机、工作目录、环境画像）。
- [ ] `Agent/AgentViewModel.swift` — 事件流 → `Chat/` UI 的四种卡片。
- [ ] 所有写操作都要 app 内用户确认（与 GitHub 侧路线图同规则）。

完成标准：从 iPhone 向一台 Mac 主机派发任务，在已验证仓库里跑完，完整事件流渲染为聊天卡片。

### Phase 2 — 面向任务的能力（攻 GitTaskBench 的主要失分点）

目标：正面攻击 benchmark 的主要失败模式。

- [ ] **仓库简报。** 派发前构建仓库简报（README 摘要、顶层结构、检测到的工具链：python/node/rust、依赖清单），经 system-prompt 标志注入。这是 Aider repo map 在 app 侧的对应物。
- [ ] **每个 location 的环境画像。** 持久化每个 location 的环境记录（解释器版本、包管理器、曾成功的安装命令）。跨任务复用；把安装失败作为一等事件上报，让 UI 能显示"死在环境搭建"而不是一个笼统错误。
- [ ] **产物交付。** CLI 声明输出产物（文件/patch）；app 经 SFTP 拉回，存到 Application Support，渲染带预览的结果卡片。
- [ ] **机器可判定结果。** 任务可携带一个检查命令（测试脚本，按退出码或输出匹配判定）。relay 在完成后再跑它并报告 pass/fail——与 benchmark 的 Execution Completion / Task Pass 二分一致。

完成标准：一个 GitTaskBench 式任务（如"用这个仓库从 PDF 提取所有邮箱，存到 output.txt"）端到端完成并产出经过验证的产物。

### Phase 3 — Benchmark 集成（不编译进 app）

目标：benchmark 评测装置作为宿主机侧工具纳入本仓库，并驱动同一条 relay，使 GitAgent 自己的技术栈可度量。

顶层 `Benchmark/` 目录（在 Xcode target 之外——纯 Python 和 JSON，不参与编译）：

```
Benchmark/
├── README.md                 # 如何跑评测
├── tasks/                    # 任务定义，GitTaskBench 兼容 schema
│   └── <TaskName>_01/
│       ├── query.json        # 自然语言任务 + 输入文件
│       ├── task_info.yaml    # 仓库锁定、输出路径、评测配置
│       └── test_script.py    # 每任务自动化 pass/fail 检查
├── runner/                   # 在主机上驱动任务走 CLI relay
└── grader/                   # 执行 test_script.py，汇总报告
```

- [ ] 原样采用 GitTaskBench 的任务 schema（`query.json` / `task_info.yaml` / `test_script.py`），使上游任务可以不加修改直接放入，我们的成绩与已发表数字可比。
- [ ] 在**我们**的领域——仓库管理（issue 复现、patch + 测试、分支/commit 规范、远程部署）——策划首批任务集，与 GitTaskBench 的多媒体/文档领域互补。起步要小：约 10 个任务，每个有固定仓库锁定和严格检查。
- [ ] `runner/` 直接对无头 CLI 说话（不经 app）用于 CI 式运行，但使用与 `CLIRelay.swift` 相同的 prompt 组装和白名单。app 路径和 benchmark 路径必须共享一份调用定义，否则 benchmark 测的不是产品。
- [ ] `grader/` 按任务及汇总报告 Execution Completion Rate 和 Task Pass Rate；结果用纯 JSONL 存在 `Benchmark/results/`（gitignore）。

完成标准：本地能跑 `gittaskbench grade --taskid ...` 的等价命令，全量运行能产出与已发布榜单格式可比的汇总报告。

### Phase 4 — 加固（后期）

- 成本控制：max turns、每任务 token 预算、提前停止。
- 可选 shim，吸收 CLI flag 变更带来的协议漂移（`Agent.md`）。
- 确认回路验证可行之后的 GitHub 写操作（Git Data API）。
- 每主机并发任务；每主机能力矩阵。

## 4. 文件计划（app 侧）

| 文件 | 作用 | 阶段 | 状态 |
|---|---|---|---|
| `Agent/AgentEvent.swift` | NDJSON 事件模型（text/tool/result/error/artifact） | 1 | 未开始 |
| `Agent/AgentSession.swift` | 任务生命周期：派发、流式、恢复、取消 | 1 | 未开始 |
| `Agent/CLIRelay.swift` | 无头 CLI 调用构建器 | 1 | 未开始 |
| `Agent/AgentHost.swift` | 执行目标：location → 主机 + 环境画像 | 1 | 未开始 |
| `Agent/AgentViewModel.swift` | 事件流 → 聊天卡片 | 1 | 未开始 |
| `Agent/RepoBrief.swift` | 注入 prompt 的仓库简报 | 2 | 未开始 |
| `Agent/EnvironmentProfile.swift` | 每 location 环境记录 + 安装复用 | 2 | 未开始 |
| `Agent/ArtifactStore.swift` | SFTP 拉回 + Application Support 存储 | 2 | 未开始 |
| `Agent/TaskCheck.swift` | 运行后机器检查 → pass/fail 卡片 | 2 | 未开始 |
| `SSH/HostKeyStore.swift` | TOFU 主机密钥 | 0 | 未开始 |
| `SSH/SSHKeyManager.swift` | 公钥认证 | 0 | 未开始 |
| `SSH/` SFTP 支持 | 产物远程文件传输 | 2 | 未开始 |

非 app 部分：`Benchmark/`（任务、runner、grader）——Phase 3，永不加入 Xcode target。

## 5. 风险与开放问题

- **CLI flag 漂移。** 厂商 CLI 会改无头模式的 flag；Phase 1 锁定一个 CLI 版本，Phase 4 的 shim 吸收漂移。不要过早抽象。
- **iOS 后台挂起。** 基于 `tmux` 的派发/轮询未经验证；Phase 1 必须在任何 UI 打磨之前验证重连。
- **Benchmark 污染。** 我们策划的任务锁定公开仓库；任务定义不进 app 二进制，也不进任何可能被训练使用的渠道。
- **安全 vs 便利。** 确认回路恰恰给 benchmark 奖励的自治流程加了摩擦。app 内写操作保留确认；benchmark runner（不经 app）只允许在 Phase 0 的隔离环境中无人值守运行。
- **范围纪律。** GitTaskBench 显示最好的系统也只能通过约一半的仓库利用型任务。Phase 2 先交付 boring 的可靠性（环境搭建、产物检查），再谈自治野心。
