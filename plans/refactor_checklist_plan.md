# Spotier 重构实施 Checklist Plan

更新日期：2026-03-21

## 执行状态（2026-03-22）

本计划对应的结构性改造已完成，代码侧已落地到仓库并通过自动化回归。

已完成：

1. 共享运行时常量、App Group、日志等级和日志容器路径已统一到单一入口。
2. 配置目录访问已拆成目录行为、目录访问、文件 repository、CloudKit sync coordinator，多处页面已移除直接文件写删。
3. `SpotierRunner` 已具备显式 session 生命周期，并把 session 轮换规则抽成可测行为模块。
4. `ContentView`、配置生成器、日志页、列表页和节点卡片已按“页面壳 + 可测行为层/原语层”拆分。
5. 日志事件格式化、配置编解码、配置目录规则、动态表单行为、连接用例、session 行为等都已补 app 侧测试。

当前仅剩人工 smoke checklist 未逐项手动执行；自动化验证已完成。

## 1. 目标与边界

本计划用于把当前审查中暴露出的结构问题，落成一份可执行的重构实施清单。目标不是局部修补，而是按项目 `AGENTS.md` 的约束，把页面职责、行为逻辑、布局规则、文件访问和跨进程共享配置拆回各自的单一职责层。

本轮重构的核心目标：

1. 建立单一事实来源，消除 App Group、会话状态、配置目录权限、日志等级读取的多份定义。
2. 让页面文件只保留组合、状态绑定和事件接线，不再直接负责文件 I/O、复杂状态派生和细节布局规则。
3. 把可复用行为提炼为纯逻辑模块，把配置文件访问、日志访问、配置生成/解析拆成可测试服务。
4. 修复当前已确认的根因问题：
   - App Group 标识不一致
   - 自定义配置目录的安全域读写/删除不完整
   - 配置生成器的动态数组索引绑定风险
   - `sessionID` 从未轮换导致的会话重建失效
5. 为关键映射补齐自动化测试，至少覆盖配置目录访问、配置编解码、日志配置共享、会话标识轮换。

本轮不包含：

1. `EasyTierCore/easytier-patched/` vendored 上游代码的深入改造。
2. 视觉风格重设计。
3. 与 NetworkExtension 架构无关的产品功能扩展。

## 2. 目标架构

建议把现有实现收敛为 6 个顶层关注点：

1. 运行时共享配置层
   - 负责 App Bundle / App Group / iCloud / 日志文件名等常量与共享默认值访问
2. 配置文件访问层
   - 负责安全域书签、目录访问、创建/读取/更新/删除配置、CloudKit 同步触发
3. 主界面状态层
   - 负责 VPN 连接状态、运行数据快照、会话标识、主界面 overlay route
4. 配置生成器领域层
   - 负责草稿、TOML 编解码、动态数组字段模型、保存/加载工作流
5. 日志与事件层
   - 负责日志文件路径解析、日志等级共享配置、纯解析逻辑、UI 数据源
6. SwiftUI 页面与原子组件层
   - 负责页面组合壳、统一 Header、统一浮动按钮、可复制明细行、动态列表字段行

## 3. 实施阶段 Checklist

### Phase 0: 基线与保护措施

- [ ] 新建分支并记录当前 `xcodebuild test -project Spotier.xcodeproj -scheme Spotier -destination 'platform=macOS'` 基线结果
- [ ] 补一份手工 smoke checklist，至少覆盖：
  - 自定义目录下创建配置
  - 自定义目录下删除配置
  - 配置生成器新增/删除监听地址、路由、出口节点
  - 修改日志等级并重启隧道
  - 重连 VPN 后节点列表动画/详情状态是否正确重置
- [ ] 在计划执行期间禁止新增业务功能，避免把结构改造和行为变更耦合在同一批提交

### Phase 1: 根因修复与单一事实来源收敛

#### 1.1 统一 App Group / 共享配置入口

