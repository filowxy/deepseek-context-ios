# Checklist: deepseek-context-ios

## ① Execution Checklist

### 阶段 1：项目骨架与基础配置
- [ ] 1.1 创建 Xcode SwiftUI App 项目，目标 iOS 17+
- [ ] 1.2 创建 Models / Services / Views / Resources / Tests 目录结构
- [ ] 1.3 配置 `.github/workflows/ios-build.yml` 远程编译工作流

### 阶段 2：数据层
- [ ] 2.1 实现 `DatabaseManager.swift`：SQLite3 打开、PRAGMA、8 张表 + FTS5 虚拟表 + 触发器
- [ ] 2.2 定义全部数据模型（Conversation, ContextMark, Tag, GlobalContext, GlobalSuggestionLog, Skill, RecallResult）
- [ ] 2.3 实现 `ConversationDAO.swift`：增删改查、归档、删除限制、活跃数统计
- [ ] 2.4 实现 `ContextMarkDAO.swift`：UPSERT、软删除/恢复、编号规则、幂等键
- [ ] 2.5 实现 `TagDAO.swift`：标签关联、按标签查标记
- [ ] 2.6 实现 `SearchDAO.swift`：FTS5 BM25 搜索，自动附加 `deleted = 0`
- [ ] 2.7 实现对话计数 DAO：递增、纠偏、子对话继承
- [ ] 2.8 实现全局上下文与建议日志 DAO

### 阶段 3：核心上下文引擎
- [ ] 3.1 实现 `ContextEngine.swift`：标记创建/删除/恢复、参数校验、幂等键生成
- [ ] 3.2 实现 `ReminderEngine.swift`：首次第 5 轮 + 等级周期提醒
- [ ] 3.3 实现 `RecallEngine.swift`：FTS5 + 标签匹配排序管道、search_id、截断
- [ ] 3.4 实现 `ConversationManager.swift`：对话创建、延续继承、归档、删除限制、软上限 50

### 阶段 4：WebView 注入层
- [ ] 4.1 实现 `DeepSeekWebView.swift`：UIViewRepresentable 包装 WKWebView，加载 chat.deepseek.com
- [ ] 4.2 实现 `Resources/injected.js`：DOM 检测、JS API、MutationObserver 200ms 稳定性、健康检测
- [ ] 4.3 实现 `WebViewCoordinator.swift`：WKNavigationDelegate / WKScriptMessageHandler、滑动窗口降级
- [ ] 4.4 实现 `MessageParser.swift`：全部 9 种 XML 标签解析、思考过程过滤、JSON 错误处理
- [ ] 4.5 实现 `ScriptInjector.swift`：系统提示、轮次信息、skill-load、全局上下文、触发发送

### 阶段 5：工具调用与 MCP
- [ ] 5.1 实现 `SearchTool.swift`：Bing API v7 + DuckDuckGo 回退、quick/normal/detailed、超时 10s
- [ ] 5.2 实现 `BrowseTool.swift`：URLSession 抓取、readability、2MB 限制、15s 超时
- [ ] 5.3 实现 `ToolQueue.swift`：同类型并发 1、总超时 30s、丢弃未执行调用

### 阶段 6：技能系统
- [ ] 6.1 实现 `SkillManager.swift`：Skill 模型与存储、全局/项目作用域
- [ ] 6.2 实现 Skill 排序与前 10 截取、`<skill-load>` 生成
- [ ] 6.3 实现 `SkillDispatcher.swift`：`<call-skill>` 拦截、上下文重放、空输入校验

### 阶段 7：SwiftUI 界面
- [ ] 7.1 实现 `ConversationListView.swift`：活跃列表、软上限提示、新建/归档/删除
- [ ] 7.2 实现 `ChatView.swift`：WebView 容器、输入栏、标题/计数、降级提示
- [ ] 7.3 实现 `ContextManagerView.swift`：标记列表、全文搜索、标签筛选、删/恢复
- [ ] 7.4 实现 `ConversationManagementView.swift`：新建、延续、归档/恢复
- [ ] 7.5 实现 `GlobalContextPromptView.swift`：确认卡片、10 秒自动注入、接受/拒绝/编辑

### 阶段 8：APP 自动注入与协议闭环
- [ ] 8.1 实现发送前 `<system>当前对话轮次: N</system>` 注入
- [ ] 8.2 实现被动提醒注入（按等级周期）
- [ ] 8.3 实现全局上下文确认后注入与 `<skill-load>` 注入
- [ ] 8.4 实现长按 AI 回复选择文本并引用到输入框

### 阶段 9：错误处理与验证
- [ ] 9.1 实现 `ErrorHandler.swift`：覆盖文档第十二章全部错误场景
- [ ] 9.2 编写并跑通单元测试套件（Database / Context / Recall / MessageParser / Tools / Skills）
- [ ] 9.3 GitHub Actions `xcodebuild test` 全绿，人工审查关键逻辑

---

## ② Checkout List（合规与验证）

### 项目规则合规
- [ ] 无未明确请求的抽象类/协议
- [ ] 无不必要的第三方依赖（优先 SQLite3 C API / WebKit / Security / SwiftUI）
- [ ] 所有魔法数字已提取为常量
- [ ] 代码注释仅使用英文
- [ ] 每个非平凡逻辑至少有一个可运行的单元测试
- [ ] 数据库操作串行化，无多线程 SQLite 竞争

### 编译与测试验证
- [ ] `xcodebuild build` 在 GitHub Actions macOS runner 上成功
- [ ] `xcodebuild test` 在 GitHub Actions macOS runner 上成功
- [ ] 无 Swift 编译警告（除不可消除的系统警告外）
- [ ] 无硬编码 API Key 或凭证

### 安全与隐私
- [ ] Bing API Key 仅通过 Keychain 读取
- [ ] 登录凭证仅通过 Keychain 存储
- [ ] robots.txt 仅检查记录，不阻塞抓取逻辑

### 文档一致性
- [ ] 数据表结构与项目设计.md 3.1~3.8 一致
- [ ] XML 协议标签覆盖 7.2~7.13
- [ ] 提醒周期与 8.1 一致
- [ ] 错误处理覆盖第十二章

---

## ③ Self-Questioning（反思问题）

1. **依赖最小化**：是否确实需要引入第三方库？SQLite3 C API 是否足以覆盖 FTS5、UPSERT、WAL 等全部需求？
2. **编号与继承**：当父对话被归档后，子对话继承 mark_id 时是否仍能正确递增且不重复？是否已测试跨父子对话的编号边界？
3. **WebView 脆弱性**：如果 DeepSeek 前端 DOM 结构变化，injected.js 的健康检测和降级模式是否足够快地保护用户？连续 3 次失败和 30/10 滑动窗口的阈值是否合理？
4. **并发与超时**：ToolQueue 中 `<search>` 和 `<open>` 各自并发为 1，但总等待 30s 后丢弃未执行调用。当 AI 同时输出多个搜索请求时，是否存在死锁或队头阻塞导致全部超时？
5. **提醒与计数修正**：`last_remind_counter` 不受计数修正影响，但 `currentCount` 来自用户可修改的 conversation_counter。如果用户将计数从 100 改回 5，ReminderEngine 是否会出现异常提醒风暴？是否需要对修正后的首次提醒做特殊处理？
