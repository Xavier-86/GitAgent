# Digest — 每日热门仓库技术简报（规划中，未实现）

**目标：** 每天向用户推送一则关于热门/trending 仓库的技术简报；用户可以对每条内容做反馈（感兴趣 / 不感兴趣 / 收藏）。反馈积累成偏好画像，让后续简报越来越个性化。

这是一个产品功能，与 `Agent/` 编排路线图相互独立：它**在端上运行，没有后端服务器**。复用现有管线——`API/GitHubClient` 取数据、`Chat/ChatClient` 做 LLM 撰写、Application Support JSON 做持久化、`L10n` 管字符串。

## 已定决策（pinned）

- **不要服务器、不要 APNs。** 投递方式是定时**本地通知**（`UNUserNotificationCenter`）+ 应用内 Digest 页。推送服务器会成为项目第一个后端依赖，还会把用户偏好数据带离设备——两者都否决。
- **端上生成优先。** 采集 → 排序 → 撰写都在 app 内运行。把撰写卸载到用户 SSH 主机（走 `Agent/` relay）是后期可选项，不是依赖——每日阅读功能不能要求用户先配好主机。
- **GitHub 初期是唯一数据源。** "Trending" 没有官方 API；用经过认证的 Search 查询近似（创建/推送时间窗、star 增速），走现有 `GitHubClient`。第三方 trending 爬虫既脆弱又有 ToS 风险——没有用户可见的开关就不要加。
- **个性化保持简单、可检查。** 一张按话题的权重表，由显式反馈按指数衰减更新。不用 embedding、不用向量库、不加新依赖。画像是纯 JSON，用户可在设置里重置。
- **持久化分层不变。** 简报历史、反馈事件、偏好画像都是非敏感数据 → Application Support 下的 JSON。LLM 密钥留在 Keychain；UserDefaults 只新增一个总开关（`AppSettings`）。

## 流水线

```
采集                    排序                    撰写
GitHubClient          话题亲和度             ChatClient（一次性，
 trending 候选集    →   + star 增速      →   流式写入 Digest 页）
 + 用户 star 图谱       + 新鲜度               偏好引导的 prompt
      │                    │                      │
      └──────────►  DigestIssue（日期 + [DigestItem]）──►  DigestView
                                              │
反馈 ◄── FeedbackStore ◄── 点赞 / 点踩 / 收藏 / 点进详情
   │
   ▼
PreferenceProfile（话题权重，指数衰减）──► 引导下一轮生成
```

- **采集。** 候选仓库来自 Search API 时间窗（如近一周创建、今日有推送、按 stars 排序），加上与用户 star 集合相邻的仓库（同话题/同语言）。README 懒加载，只取入围项（client 已有文本缓存）。
- **排序。** 确定性打分：star 增速 + 新鲜度 + 来自 `PreferenceProfile` 的话题亲和度。**LLM 不参与排序**，只为排序器选出的条目做叙述——让个性化可调试。
- **撰写。** 每则简报一次 `ChatClient.streamChat` 调用：system prompt 携带用户的高兴趣话题和反感话题；条目渲染为结构化卡片而非自由散文，使反馈可以逐条挂载。
- **反馈。** 卡片上的显式操作（感兴趣 / 不感兴趣 / 收藏）+ 点进 `RepoDetailView` 的隐式信号。每个信号立即更新画像；收藏条目在简报历史中可见。

## 投递机制

- **iOS：** 一个 `BGAppRefreshTask` 尝试在后台生成；成功后调度明天的本地通知。如果后台刷新没跑（不常打开的 app 很常见），则在下次前台时生成并调度通知。通知深链进 Digest 页。
- **macOS：** 没有 `BGTaskScheduler`——启动时生成，运行期间按每日定时器生成；同样的本地通知投递。
- 通知权限只在用户在设置里开启该功能后才请求（默认关闭）。

## 数据模型（Application Support JSON）

| 类型 | 内容 |
|---|---|
| `DigestIssue` | 日期、`[DigestItem]`、生成时间、所用 provider/model |
| `DigestItem` | repoID、fullName、一句话简介、"入选理由"、标签、排序分 |
| `FeedbackEvent` | itemID、信号（like/dislike/save/tap）、时间戳 |
| `PreferenceProfile` | 话题权重、语言权重、已屏蔽 repoID、最后更新时间；EMA 衰减让旧信号淡出 |