- [ ] 把 `APP_BUNDLE_ID` / `APP_GROUP_ID` / `ICLOUD_CONTAINER_ID` / `LOG_FILENAME` 收敛到单一共享定义
- [ ] 清除所有硬编码 `group.com.alick.swiftier`
- [ ] 抽一个共享 `UserDefaults(suiteName: APP_GROUP_ID)` 访问入口，避免各文件重复拼接
- [ ] 确认主 App、NE、日志解析器、日志视图、设置页都读同一份日志等级

#### 1.2 收敛配置目录访问

- [ ] 把“列目录 / 读文件 / 创建文件 / 写文件 / 删除文件”全部收进同一安全域访问入口
- [ ] 禁止页面层直接 `write(to:)` 或 `removeItem(at:)`
- [ ] 保留 CloudKit 触发逻辑，但将其挂到 repository/service 层，而不是页面层

#### 1.3 修正会话标识模型

- [ ] 在 `SpotierRunner` 中显式定义会话开始/结束
- [ ] 每次 VPN 新连接成功时轮换 `sessionID`
- [ ] 断开时清空与会话绑定的瞬时状态
- [ ] `ContentView` 不再维护 runner 派生的本地镜像状态；主界面只绑定一个权威状态源

### Phase 2: 主界面与运行状态解耦

#### 2.1 拆薄 `ContentView`

- [ ] 把 overlay route 从多个 `Bool/URL?` 收敛为单一枚举状态
- [ ] 把布局常量和几何映射从页面文件提取到独立 layout rules
- [ ] 把“创建配置”“删除配置”“按钮中心定位”“选中配置同步”移出页面主体
- [ ] 保留 `ContentView` 只负责：
  - 页面结构
  - 绑定 state
  - 分发事件

#### 2.2 约束 `SpotierRunner` / `VPNManager` 边界

- [ ] `SpotierRunner` 只负责运行信息轮询、派生快照和会话状态
- [ ] `VPNManager` 只负责 NE 生命周期、provider message、On Demand 管理
- [ ] 把 UI 文本、弹窗、副作用从 runner 中移出，改为错误事件/状态输出

### Phase 3: 配置生成器领域拆分

#### 3.1 把配置模型与视图拆开

- [ ] 把 `SpotierConfigModel`、`PortForwardRule`、`PeerMode` 拆到独立 domain 文件
- [ ] 把 `ConfigDraftManager` 拆成草稿存储模块
- [ ] 把 `parseTOML` / `generateTOML` 抽成 codec/service
- [ ] 把 `loadContent` / `loadFromFile` / `generateAndSave` 抽成 generator store/use case

#### 3.2 替换索引驱动的动态列表

- [ ] 用 `Identifiable` 行模型替换所有 `ForEach(indices)` 驱动的可变表单
- [ ] 把字符串数组包装成稳定行对象，避免删除时 stale binding
- [ ] 对 `listeners` / `manualRoutes` / `exitNodes` / `manualPeers` / `overrideDns` / 通用字符串列表统一使用一套行为原语

#### 3.3 拆分配置生成器页面

- [ ] `mainView` 拆成基础网络、节点、DNS、监听地址、功能开关等 section 子视图
- [ ] `advancedView` 拆成 VPN Portal、代理网段、路由、出口节点、映射等 section 子视图
- [ ] `portForwardingView` 拆成独立 scene shell
- [ ] `header(...)` 改为复用统一容器原语，不再重复实现页面头部

### Phase 4: 日志/设置/列表 UI 原语统一

#### 4.1 统一日志访问与解析

- [ ] 日志文件路径解析从 `LogView` / `LogParser` 移出
- [ ] `LogParser` 只保留解析与缓冲逻辑，文件路径和日志等级由独立依赖注入
- [ ] 让设置页修改日志等级后，NE 与主 App 都消费同一来源

#### 4.2 统一页面 Header、浮动按钮、可复制行

