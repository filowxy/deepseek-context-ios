# Goal: deepseek-context-ios

## 目标概述

基于 [项目设计.md](file:///d:/.trae-project/deepseek+app/项目设计.md) 完整实现 iOS APP：在 SwiftUI 内嵌 WKWebView 加载 chat.deepseek.com，通过 JS 注入与 XML 协议增强 AI 长对话上下文管理能力（标记、提醒、搜索、引用、全局上下文、技能系统、联网搜索）。

**约束**：当前无 macOS/Xcode，代码编写后通过 GitHub Actions macOS runner 远程编译验证，同时辅以人工审查。

**依赖策略**：优先使用 iOS 系统框架（SwiftUI、WebKit、SQLite3 C API、Security/Keychain），不引入 GRDB 等第三方库，保持最小依赖。

---

## 阶段 1：项目骨架与基础配置

### 任务 1.1：创建 Xcode 项目
- **文件**：`DeepSeekContext/DeepSeekContext.xcodeproj/project.pbxproj`（生成）、`DeepSeekContext/DeepSeekContextApp.swift`
- **当前行为**：无项目
- **目标行为**：创建 SwiftUI App 项目，bundle ID 可配置，目标 iOS 17+，启用 Swift Concurrency、SwiftData 不启用（使用 SQLite3）
- **依赖**：无
- **验证**：GitHub Actions 能 checkout 并 `xcodebuild build` 通过

### 任务 1.2：定义目录结构
- **文件**：创建以下目录
  - `DeepSeekContext/Models/`
  - `DeepSeekContext/Services/Database/`
  - `DeepSeekContext/Services/Context/`
  - `DeepSeekContext/Services/WebView/`
  - `DeepSeekContext/Services/Tools/`
  - `DeepSeekContext/Services/Skills/`
  - `DeepSeekContext/Views/`
  - `DeepSeekContext/Resources/`
  - `DeepSeekContextTests/`
- **当前行为**：无
- **目标行为**：目录完整
- **依赖**：1.1
- **验证**：目录存在

### 任务 1.3：配置 GitHub Actions 编译工作流
- **文件**：`.github/workflows/ios-build.yml`
- **当前行为**：无 CI
- **目标行为**：每次 push 使用 `macos-latest` runner 执行 `xcodebuild -scheme DeepSeekContext -destination 'platform=iOS Simulator,name=iPhone 15' build`
- **依赖**：1.1
- **验证**：推送后 Actions 成功

---

## 阶段 2：数据层

### 任务 2.1：SQLite 数据库初始化
- **文件**：`DeepSeekContext/Services/Database/DatabaseManager.swift`
- **当前行为**：无数据库
- **目标行为**：
  - 单例 `DatabaseManager`
  - 使用 `sqlite3_open_v2` 打开沙盒内 `deepseek_context.sqlite`
  - 执行 PRAGMA：`foreign_keys = ON`、`journal_mode = WAL`
  - 建表 SQL 覆盖文档 3.1~3.8 全部表结构
  - 创建 FTS5 虚拟表与 INSERT/DELETE/UPDATE 触发器
- **依赖**：1.2
- **验证**：单元测试 `DatabaseManagerTests.testSchemaCreation` 确认 8 张表存在

### 任务 2.2：数据模型定义
- **文件**：
  - `DeepSeekContext/Models/Conversation.swift`
  - `DeepSeekContext/Models/ContextMark.swift`
  - `DeepSeekContext/Models/Tag.swift`
  - `DeepSeekContext/Models/GlobalContext.swift`
  - `DeepSeekContext/Models/GlobalSuggestionLog.swift`
  - `DeepSeekContext/Models/Skill.swift`
  - `DeepSeekContext/Models/RecallResult.swift`
- **当前行为**：无模型
- **目标行为**：Swift struct/class 与文档字段一一对应，日期统一使用 ISO8601 字符串存储
- **依赖**：无
- **验证**：编译通过

### 任务 2.3：Conversation DAO
- **文件**：`DeepSeekContext/Services/Database/ConversationDAO.swift`
- **当前行为**：无
- **目标行为**：
  - `insert(_:)`
  - `update(_:)`
  - `fetchActive(orderBy:)`（按 updated_at 倒序）
  - `fetchAll()`
  - `archive(id:)`（is_active = 0）
  - `delete(id:)`（仅当无子对话时允许）
  - `countActive()`（活跃对话数，用于软上限 50 检查）
- **依赖**：2.1、2.2
- **验证**：单元测试覆盖增删改查与上限计数

### 任务 2.4：ContextMark DAO
- **文件**：`DeepSeekContext/Services/Database/ContextMarkDAO.swift`
- **当前行为**：无
- **目标行为**：
  - `upsert(_:)` 幂等键冲突时更新 content/tags，deleted 重置为 0
  - `fetch(byConversationId:)`
  - `fetch(byId:)`
  - `softDelete(id:)` 设置 deleted=1、deleted_at
  - `recover(id:)` 设置 deleted=0
  - `nextMarkId(for conversationId:)` 返回当前对话最大 mark_id + 1
  - `nextMarkIdWithParent(for conversationId:, parentId:)` 继承父对话编号规则
- **依赖**：2.1、2.2
- **验证**：单元测试覆盖编号递增、继承、软删除恢复、幂等键更新

### 任务 2.5：Tag DAO
- **文件**：`DeepSeekContext/Services/Database/TagDAO.swift`
- **当前行为**：无
- **目标行为**：
  - `setTags(for markId:, tags:)` 先删后插
  - `fetchTags(for markId:)`
  - `fetchMarkIds(byTag:)`
- **依赖**：2.1、2.2
- **验证**：单元测试覆盖标签关联查询

### 任务 2.6：FTS5 搜索 DAO
- **文件**：`DeepSeekContext/Services/Database/SearchDAO.swift`
- **当前行为**：无
- **目标行为**：
  - `searchFullText(query:, limit:)` 使用 `context_marks_fts` BM25 排序
  - 所有查询自动附加 `WHERE cm.deleted = 0`
  - 返回 `RecallResult.Item` 数组
- **依赖**：2.1、2.2
- **验证**：单元测试验证插入后全文搜索命中、删除后不再命中

### 任务 2.7：ConversationCounter DAO
- **文件**：合并到 `ConversationDAO.swift` 或独立 `ConversationCounterDAO.swift`
- **当前行为**：无
- **目标行为**：
  - `getCount(for:)`
  - `increment(for:)`
  - `setCount(for:, count:)`（手动纠偏）
  - 新建子对话时 `initializeFromParent(child:, parent:)`
- **依赖**：2.1、2.2
- **验证**：单元测试覆盖计数递增与继承

### 任务 2.8：GlobalContext & SuggestionLog DAO
- **文件**：合并到 `ConversationDAO.swift` 或独立 `GlobalContextDAO.swift`
- **当前行为**：无
- **目标行为**：
  - GlobalContext：增删改查、软删除
  - SuggestionLog：记录 AI 建议、接受/拒绝状态、rejection_feedback
- **依赖**：2.1、2.2
- **验证**：单元测试覆盖建议日志状态流转

---

## 阶段 3：核心上下文引擎

### 任务 3.1：ContextEngine
- **文件**：`DeepSeekContext/Services/Context/ContextEngine.swift`
- **当前行为**：无
- **目标行为**：
  - `createMark(type:, lev:, content:, tags:, conversationId:, messageIndex:, sequence:)`
  - `deleteMark(id:)` / `recoverMark(id:)`
  - 校验 `lev ∈ [0,3]`、`type ∈ [userask, complex]`、`content` 非空
  - 生成 idem_key：`{conversation_id}_{message_index}_{type}_{sequence}`
- **依赖**：2.4、2.5
- **验证**：单元测试覆盖非法参数拒绝、幂等键生成、UPSERT

### 任务 3.2：ReminderEngine
- **文件**：`DeepSeekContext/Services/Context/ReminderEngine.swift`
- **当前行为**：无
- **目标行为**：
  - `shouldRemind(mark:, currentCount:)`
  - 首次提醒第 5 轮，后续周期：lev0 每 10 轮、lev1 每 20 轮、lev2 每 30 轮、lev3 每 50 轮
  - 更新 `last_remind_counter`
- **依赖**：2.4
- **验证**：单元测试覆盖各等级周期

### 任务 3.3：RecallEngine
- **文件**：`DeepSeekContext/Services/Context/RecallEngine.swift`
- **当前行为**：无
- **目标行为**：
  - `recall(query:, scope:, conversationId:, parentId:, limit:)`
  - scope：`current` / `parent` / `all`
  - 排序管道：FTS5 命中按 BM25 → 标签精确匹配按 created_at 倒序 → 截取前 N
  - 生成 `search_id`、返回 total / truncated / message
- **依赖**：2.6、2.5
- **验证**：单元测试覆盖 FTS5 排序、标签追加、截断、search_id 生成

### 任务 3.4：ConversationManager
- **文件**：`DeepSeekContext/Services/Context/ConversationManager.swift`
- **当前行为**：无
- **目标行为**：
  - `createConversation(title:)`
  - `linkChild(childId:, parentId:)` 一次性建立延续关系
  - `archiveConversation(id:)` 父对话允许归档但保留延续关系
  - `deleteConversation(id:)` 已有子对话的父对话禁止删除
  - `activeConversationCount()` 软上限 50 检查（有子对话的父对话不计入）
  - 子对话创建时继承标记库、项目技能、对话计数
- **依赖**：2.3、2.7、3.1
- **验证**：单元测试覆盖继承、归档、删除限制、配额计算

---

## 阶段 4：WebView 注入层

### 任务 4.1：DeepSeekWebView 视图封装
- **文件**：`DeepSeekContext/Services/WebView/DeepSeekWebView.swift`
- **当前行为**：无 WebView
- **目标行为**：
  - 使用 `UIViewRepresentable` 包装 `WKWebView`
  - 加载 `https://chat.deepseek.com`
  - 注入用户脚本 `injected.js`
  - 暴露回调：`onMessageFinalized`、JS 调用原生通道
- **依赖**：1.1
- **验证**：编译通过

### 任务 4.2：injected.js 脚本
- **文件**：`DeepSeekContext/Resources/injected.js`
- **当前行为**：无
- **目标行为**：
  - 检测关键 DOM 节点（输入框、发送按钮、消息气泡容器）
  - 提供 JS API：`setInputText(text)`、`clickSend()`、`getLatestMessageText()`
  - MutationObserver 监控消息气泡，200ms 内无变化视为渲染完毕
  - 向原生发送消息：`<message-finalized> ... </message-finalized>`
  - 健康检测：连续 3 次找不到关键节点时上报错误
- **依赖**：4.1
- **验证**：通过 UI 测试或 JS 单元测试（若有 Node 环境）验证选择器逻辑

### 任务 4.3：WebViewCoordinator
- **文件**：`DeepSeekContext/Services/WebView/WebViewCoordinator.swift`
- **当前行为**：无
- **目标行为**：
  - 实现 `WKNavigationDelegate`、`WKScriptMessageHandler`
  - 处理 `console`、`messageFinalized`、`domHealth` 等消息
  - 维护 30 次操作滑动窗口，失败 ≥10 次触发降级模式
- **依赖**：4.1
- **验证**：单元测试模拟消息验证降级触发

### 任务 4.4：XML 协议解析器
- **文件**：`DeepSeekContext/Services/WebView/MessageParser.swift`
- **当前行为**：无
- **目标行为**：
  - 解析 AI 最终回复中的 XML 标签：`<main>`、`<de-main>`、`<recover-mark>`、`<recall-context>`、`<all>`、`<search>`、`<open>`、`<call-skill>`、`<global-suggest>`
  - 忽略思考过程内容
  - JSON 解析失败时返回 `.parseError`，注入系统提示通知 AI 重试
- **依赖**：4.1
- **验证**：单元测试覆盖所有标签解析与错误场景

### 任务 4.5：ScriptInjector
- **文件**：`DeepSeekContext/Services/WebView/ScriptInjector.swift`
- **当前行为**：无
- **目标行为**：
  - `injectSystemPrompt(_:)` 将系统提示追加到输入框
  - `injectRoundInfo(round:, sequenceStart:)`
  - `injectSkillLoad(_:)`
  - `injectGlobalContext(_:)`
  - `sendCurrentInput()` 触发发送
- **依赖**：4.1、4.2
- **验证**：UI 测试验证注入文本出现在输入框

---

## 阶段 5：工具调用与 MCP

### 任务 5.1：SearchTool
- **文件**：`DeepSeekContext/Services/Tools/SearchTool.swift`
- **当前行为**：无
- **目标行为**：
  - 支持 Bing Web Search API v7（Keychain 读取 `bing_api_key`）
  - 未配置时回退 DuckDuckGo HTML 搜索
  - `quick` / `normal` / `detailed` 对应 3/7/10 条结果
  - 超时 10 秒
- **依赖**：1.1
- **验证**：单元测试使用 URLProtocol mock 网络响应

### 任务 5.2：BrowseTool
- **文件**：`DeepSeekContext/Services/Tools/BrowseTool.swift`
- **当前行为**：无
- **目标行为**：
  - URLSession 抓取，User-Agent `WorldScapeApp/1.0`
  - 超时 15 秒，最大 2MB
  - readability 算法提取正文，失败返回纯文本前 4000 字符
  - 遵守 robots.txt（仅检查并记录，不强制阻塞）
- **依赖**：1.1
- **验证**：单元测试 mock HTML 验证摘要格式

### 任务 5.3：ToolQueue
- **文件**：`DeepSeekContext/Services/Tools/ToolQueue.swift`
- **当前行为**：无
- **目标行为**：
  - 同类型工具最大并发 1（`<search>` 和 `<open>` 各自独立队列）
  - 总等待超时 30 秒
  - 超时后丢弃未执行调用，注入系统提示告知 AI
- **依赖**：5.1、5.2
- **验证**：单元测试模拟并发与超时

---

## 阶段 6：技能系统

### 任务 6.1：Skill 模型与存储
- **文件**：`DeepSeekContext/Services/Skills/SkillManager.swift`
- **当前行为**：无
- **目标行为**：
  - Skill 字段：name、whentouse、description、scope、lastUsedAt、updatedAt
  - 全局技能：所有对话可用
  - 项目技能：仅当前对话，子对话继承
- **依赖**：2.2
- **验证**：单元测试覆盖作用域查询

### 任务 6.2：Skill 排序与注入
- **文件**：合并到 `SkillManager.swift`
- **当前行为**：无
- **目标行为**：
  - 排序规则：最近使用 > 最近修改 > 名称字母序
  - 超过 10 个只取前 10
  - 生成 `<skill-load>` XML 注入
- **依赖**：6.1
- **验证**：单元测试覆盖排序与截断

### 任务 6.3：SkillDispatcher
- **文件**：`DeepSeekContext/Services/Skills/SkillDispatcher.swift`
- **当前行为**：无
- **目标行为**：
  - 拦截 `<call-skill>name:'xxx'</call-skill>`
  - 暂存用户原输入与当前对话上下文
  - 将 Skill description 作为系统消息注入并重放请求
  - 用户手动调用 Skill 时输入框为空则拒绝发送并提示「请输入内容」
- **依赖**：4.5、6.1
- **验证**：单元测试覆盖拦截与重放逻辑

---

## 阶段 7：SwiftUI 界面

### 任务 7.1：ConversationListView
- **文件**：`DeepSeekContext/Views/ConversationListView.swift`
- **当前行为**：无
- **目标行为**：
  - 显示活跃对话列表（updated_at 倒序）
  - 软上限 50 时提示归档旧对话
  - 支持新建、归档、删除（有子对话禁止删除）
- **依赖**：3.4
- **验证**：UI 测试或预览验证

### 任务 7.2：ChatView
- **文件**：`DeepSeekContext/Views/ChatView.swift`
- **当前行为**：无
- **目标行为**：
  - 嵌入 DeepSeekWebView
  - 底部输入栏、发送按钮
  - 顶部显示当前对话标题与计数
  - 降级模式提示卡片
- **依赖**：4.1、3.2
- **验证**：UI 测试或预览验证

### 任务 7.3：ContextManagerView
- **文件**：`DeepSeekContext/Views/ContextManagerView.swift`
- **当前行为**：无
- **目标行为**：
  - 展示当前对话标记列表
  - 搜索框：全文搜索 + 标签筛选
  - 支持删除/恢复标记
- **依赖**：3.1、3.3
- **验证**：UI 测试或预览验证

### 任务 7.4：ConversationManagementView
- **文件**：`DeepSeekContext/Views/ConversationManagementView.swift`
- **当前行为**：无
- **目标行为**：
  - 新建对话
  - 建立延续关系
  - 归档/恢复对话
- **依赖**：3.4
- **验证**：UI 测试或预览验证

### 任务 7.5：GlobalContextPromptView
- **文件**：`DeepSeekContext/Views/GlobalContextPromptView.swift`
- **当前行为**：无
- **目标行为**：
  - 新对话开始时弹出确认卡片
  - 展示全局上下文候选
  - 10 秒无操作自动注入
  - 用户可接受/拒绝/编辑
- **依赖**：2.8
- **验证**：UI 测试或预览验证

---

## 阶段 8：APP 自动注入与协议闭环

### 任务 8.1：轮次编号注入
- **文件**：`DeepSeekContext/Services/WebView/WebViewCoordinator.swift`
- **当前行为**：无
- **目标行为**：用户点击发送后，APP 向 AI 注入 `<system>当前对话轮次: N, 本轮标记序号从 1 开始</system>`
- **依赖**：4.3、2.7
- **验证**：单元测试验证注入时机与文本

### 任务 8.2：被动提醒注入
- **文件**：`DeepSeekContext/Services/Context/ReminderEngine.swift` + WebViewCoordinator
- **当前行为**：无
- **目标行为**：每条发言前检查需要提醒的标记，按等级周期拼接上下文文本注入
- **依赖**：3.2、4.5
- **验证**：单元测试覆盖各等级提醒周期

### 任务 8.3：全局上下文与技能列表注入
- **文件**：`DeepSeekContext/Services/WebView/WebViewCoordinator.swift`
- **当前行为**：无
- **目标行为**：
  - 新对话开始时注入全局上下文（10 秒确认后）
  - 对话开始时注入 `<skill-load>`
- **依赖**：2.8、6.2、4.5
- **验证**：单元测试验证注入内容

### 任务 8.4：引用功能
- **文件**：`DeepSeekContext/Services/WebView/DeepSeekWebView.swift`
- **当前行为**：无
- **目标行为**：长按 AI 回复 → 选择文本 → 确认引用 → 以原文形式注入输入框
- **依赖**：4.1
- **验证**：UI 测试或模拟 JS 调用验证

---

## 阶段 9：错误处理与验证

### 任务 9.1：错误处理映射
- **文件**：`DeepSeekContext/Services/ErrorHandler.swift`
- **当前行为**：无
- **目标行为**：实现文档第十二章全部错误场景，返回结构化错误并注入系统提示
- **依赖**：3.1、3.3、5.1、5.2、6.3、7.2
- **验证**：单元测试覆盖每个错误场景

### 任务 9.2：单元测试套件
- **文件**：`DeepSeekContextTests/*.swift`
- **当前行为**：无测试
- **目标行为**：
  - DatabaseManagerTests
  - ContextEngineTests
  - ReminderEngineTests
  - RecallEngineTests
  - ConversationManagerTests
  - MessageParserTests
  - SearchToolTests
  - BrowseToolTests
  - SkillTests
- **依赖**：全部前置阶段
- **验证**：GitHub Actions 中 `xcodebuild test` 通过

### 任务 9.3：编译验证与人工审查
- **文件**：`.github/workflows/ios-build.yml`、PR 说明
- **当前行为**：无
- **目标行为**：每个任务完成后 push 触发 CI build，人工检查关键 Swift 语法与逻辑
- **依赖**：全部
- **验证**：CI 全绿

---

## 非功能要求

- **语言**：代码注释使用英文（遵循用户规则）
- **常量**：所有魔法数字使用常量（提醒周期、200ms、30次/10次、软上限50、搜索条数等）
- **并发**：数据库操作必须在串行队列/actor 中执行，避免 SQLite 多线程问题
- **安全**：Keychain 仅存储 Bing API Key 与登录凭证，不硬编码密钥