文件：`digest-issues.json`、`digest-feedback.json`、`digest-preferences.json`，与现有 store 并列存放。

## 阶段计划

### Phase 1 — 静态每日简报（无个性化）

- [ ] `Digest/DigestModels.swift` — 上述类型，Codable。
- [ ] `Digest/TrendingCollector.swift` — 候选查询 + 入围筛选；只为 `GitHubClient` 补缺（话题搜索）。
- [ ] `Digest/DigestGenerator.swift` — 固定 prompt → `ChatClient` → 简报。
- [ ] `Digest/DigestStore.swift` — 简报历史，读写。
- [ ] `Digest/DigestView.swift` — 简报列表 + 条目卡片，深链 `RepoDetailView`；字符串走 `L10n`。

完成标准：打开 Digest 标签页即可从 GitHub 实时数据生成并展示今日简报。

### Phase 2 — 反馈闭环与个性化

- [ ] 每张卡片的 感兴趣 / 不感兴趣 / 收藏 控件。
- [ ] `Digest/FeedbackStore.swift` — 事件日志。
- [ ] `Digest/PreferenceProfile.swift` — 权重表 + 衰减；`DigestGenerator` 的 prompt 引导；排序中的亲和度项。
- [ ] 设置页：查看/重置偏好画像；`AppSettings` 总开关。

完成标准：对某话题点"不感兴趣"后，它在后续简报中明显减少；点"感兴趣"则明显增多。

### Phase 3 — 每日推送

- [ ] `Digest/DigestNotificationScheduler.swift` — 本地通知、权限流程、深链。
- [ ] iOS `BGAppRefreshTask` 注册（走 `INFOPLIST_KEY_` 构建设置，没有 Info.plist）；macOS 启动/定时器生成。

完成标准：开启该功能的用户每天收到一条本地通知，点开是一则新鲜的个性化简报。

### Phase 4 — 打磨（可选）

- 收藏列表；分享；卡片上的"再来点类似的"。
- 经 `Agent/` relay 的主机侧生成，供想用比端上 provider 更重模型的用户。
- 更多数据源（如 Hacker News），每个源单独开关。

## 文件计划

| 文件 | 作用 | 阶段 | 状态 |
|---|---|---|---|
| `Digest/DigestModels.swift` | 简报/条目/反馈/画像类型 | 1 | 未开始 |
| `Digest/TrendingCollector.swift` | 候选采集 + 确定性排序 | 1 | 未开始 |
| `Digest/DigestGenerator.swift` | 经 `ChatClient` 的 LLM 撰写 | 1 | 未开始 |
| `Digest/DigestStore.swift` | 简报历史持久化 | 1 | 未开始 |
| `Digest/DigestView.swift` | 简报 UI + 条目卡片 | 1 | 未开始 |
| `Digest/FeedbackStore.swift` | 反馈事件日志 | 2 | 未开始 |
| `Digest/PreferenceProfile.swift` | 话题权重、衰减、prompt 引导 | 2 | 未开始 |
| `Digest/DigestNotificationScheduler.swift` | 本地通知 + 后台刷新 | 3 | 未开始 |

## 风险与开放问题

- **Trending 近似的质量。** Search 时间窗启发式和 github.com/trending 有偏差；Phase 1 先用肉眼验证输出质量，再投入个性化。
- **速率限制。** 认证的 Search 约 30 次/分钟；采集器每天只发少量查询，复用 client 的缓存。
- **LLM 成本与缺席。** 没配置 provider → 跳过撰写，直接展示带原始元数据的排序条目（简报仍可用，只是可读性差些）。
- **冷启动。** 空画像时纯按增速 + 新鲜度排序；首次运行可以让用户选 3–5 个兴趣话题，但前提是 Phase 2 证明冷启动质量确实是问题。
- **反馈信号的可信度。** 停留/点击等隐式信号噪声大；显式反馈权重高一个数量级，绝不让一次误触支配画像。
