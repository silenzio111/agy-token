# AgyToken - AI 编程助手 Token 消耗与费用看板

集成支持 **Google Antigravity**、**OpenAI Codex** 与 **Anthropic Claude Code** 三大主流 AI 编程助手的极简本地桌面端监控看板。开箱即用，纯本地无侵入。

---

### ✨ 核心功能
1. **三大 AI 工具全自动扫描**：
   * ⚡ **Google Antigravity (`agy`)**：双路扫描 GUI 客户端（`~/.gemini/antigravity/`）与 CLI 终端版（`~/.gemini/antigravity-cli/`）的 SQLite 数据库与 Protobuf 生成元数据。
   * 💻 **OpenAI Codex**：自动解析 `~/.codex/state_5.sqlite` 与 Rollout 会话，秒级毫秒倒序提取 Prompt、Completion、Cache、Reasoning 分布。
   * 🤖 **Anthropic Claude Code**：自动扫描 `~/.claude/projects/` 全量会话，精准统计各模型（Sonnet、Opus、DeepSeek 等）的输入/输出与提示词缓存。
   * **快捷工具切换**：支持 `[ 🌐 全部工具 ]`、`[ ⚡ Antigravity ]`、`[ 💻 Codex ]`、`[ 🤖 Claude Code ]` 一键分流与总览切换。
2. **📈 现代暗黑极简趋势曲线图 (Linear / Apple Stocks 风格)**：
   * **纵向天幕渐变辉光 (Vertical Gradient Aura)**：告别生硬的纯色填充，使用自定义从 `#16171e` 到荧光青的高级纵向渐变光晕。
   * **多层霓虹光纤线条 (Glowing Strokes)**：采用三层发光渲染（外层发散光晕 + 中层亮光 + 核心锐利光纤），曲线柔润通透。
   * **极致无框视觉 (Seamless Borderless)**：彻底消除传统外框与坐标轴线（Spines），图表与背景浑然一体。
   * **峰值极光灯塔 (Glowing Beacon)**：告别珠串式的密集数据点，超过 10 天自动隐去冗余节点，仅在最高峰值点点亮三层极光光圈与悬浮气泡。
   * **单调保形平滑插值 (PCHIP Spline)**：无下冲与负值畸变，完美贴合真实走势。
   * **双曲线对比**：总 Token 消耗（荧光青）与模型生成输出（薄荷绿）。
   * **原生 Retina 高清浮层**：直接由 macOS Cocoa 引擎渲染矢量 Tooltip，鼠标悬停即时响应，清晰锐利无延迟。
   * 支持右上角一键 **`[ 📈 隐藏/展开图表 ]`**。
3. **多维时间段筛选**：
   * **快捷按钮**：`[ 今天 ]`、`[ 昨天 ]`、`[ 近 7 天 ]`、`[ 近 30 天 ]`、`[ 全部历史 ]`。
   * **自定义起止区间**：提供 `从 [起始日期 ▾] 至 [截止日期 ▾]` 下拉选择，精准选定任意跨度时间段。
4. **主界面单一时期聚焦**：
   * 4 大核心指标卡片（总消耗、预估费用、输入/输出明细、Prompt 缓存命中率）与下方表格**仅聚焦统计当前选定的单一时期**。
   * 顶部常驻 **🔥 今日最新消耗与费用实时看板**，随时掌握当天额度使用情况。
5. **💰 官方全量实时 API 价格库（3,800+ 规格）**：
   * 自动集成并拉取行业权威的官方标准模型价格数据库（包含 OpenAI、Anthropic、Google、DeepSeek 等全量 3,800+ 款官方/衍生模型规格）。
   * 精确区分各型号的真实官方单价（未缓存输入、输出、Prompt 缓存命中），告别粗暴估算。例如 `gpt-5.6-luna` 蒸馏模型官方实际输入仅需 **$0.20/1M**，计费真实还原。
   * 支持离线内置核心表兜底 + 手动/定时联网热更新，双击任意行可在详情浮层中直观查验单条会话匹配的官方单价与费率来源。
   * 支持一键切换 **人民币 (¥ CNY)** 与 **美元 ($ USD)**（汇率按 1:7.2 换算）。
