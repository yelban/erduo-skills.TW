# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

**Erduo Skills** 是 AI Agent 技能庫，提供結構化能力與智慧工作流程。目前主要包含 **Daily Picks AI News** 技能，用於自動抓取、篩選並彙總多來源技術新聞。

## 架構

### Master-Worker 架構

```
主 Agent (Orchestrator)
├── 排程、監控、評估、決策、彙總
└── 排程 SubAgent 執行層
    ├── Worker A/B (WebFetch) - Tier1/Tier2 批次抓取
    └── Browser Worker (Headless Chrome) - JS 渲染頁面
```

### 關鍵設計原則

1. **早停機制**：達 20 條高品質內容即停止抓取
2. **並行優先**：同批次 SubAgent 並行執行
3. **失敗容錯**：單一來源失敗不影響整體流程
4. **降級模式**：worker agent 不可用時序列執行

## 目錄結構

```
.claude/agents/     # Agent 定義 (worker.md)
skills/             # 技能實作
  └── daily-news-report/
      ├── SKILL.md      # 技能主檔案（執行流程詳解）
      ├── sources.json  # 來源配置（tier1/tier2/tier3_browser）
      └── cache.json    # 快取資料、歷史統計、去重指紋
NewsReport/         # 產出的日報（YYYY-MM-DD-news-report.md）
```

## 執行技能

```bash
# 在支援 MCP 的 Agent 環境中執行
> "生成今天的日報"
> "Generate today's news report"
```

## 來源配置（sources.json）

扁平陣列結構，每個來源包含 `tier`、`batch`、`fetch_method` 欄位：

| 欄位 | 說明 | 範例值 |
|------|------|--------|
| `tier` | 優先順序（1 最高） | `1`, `2`, `3`, `null`（停用） |
| `batch` | 並行分組 | `"a"`, `"b"`, `null` |
| `fetch_method` | 抓取方式 | `"webfetch"`, `"browser"` |
| `requires_real_browser` | 需要真實瀏覽器（僅 browser） | `true`（Cloudflare）, `false` |
| `enabled` | 是否啟用 | `true`, `false` |

**新增來源**：在 `sources` 陣列加一筆即可
**瀏覽器來源**：`requires_real_browser: true` 使用 claude-in-chrome，`false` 使用 agent-browser

## SubAgent 呼叫

使用 `Task` 工具排程：

```yaml
subagent_type: worker  # 或 general-purpose（worker 不可用時）
model: haiku
prompt: |
  task: fetch_and_extract
  input: { urls: [...] }
  output_schema: { source_id, title, summary, key_points, url, keywords, quality_score }
  constraints: { filter: "前沿技術/實用資訊", exclude: "營銷軟文/招聘帖" }
```

## 允許的工具（daily-news-report）

`Task`, `WebFetch`, `Read`, `Write`, `Bash(mkdir*)`, `Bash(date*)`, `Bash(ls*)`, `Skill(agent-browser)`, `mcp__claude-in-chrome__*`

## 上游同步（Fork 維護）