- [ ] 扩展 `UnifiedHeader` 或建立新的 scene shell primitive
- [ ] `EventListView` 和 `LogListView` 的右下角滚动按钮收敛为共享 primitive
- [ ] `PeerCard.DetailRow` 的复制行为改成可访问的可复用行组件
- [ ] 减少 `onTapGesture` 驱动的交互，优先用 `Button`

### Phase 5: 测试与验收补齐

- [ ] 新增 app 侧测试 target（建议 `SpotierTests`），不要把 UI/domain 测试继续堆到 `SpotierNETests`
- [ ] 为配置目录访问补测试
- [ ] 为 TOML 编解码补测试
- [ ] 为会话标识轮换补测试
- [ ] 为 App Group / 日志等级共享补测试
- [ ] 为动态数组字段新增/删除顺序补测试

## 4. 受影响文件与方法清单

### 4.1 现有文件影响矩阵

| 文件 | 受影响方法 / 属性 | 所需修改 |
| --- | --- | --- |
| `Spotier/ContentView.swift` | `body`, `headerView`, `contentArea`, `buttonCenterY(in:)`, `createConfig()`, `deleteSelectedConfig()`, `SpeedDashboard.body`, `PeerListArea.body` | 拆成页面壳；移除文件 I/O；把 overlay 状态改为单一 route；把 layout 规则提取到独立模块；改为绑定权威状态对象，不再镜像 `runner` 状态 |
| `Spotier/SpotierRunner.swift` | `sessionID`, `currentSessionID`, `handleVPNStatusChange(_:)`, `toggleService(configPath:)`, `startMonitoring()`, `resetSpeedCounters()`, `processRunningInfo(_:)` | 引入显式 session 生命周期；在连接建立时轮换 session；移除 UI 级副作用和弹窗；输出稳定运行时快照供视图消费 |
| `Spotier/VPNManager.swift` | `saveConfigToAppGroup(configContent:)`, `startVPN(configContent:)`, `disableOnDemandAndStop()`, `updateStatusSync()`, `processPendingStartIfNeeded()` | 保持 NE 生命周期职责；如有需要抽出 provider message / tunnel state adapter；避免与 `SpotierRunner` 重复承担页面语义 |
| `Spotier/ConfigManager.swift` | `refreshConfigs(skipCloudSync:)`, `readConfigContent(_:)`, `deleteConfig(_:)`, `selectCustomFolder()`, `triggerCloudSyncIfNeeded(force:)`, `directoryFromUserPreference()` | 演进为配置文件访问服务或被新 repository 包装；补齐 create/update/delete 的安全域访问；保留 CloudKit 同步但下沉到服务边界 |
| `Spotier/ConfigEditorView.swift` | `loadContent()`, `saveContent()`, `body` | 改为调用统一配置 repository；移除本地安全域访问细节；页面只保留编辑器壳层 |
| `Spotier/ConfigGeneratorView.swift` | `body`, `loadContent(forceReset:)`, `advancedView`, `mainView`, `portForwardingView`, `stringListSection(list:placeholder:)`, `safePeerBinding(at:)`, `header(...)`, `generateAndSave()`, `loadFromFile()`, `parseTOML(_:)`, `generateTOML(peers:)`, `IPv4CidrField`, `IPv4Field` | 拆出 domain model、draft store、codec、section 子视图、动态列表原语；去掉索引驱动可变绑定；保留视图层只做组合与绑定 |
| `Spotier/SettingsView.swift` | `@AppStorage("logLevel"...`, `body`, `checkLaunchAtLogin()`, `toggleLaunchAtLogin(enabled:)` | 切到统一 App Group 配置入口；如引入 `LogSettingsStore`，则改为绑定 store；设置页只负责展示与交互 |
| `Spotier/LogView.swift` | `logPath`, `body` | 移除硬编码 App Group 路径；接入日志容器解析服务；复用统一 Header primitive |
| `Spotier/LogParser.swift` | `logPath`, `quickParseLogs(_:)`, `readNewRawLines()`, `startMonitoring()`, `updateEventsFromRunningInfo(_:)` | 把文件路径解析和日志等级来源注入；保留纯解析逻辑；为 parser 增加可测试边界 |
| `Spotier/SharedComponents.swift` | `UnifiedHeader` | 扩展为真正的页面壳 primitive，统一 header/标题/左右操作区，不再让各页面重复实现相似结构 |
| `Spotier/PeerCard.swift` | `body`, `ScrollingText.body`, `DetailRow.body`, `ScrollingTextValue.body`, `localNodeSections(_:)`, `remotePeerSections(_:)` | 提取滚动文本、Tag、可复制行原语；把交互从 `onTapGesture` 改为更可访问的按钮型组件；把宽度规则集中定义 |
| `Spotier/EventListView.swift` | `body`, `FlatCircleButtonModifier.body(content:)` | 提取统一的滚动到顶部浮动按钮 primitive；收敛空态/列表态样式规则 |
| `Spotier/LogListView.swift` | `body`, `LogListRow.body`, `LogDetailView.body` | 收敛浮动按钮与行选中行为；避免页面内部重复交互原语 |
| `Spotier/SpotierControlApp.swift` | `SpotierControlApp.body`, `MenuBarIconState.handleRunningStateChange(isRunning:)`, `updateTimerState()` | 若引入统一运行状态 store，需要让菜单栏图标消费同一权威状态；删除无效或冗余状态持有 |
| `Spotier/CliClient.swift` | `PeerInfo.sessionID`, `PeerInfo.id`, `fetchPeers(sessionID:)`, `parseCLITable(_:sessionID:)`, `parseCLIJSON(_:sessionID:)` | 若保留 CLI 路径，需与新的 session 轮换语义一致；注释和 ID 生成规则要与 `SpotierRunner` 对齐 |
| `Spotier/EasyTierShared.swift` | `APP_BUNDLE_ID`, `APP_GROUP_ID`, `ICLOUD_CONTAINER_ID`, `LOG_FILENAME`, `connectWithManager(_:)` | 作为主 App 侧共享常量来源；补一个统一 defaults/container helper，禁止各处硬编码 |
| `SpotierNE/EasyTierShared.swift` | `APP_BUNDLE_ID`, `APP_GROUP_ID`, `ICLOUD_CONTAINER_ID`, `LOG_FILENAME`, `connectWithManager(_:)` | 与主 App 侧保持完全一致；必要时合并为真正共享文件，避免双份常量漂移 |
| `SpotierNE/PacketTunnelProvider.swift` | `loadConfig()`, `parseConfigHints(_:)`, `applyNetworkSettings(_:)`, `buildSettings()`, 读取 `UserDefaults(suiteName: APP_GROUP_ID)` 的相关逻辑 | 使用统一共享配置入口；确保日志等级与共享常量统一；避免主 App 与扩展配置源分叉 |
| `SpotierNE/TunnelHelper.swift` | `initRustLogger(level:)`, `fetchRunningInfo()` | 使用统一容器/日志配置常量；必要时让日志初始化走共享 helper |
| `Spotier.xcodeproj/project.pbxproj` | target/file references/build phases | 挂接新增文件；若新增 `SpotierTests` target，也需要更新 project 配置 |