6. **实时无感同步**：支持后台每 30 秒静默增量刷新，亦可手动点击“刷新”。
7. **会话详情下钻**：双击任一行可查看该会话的完整 Token 及费用细项，并支持一键复制 Conversation ID。
8. **💾 记忆与恢复上次使用状态**：
   * 自动记录退出时的**窗口尺寸与屏幕位置**（再次打开无需重新调整摆放）。
   * 自动恢复**AI 工具筛选模式**（全部 / Antigravity / Codex / Claude Code）。
   * 自动恢复**时间段模式**（今天 / 昨天 / 近 7 天 / 近 30 天 / 全部历史 / 自定义起止区间）。
   * 自动恢复**币种偏好**（¥ CNY / $ USD）、**图表折叠状态**（展开/收起）、**自动同步开关**及**搜索关键字**。
   * 配置保存在 `~/Library/Application Support/AgyToken/` 中，轻量透明、跨会话无缝接续。

---

### 🔍 Codex & Claude Code 统计原理

1. **OpenAI Codex**：
   * **纯 sessions 目录扫描**：彻底移除对 SQLite 数据库的任何依赖，直接扫描 `~/.codex/sessions/`（按 `YYYY/MM/DD/` 存放的各会话 `rollout-*.jsonl`）及 `~/.codex/archived_sessions/` 归档目录；首次完整读取，后续按文件大小与修改时间复用扫描缓存。
   * **自解析前置元数据**：直接从 JSONL 前 40 行提取首条用户需求（作为会话标题）以及 `turn_context` / `session_meta` 中的模型标识（如 `gpt-5-codex`、`gpt-5.6-terra` 等）。
   * **256KB 深度倒序探测 + 字节流兜底**：对发生变化的文件优先倒序探测尾部 256KB，精准截获 `"thread_token_usage"` 或 `"total_token_usage"` 聚合快照；若遇超长终端输出则全文件字节流快速捕获：
     - `input_tokens`（总输入，扣除缓存后为未缓存 Prompt）
     - `cached_input_tokens`（命中 Prompt Cache 的标记数）
     - `output_tokens`（实际生成的代码/回复标记数）
     - `reasoning_output_tokens`（深度推理/Thinking 思考标记数）
   * **真实本地时间提取**：直接从文件日志末尾事件提取 ISO 时间戳，结合文件 mtime，完全脱离外部数据库，零锁表、零依赖、100% 纯真物理统计。

2. **Anthropic Claude Code**：
   * **日志定位**：遍历扫描 `~/.claude/projects/*/*.jsonl` 下各个工作区的会话流。
   * **标准使用量提取**：依次解析每条 `type == 'assistant'` 的回复块中携带的 Anthropic 官方 `message.usage` 标准元数据：
     - `input_tokens`（未命中的基础 Prompt Tokens）
     - `cache_read_input_tokens`（命中提示词缓存的 Tokens，享受 9 折优惠）
     - `output_tokens`（生成的代码/文本输出）
     - `output_tokens_details.thinking_tokens`（Claude 3.7 Sonnet 的扩展思考过程）
   * 对单会话内全部轮次进行精确累加并提取首条用户 Prompt 作为任务摘要，结合当前模型（如 `claude-3-7-sonnet`）的阶梯 API 价格进行真实成本核算。

---

### 🚀 启动与安装方式

#### 方式 1：macOS 原生 App（推荐，开箱即用）
- 在当前文件夹中直接双击 **`AgyToken.app`**
- 也可以直接将 `AgyToken.app` 复制或拖拽至系统的 **`/Applications`**（访达 -> 应用程序），从启动台 (Launchpad) 或聚焦搜索 (Spotlight) 随时随地唤起。
- 命令行快速拉起：
  ```bash
  open "AgyToken.app"
  ```

#### 方式 2：双击脚本
- 双击 **`启动.command`**（后台静默拉起界面并自动退出终端）。

---

### 🛠️ 重新打包与构建原生 App

如对图标或代码进行了自定义修改，可在终端运行一键自动化打包脚本：
```bash
./Scripts/build_native_app.sh
```
脚本将自动完成：
1. 使用 Swift CoreGraphics 矢量渲染 10 档分辨率的 `AppIcon.icns`
2. 编译 SwiftUI 原生 Mach-O 应用程序
3. 组装并签名 `AgyToken.app`