本專案為 [rookie-ricardo/erduo-skills](https://github.com/rookie-ricardo/erduo-skills) 的繁體中文 fork。

### 本地化變更摘要

| 檔案 | 變更項目 | 說明 |
|------|----------|------|
| 全部 `.md` | 繁體中文化 | `opencc s2twp` 轉換 |
| `sources.json` | 結構重構 | 巢狀 → 扁平陣列（v3.0） |
| `sources.json` | 可配置參數 | 新增 `config` 區塊 |
| `sources.json` | 瀏覽器選擇 | 新增 `requires_real_browser` 欄位 |
| `SKILL.md` | allowed-tools | 加入 `Skill(agent-browser)`, `mcp__claude-in-chrome__*` |
| `SKILL.md` | Phase 6 流程 | 根據 `requires_real_browser` 選擇瀏覽器工具 |
| `SKILL.md` | 參數引用 | 硬編碼數字 → 引用 `config.*` |
| `README*.md` | 環境需求 | 加入 agent-browser、claude-in-chrome |
| `README*.md` | 安裝說明 | 新增方式1/方式2 詳細步驟 |

### Remote 配置

```
origin   → 本 fork（繁體中文版）
upstream → https://github.com/rookie-ricardo/erduo-skills.git
```

### 同步流程

> ⚠️ 本 fork 有多項結構性變更，無法直接 merge，需按以下步驟處理

```bash
# 1. 拉取上游更新
git fetch upstream

# 2. 查看上游變更
git diff HEAD...upstream/main --stat
git diff HEAD...upstream/main -- skills/daily-news-report/sources.json

# 3. 合併非結構性檔案（如 worker.md、cache.json）
git checkout upstream/main -- .claude/agents/worker.md
git checkout upstream/main -- skills/daily-news-report/cache.json
# 注意：不要直接 checkout SKILL.md、README、sources.json

# 4. 手動處理 sources.json（若上游有新增來源）
# 將上游新來源轉換為扁平格式加入 sources 陣列：
# - webfetch 來源: { "id": "xxx", "url": "...", "tier": N, "batch": "a", "fetch_method": "webfetch", "enabled": true }
# - browser 來源:  { "id": "xxx", "url": "...", "tier": 3, "batch": null, "fetch_method": "browser", "requires_real_browser": false, "enabled": true }
# 注意：browser 來源需測試是否有 Cloudflare 防護，有則設 requires_real_browser: true

# 5. 手動處理 SKILL.md（若上游有更新）
# 合併上游內容後，重新套用以下本地化修改：
#   - allowed-tools: 加入 Skill(agent-browser), mcp__claude-in-chrome__*
#   - Phase 6: 根據 requires_real_browser 欄位選擇 agent-browser 或 claude-in-chrome
#   - 來源結構: 加入 requires_real_browser 欄位說明
#   - 數字參數: 改為引用 config（target_count, early_stop 等）

# 6. 手動處理 README（若上游有更新）
# 合併上游內容後，重新套用：
#   - 環境需求: agent-browser skill + claude-in-chrome MCP
#   - 瀏覽器說明: 根據 requires_real_browser 自動選擇工具
#   - 安裝說明: 方式1/方式2

# 7. 繁體中文化
for f in $(find . -name "*.md" -not -path "./.git/*"); do
  opencc -c s2twp -i "$f" -o "$f.tmp" && mv "$f.tmp" "$f"
done

# 8. 驗證 JSON 語法
python3 -m json.tool skills/daily-news-report/sources.json > /dev/null

# 9. 提交變更
git add -A && git commit -m "chore: sync upstream and apply local customizations"
```

### sources.json 結構對照

```
上游結構（巢狀）              本地結構（扁平 v3.0）
─────────────────────────    ─────────────────────────
sources.tier1.batch_a[0]  →  sources[i] { tier: 1, batch: "a" }
sources.tier2.batch_b[0]  →  sources[i] { tier: 2, batch: "b" }
sources.tier3_browser[0]  →  sources[i] { tier: 3, fetch_method: "browser", requires_real_browser: true/false }
sources.disabled[0]       →  sources[i] { enabled: false, tier: null }

requires_real_browser 欄位（本地新增）:
  - true  → 使用 claude-in-chrome（Cloudflare 等防護）
  - false → 使用 agent-browser（一般 JS 渲染）
```

### 注意事項

- `opencc -c s2twp`：簡體→繁體（台灣用語+詞彙轉換）
- `sources.json` 需手動轉換結構，不能直接 merge
- 新增來源時記得設定 `tier`、`batch`、`enabled` 欄位
- browser 來源需設定 `requires_real_browser`（測試 Cloudflare 防護後決定 true/false）
- 上游若有重大結構變更，需評估是否調整本地結構
