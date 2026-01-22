---
name: daily-news-report
description: 基於預設 URL 列表抓取內容，篩選高質量技術資訊並生成每日 Markdown 報告。
argument-hint: [可選: 日期]
disable-model-invocation: false
user-invocable: true
allowed-tools: Task, WebFetch, Read, Write, Bash(mkdir*), Bash(date*), Bash(ls*), Skill(agent-browser), mcp__claude-in-chrome__*
---

# Daily Picks AI News v3.0

> **架構升級**：主 Agent 排程 + SubAgent 執行 + 瀏覽器抓取 + 智慧快取

## 核心架構

```
┌─────────────────────────────────────────────────────────────────────┐
│                        主 Agent (Orchestrator)                       │
│  職責：排程、監控、評估、決策、彙總                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐     │
│   │ 1. 初始化 │ → │ 2. 排程   │ → │ 3. 監控   │ → │ 4. 評估   │     │
│   │ 讀取配置  │    │ 分發任務  │    │ 收集結果  │    │ 篩選排序  │     │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘     │
│         │               │               │               │           │
│         ▼               ▼               ▼               ▼           │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐     │
│   │ 5. 決策   │ ← │ 達標？    │    │ 6. 生成   │ → │ 7. 更新   │     │
│   │ 繼續/停止 │    │ Y/N      │    │ 日報檔案  │    │ 快取統計  │     │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
         ↓ 排程                              ↑ 返回結果
┌─────────────────────────────────────────────────────────────────────┐
│                        SubAgent 執行層                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐              │
│   │ Worker A    │   │ Worker B    │   │ Browser     │              │
│   │ (WebFetch)  │   │ (WebFetch)  │   │ (Headless)  │              │
│   │ Tier1 Batch │   │ Tier2 Batch │   │ JS渲染頁面   │              │
│   └─────────────┘   └─────────────┘   └─────────────┘              │
│         ↓                 ↓                 ↓                        │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                    結構化結果返回                             │   │
│   │  { status, data: [...], errors: [...], metadata: {...} }    │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 配置檔案

本 Skill 使用以下配置檔案：

| 檔案 | 用途 |
|------|------|
| `sources.json` | 資訊源配置、優先順序、抓取方法、**全域參數** |
| `cache.json` | 快取資料、歷史統計、去重指紋 |

### 全域參數（sources.json → config）

```json
{
  "config": {
    "target_count": 20,           // 目標收錄數量
    "early_stop_total": 25,       // 早停門檻（總數）
    "early_stop_quality": 20,     // 早停門檻（高品質數）
    "min_quality_score": 3,       // 最低品質分數
    "sort_by": ["quality_score:desc", "source_priority:asc"]
  }
}
```

### 來源結構（sources.json → sources）

```json
{
  "sources": [
    {
      "id": "hn",                    // 唯一識別碼
      "name": "Hacker News",         // 顯示名稱
      "url": "https://...",          // 抓取網址
      "tier": 1,                     // 優先順序（1 最高，null 停用）
      "batch": "a",                  // 並行分組（同 tier 內 a/b 並行）
      "fetch_method": "webfetch",    // 抓取方式：webfetch | browser
      "requires_real_browser": false,// 僅 browser 用：true=claude-in-chrome, false=agent-browser
      "extract": "top_10",           // 截取規則
      "enabled": true                // 是否啟用
    }
  ]
}
```

**新增來源**：只需在 `sources` 陣列加一筆，設定 `tier`、`batch`、`enabled: true`
**瀏覽器來源**：若 `fetch_method: "browser"`，需設定 `requires_real_browser`（Cloudflare 等防護需設 `true`）

## 執行流程詳解

### Phase 1: 初始化

```yaml
步驟:
  1. 確定日期（使用者引數或當前日期）
  2. 讀取 sources.json 獲取源配置
  3. 讀取 cache.json 獲取歷史資料
  4. 建立輸出目錄 NewsReport/
  5. 檢查今日是否已有部分報告（追加模式）
```

### Phase 2: 排程 SubAgent

**策略**：並行排程，分批執行，早停機制

```yaml
第1波 (並行):
  - Worker A: Tier1 Batch A (HN, HuggingFace Papers)
  - Worker B: Tier1 Batch B (OneUsefulThing, Paul Graham)

等待結果 → 評估數量

如果 < config.target_count * 0.75 條高品質:
  第2波 (並行):
    - Worker C: Tier2 Batch A (James Clear, FS Blog)
    - Worker D: Tier2 Batch B (HackerNoon, Scott Young)