### 4.2 建议新增文件

以下文件名为建议命名，可按现有目录风格微调，但职责边界应保持不变。

| 建议新增文件 | 目的 |
| --- | --- |
| `Spotier/AppRuntimeConfig.swift` | App Group、Bundle ID、日志文件名、iCloud 容器等统一定义；提供默认值/容器访问 helper |
| `Spotier/Config/ConfigDirectoryAccess.swift` | 封装安全域书签、目录解析、`withScopedAccess` |
| `Spotier/Config/ConfigFileRepository.swift` | 统一 create/read/update/delete/list；对上层暴露 typed API |
| `Spotier/Main/MainDashboardState.swift` | 主界面权威状态，收敛 `runner`/`vpnManager` 派生值与 overlay route |
| `Spotier/Main/MainOverlayRoute.swift` | 用枚举表达日志/设置/生成器/编辑器/新建弹窗等路由 |
| `Spotier/Main/DashboardLayoutMetrics.swift` | `windowWidth`、`windowHeight`、按钮中心 Y、节点区高度等布局规则单一来源 |
| `Spotier/Main/MainDashboardHeader.swift` | 主界面顶部菜单与操作区组合 |
| `Spotier/Main/CreateConfigPrompt.swift` | 新建配置弹窗，脱离 `ContentView` |
| `Spotier/ConfigGenerator/SpotierConfigDraft.swift` | `SpotierConfigModel`、`PortForwardRule`、`PeerMode` |
| `Spotier/ConfigGenerator/SpotierConfigCodec.swift` | TOML 解析与生成 |
| `Spotier/ConfigGenerator/ConfigDraftStore.swift` | 草稿读写与生命周期 |
| `Spotier/ConfigGenerator/StringListFieldRow.swift` | 动态字符串字段行原语，替代索引驱动 `ForEach(indices)` |
| `Spotier/ConfigGenerator/ConfigGeneratorStore.swift` | 处理 load/save/generate 工作流 |
| `Spotier/Logging/LogContainerResolver.swift` | 统一日志文件路径和 App Group 解析 |
| `Spotier/Logging/LogSettingsStore.swift` | 日志等级的统一设置入口 |
| `Spotier/UI/FloatingScrollTopButton.swift` | 统一右下角滚动到顶部按钮 |
| `Spotier/UI/CopyableDetailRow.swift` | 可访问、可复制的明细行组件 |
| `SpotierTests/AppRuntimeConfigTests.swift` | 校验 App Group / defaults / log path 统一配置 |
| `SpotierTests/ConfigFileRepositoryTests.swift` | 校验安全域路径下的 list/create/update/delete 流程 |
| `SpotierTests/SpotierConfigCodecTests.swift` | 校验 TOML parse/generate |
| `SpotierTests/SpotierRunnerSessionTests.swift` | 校验 session 轮换与 reconnect 行为 |
| `SpotierTests/ConfigGeneratorCollectionTests.swift` | 校验动态列表新增删除后绑定稳定性 |

