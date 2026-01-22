#!/bin/bash
# 部署 NewsReport 到 GitHub Pages (blog 專案)
#
# 用法：./scripts/deploy-news.sh [commit message]

set -e

# 路徑設定
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")/NewsReport"
TARGET_REPO="$HOME/zoo/blog"
TARGET_DIR="$TARGET_REPO/news"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== 部署 NewsReport 到 GitHub Pages ===${NC}"

# 檢查來源目錄
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}錯誤：找不到來源目錄 $SOURCE_DIR${NC}"
    exit 1
fi

# 檢查目標 repo
if [ ! -d "$TARGET_REPO/.git" ]; then
    echo -e "${RED}錯誤：找不到目標 git repo $TARGET_REPO${NC}"
    exit 1
fi

# 生成報告索引
echo -e "${GREEN}生成報告索引...${NC}"
REPORTS=$(ls "$SOURCE_DIR"/*-news-report.md 2>/dev/null | xargs -I {} basename {} | sed 's/-news-report\.md//' | sort -r | jq -R . | jq -s .)
echo "{\"reports\": $REPORTS}" | jq . > "$SOURCE_DIR/reports.json"
echo "已生成 reports.json，包含 $(echo "$REPORTS" | jq length) 篇報告"

# 同步檔案
echo -e "${GREEN}同步檔案...${NC}"
mkdir -p "$TARGET_DIR"
rsync -av --delete \
    --exclude '.DS_Store' \
    "$SOURCE_DIR/" "$TARGET_DIR/"

# 進入目標 repo
cd "$TARGET_REPO"

# Git 操作
echo -e "${GREEN}提交變更...${NC}"
git add news/

# 檢查是否有變更
if git diff --cached --quiet; then
    echo -e "${YELLOW}沒有變更需要部署${NC}"
    exit 0
fi

COMMIT_MSG="${1:-chore: update news report $(date +%Y-%m-%d)}"
git commit -m "$COMMIT_MSG"

echo -e "${GREEN}推送到遠端...${NC}"
git push origin main

echo -e "${GREEN}=== 部署完成 ===${NC}"
echo -e "網址：https://yelban.github.io/blog/news/"