如果仍 < config.target_count 條:
  第3波 (瀏覽器):
    - Browser Worker: ProductHunt, Latent Space (需要JS渲染)
```

### Phase 3: SubAgent 任務格式

每個 SubAgent 接收的任務格式：

```yaml
task: fetch_and_extract
sources:
  - id: hn
    url: https://news.ycombinator.com
    extract: top_10
  - id: hf_papers
    url: https://huggingface.co/papers
    extract: top_voted

output_schema:
  items:
    - source_id: string      # 來源標識
      title: string          # 標題
      summary: string        # 2-4句摘要
      key_points: string[]   # 最多3個要點
      url: string            # 原文連結
      keywords: string[]     # 關鍵詞
      quality_score: 1-5     # 質量評分

constraints:
  filter: "前沿技術/高深技術/提效技術/實用資訊"
  exclude: "泛科普/營銷軟文/過度學術化/招聘帖"
  max_items_per_source: 10
  skip_on_error: true

return_format: JSON
```

### Phase 4: 主 Agent 監控與反饋

主 Agent 職責：

```yaml
監控:
  - 檢查 SubAgent 返回狀態 (success/partial/failed)
  - 統計收集到的條目數量
  - 記錄每個源的成功率

反饋迴圈:
  - 如果某 SubAgent 失敗，決定是否重試或跳過
  - 如果某源持續失敗，標記為停用
  - 動態調整後續批次的源選擇

決策（參照 config）:
  - 條目數 >= early_stop_total 且高品質 >= early_stop_quality → 停止抓取
  - 條目數 < target_count * 0.75 → 繼續下一批
  - 所有批次完成但 < target_count → 用現有內容生成（寧缺毋濫）
```

### Phase 5: 評估與篩選

```yaml
去重:
  - 基於 URL 完全匹配
  - 基於標題相似度 (>80% 視為重複)
  - 檢查 cache.json 避免與歷史重複

評分校準:
  - 統一各 SubAgent 的評分標準
  - 根據來源可信度調整權重
  - 手動標註的高質量源加分

排序（參照 config.sort_by）:
  - 按 quality_score 降序
  - 同分按來源優先順序排序
  - 擷取 Top {target_count}
```

### Phase 6: 瀏覽器抓取 (JS 渲染頁面)

對於 `fetch_method: "browser"` 的來源，根據 `requires_real_browser` 欄位選擇工具：

```yaml
決策邏輯:
  if source.requires_real_browser == true:
    使用 claude-in-chrome  # 真實瀏覽器，可通過 Cloudflare 等防護
  else:
    使用 agent-browser     # Headless 瀏覽器，速度較快
    if agent-browser 失敗:
      fallback 到 claude-in-chrome

agent-browser 流程（requires_real_browser: false）:
  1. agent-browser open <url>
  2. agent-browser wait 3000
  3. agent-browser snapshot -c（或處理彈窗後再 snapshot）
  4. 解析 snapshot 提取文章列表
  5. agent-browser close

claude-in-chrome 流程（requires_real_browser: true）:
  1. mcp__claude-in-chrome__tabs_context_mcp 取得/建立 tab group
  2. mcp__claude-in-chrome__tabs_create_mcp 建立新 tab
  3. mcp__claude-in-chrome__navigate 導航到目標 URL
  4. mcp__claude-in-chrome__computer(action: wait, duration: 3) 等待載入
  5. mcp__claude-in-chrome__computer(action: screenshot) 確認頁面狀態
  6. mcp__claude-in-chrome__read_page 或 find 提取內容

來源配置範例:
  - ProductHunt: requires_real_browser: true  # Cloudflare 防護
  - Latent Space: requires_real_browser: false # agent-browser 可處理
```

### Phase 7: 生成日報

```yaml
輸出:
  - 目錄: NewsReport/
  - 檔名: YYYY-MM-DD-news-report.md
  - 格式: 標準 Markdown

內容結構:
  - 標題 + 日期
  - 統計摘要（源數量、收錄數量）
  - {target_count} 條高品質內容（按模板）
  - 生成資訊（版本、時間戳）
```

### Phase 8: 更新快取

```yaml
更新 cache.json:
  - last_run: 記錄本次執行資訊
  - source_stats: 更新各源統計資料
  - url_cache: 新增已處理的 URL
  - content_hashes: 新增內容指紋
  - article_history: 記錄收錄文章