## 5. 文件级实施清单

### A. 共享常量与 App Group 收敛

- [ ] 修改 `Spotier/EasyTierShared.swift`
- [ ] 修改 `SpotierNE/EasyTierShared.swift`
- [ ] 修改 `Spotier/SettingsView.swift`
- [ ] 修改 `Spotier/LogView.swift`
- [ ] 修改 `Spotier/LogParser.swift`
- [ ] 修改 `SpotierNE/PacketTunnelProvider.swift`
- [ ] 修改 `SpotierNE/TunnelHelper.swift`
- [ ] 全仓搜索并清零硬编码 `group.com.alick.swiftier`

### B. 配置目录访问重构

- [ ] 新增 `ConfigDirectoryAccess.swift`
- [ ] 新增 `ConfigFileRepository.swift`
- [ ] 修改 `Spotier/ConfigManager.swift`，收缩为 facade 或迁移职责
- [ ] 修改 `Spotier/ContentView.swift` 的 `createConfig()` / `deleteSelectedConfig()`
- [ ] 修改 `Spotier/ConfigEditorView.swift` 的 `saveContent()`
- [ ] 修改 `Spotier/ConfigGeneratorView.swift` 的 `generateAndSave()` / `loadFromFile()`

### C. 主界面状态与布局规则重构

- [ ] 新增 `MainDashboardState.swift`
- [ ] 新增 `MainOverlayRoute.swift`
- [ ] 新增 `DashboardLayoutMetrics.swift`
- [ ] 修改 `Spotier/ContentView.swift`
- [ ] 修改 `Spotier/SpotierRunner.swift`
- [ ] 评估并修改 `Spotier/VPNManager.swift`
- [ ] 视需要修改 `Spotier/SpotierControlApp.swift`
- [ ] 视需要修改 `Spotier/CliClient.swift`

### D. 配置生成器重构