```

## SubAgent 呼叫示例

### 使用 general-purpose Agent

由於自定義 agent 需要 session 重啟才能發現，可以使用 general-purpose 並注入 worker prompt：

```
Task 呼叫:
  subagent_type: general-purpose
  model: haiku
  prompt: |
    你是一個無狀態的執行單元。只做被分配的任務，返回結構化 JSON。

    任務：抓取以下 URL 並提取內容

    URLs:
    - https://news.ycombinator.com (提取 Top 10)
    - https://huggingface.co/papers (提取高投票論文)

    輸出格式：
    {
      "status": "success" | "partial" | "failed",
      "data": [
        {
          "source_id": "hn",
          "title": "...",
          "summary": "...",
          "key_points": ["...", "...", "..."],
          "url": "...",
          "keywords": ["...", "..."],
          "quality_score": 4
        }
      ],
      "errors": [],
      "metadata": { "processed": 2, "failed": 0 }
    }

    篩選標準：
    - 保留：前沿技術/高深技術/提效技術/實用資訊
    - 排除：泛科普/營銷軟文/過度學術化/招聘帖

    直接返回 JSON，不要解釋。
```

### 使用 worker Agent（需重啟 session）

```
Task 呼叫:
  subagent_type: worker
  prompt: |
    task: fetch_and_extract
    input:
      urls:
        - https://news.ycombinator.com
        - https://huggingface.co/papers
    output_schema:
      - source_id: string
      - title: string
      - summary: string
      - key_points: string[]
      - url: string
      - keywords: string[]
      - quality_score: 1-5
    constraints:
      filter: 前沿技術/高深技術/提效技術/實用資訊
      exclude: 泛科普/營銷軟文/過度學術化
```

## 輸出模板

```markdown
# Daily Picks AI News（YYYY-MM-DD）

> 本日篩選自 N 個資訊源，共收錄 {target_count} 條高品質內容
> 生成耗時: X 分鐘 | 版本: v3.0
>
> **Warning**: Sub-agent 'worker' not detected. Running in generic mode (Serial Execution). Performance might be degraded.
> **警告**：未檢測到 Sub-agent 'worker'。正在以通用模式（序列執行）執行。效能可能會受影響。

---

## 1. 標題

- **摘要**：2-4 行概述
- **要點**：
  1. 要點一
  2. 要點二
  3. 要點三
- **來源**：[連結](URL)
- **關鍵詞**：`keyword1` `keyword2` `keyword3`
- **評分**：⭐⭐⭐⭐⭐ (5/5)

---

## 2. 標題
...

---

*Generated by Daily Picks AI News v3.0*
*Sources: HN, HuggingFace, OneUsefulThing, ...*
```

## 約束與原則

1. **寧缺毋濫**：低質量內容不進入日報
2. **早停機制**：達 config.early_stop_quality 條高品質就停止抓取
3. **並行優先**：同一批次的 SubAgent 並行執行
4. **失敗容錯**：單個源失敗不影響整體流程
5. **快取複用**：避免重複抓取相同內容
6. **主 Agent 控制**：所有決策由主 Agent 做出
7. **Fallback Awareness**：檢測 sub-agent 可用性，不可用時優雅降級

## 預期效能

| 場景 | 預期時間 | 說明 |
|------|----------|------|
| 最優情況 | ~2 分鐘 | Tier1 足夠，無需瀏覽器 |
| 正常情況 | ~3-4 分鐘 | 需要 Tier2 補充 |
| 需要瀏覽器 | ~5-6 分鐘 | 包含 JS 渲染頁面 |

## 錯誤處理

| 錯誤型別 | 處理方式 |
|----------|----------|
| SubAgent 超時 | 記錄錯誤，繼續下一個 |
| 源 403/404 | 標記停用，更新 sources.json |
| 內容提取失敗 | 返回原始內容，主 Agent 決定 |
| 瀏覽器崩潰 | 跳過該源，記錄日誌 |

## 相容性與兜底 (Compatibility & Fallback)

為了確保在不同 Agent 環境下的可用性，必須執行以下檢查：

1.  **環境檢查**:
    -   在 Phase 1 初始化階段，嘗試檢測 `worker` sub-agent 是否存在。
    -   如果不存在（或未安裝相關外掛），自動切換到 **序列執行模式 (Serial Mode)**。

2.  **序列執行模式**:
    -   不使用 parallel block。
    -   主 Agent 依次執行每個源的抓取任務。
    -   雖然速度較慢，但保證基本功能可用。

3.  **使用者提示**:
    -   必須在生成的日報開頭（引用塊部分）包含明顯的警告資訊，提示使用者當前正在運行於降級模式。