- [ ] 新增 `SpotierConfigDraft.swift`
- [ ] 新增 `SpotierConfigCodec.swift`
- [ ] 新增 `ConfigDraftStore.swift`
- [ ] 新增 `ConfigGeneratorStore.swift`
- [ ] 新增动态列表字段原语文件
- [ ] 大幅拆分 `Spotier/ConfigGeneratorView.swift`
- [ ] 校验 `IPv4Field` / `IPv4CidrField` 是否继续保留在原文件，还是提到公共字段文件

### E. UI 原语统一

- [ ] 扩展或重构 `Spotier/SharedComponents.swift`
- [ ] 新增 `FloatingScrollTopButton.swift`
- [ ] 新增 `CopyableDetailRow.swift`
- [ ] 修改 `Spotier/EventListView.swift`
- [ ] 修改 `Spotier/LogListView.swift`
- [ ] 修改 `Spotier/PeerCard.swift`
- [ ] 修改 `Spotier/LogView.swift`

### F. 测试与工程接线

- [ ] 修改 `Spotier.xcodeproj/project.pbxproj`
- [ ] 新增 `SpotierTests` target 或同等 app 侧测试承载
- [ ] 添加 4~5 个领域测试文件
- [ ] 保留并继续运行 `SpotierNETests`

## 6. 实施顺序建议

必须按以下顺序推进，避免一边拆 UI 一边改底层契约：

1. 统一共享常量与 App Group
2. 收敛配置目录访问与安全域写删能力
3. 修复 session 生命周期与主界面状态源
4. 拆 `ContentView`
5. 拆 `ConfigGeneratorView`
6. 统一日志/设置/列表原语
7. 补测试并做回归

原因：

1. App Group 和配置目录访问属于底层契约，必须先固定，否则上层抽象仍会建立在错误前提上。
2. `sessionID` 和主界面状态源会直接决定后续页面壳如何设计。
3. `ConfigGeneratorView` 依赖文件访问和保存流程，必须在 repository 定型后再拆。

## 7. 验收标准

### 功能验收

- [ ] 设置页修改日志等级后，NE 和主 App 读取到同一份值
- [ ] 日志视图能够打开正确的共享日志文件
- [ ] 自定义目录下创建配置成功
- [ ] 自定义目录下删除配置成功
- [ ] 配置编辑器保存成功
- [ ] 配置生成器新增/删除任意动态行时不崩溃、不串值
- [ ] VPN 重连后，节点卡片按新 session 正确重建，旧详情/动画状态不泄漏

### 结构验收

- [ ] `ContentView.swift` 不再直接负责文件读写
- [ ] `ConfigGeneratorView.swift` 不再同时承担 model/store/codec/UI
- [ ] App Group / 日志文件名 / iCloud 容器只存在一个权威定义源
- [ ] 关键 layout 规则集中到单独模块
- [ ] 关键行为有对应测试

## 8. 风险与回滚

主要风险：

1. 配置生成器拆分过程中，字段映射可能出现回归。
2. 安全域访问集中化后，如果接口设计不完整，可能影响 CloudKit 模式与自定义目录模式切换。
3. 主界面状态整合后，菜单栏图标、节点列表、速度卡片刷新节奏可能出现联动问题。

回滚策略：

1. 每个 Phase 独立提交，禁止把多个 Phase 混到一个 commit。
2. Phase 1 完成后先做一次可运行回归，再进入 Phase 2。
3. `ConfigGeneratorView` 拆分采用“小步迁移”：先保留原渲染结构，只替换 store/codec；再拆 section；最后替换动态列表原语。

## 9. 建议的提交切分

1. `refactor: unify runtime config and app group access`
2. `refactor: centralize scoped config file operations`
3. `fix: rotate runner session identity on reconnect`
4. `refactor: thin content view into dashboard shell`
5. `refactor: extract config generator domain and codec`
6. `refactor: replace index-based dynamic form bindings`
7. `refactor: unify log and list ui primitives`
8. `test: add app-side refactor coverage`
