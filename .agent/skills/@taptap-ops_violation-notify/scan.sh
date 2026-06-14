#\!/bin/bash
# violation-notify 自动扫描脚本
# 在 build 前自动运行，检测 scripts/ 中的潜在违规风险

SCRIPTS_DIR="/workspace/scripts"
FOUND_ISSUES=0
REPORT=""

if [ \! -d "$SCRIPTS_DIR" ]; then
    echo "[violation-scan] scripts/ 目录不存在，跳过扫描"
    exit 0
fi

LUA_COUNT=$(find "$SCRIPTS_DIR" -name "*.lua" 2>/dev/null | wc -l)
if [ "$LUA_COUNT" -eq 0 ]; then
    echo "[violation-scan] 未发现 Lua 文件，跳过扫描"
    exit 0
fi

add_issue() {
    local category="$1"
    local violation_type="$2"
    local details="$3"
    REPORT="${REPORT}
--- [${category}] ${violation_type} ---
${details}
"
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
}

echo "[violation-scan] 开始扫描 scripts/ ..."
echo ""

# 1. 计费违规 (1.1)
HITS=$(grep -rnE "充值|内购|付费|支付|赞助|打赏|purchase|payment|recharge|donate|in.app.purchase|doPay|startPay|openPay|buyItem|buy_item" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null | grep -v "violation-scan-ignore")
if [ -n "$HITS" ]; then
    add_issue "计费违规" "1.1 偷开计费" "发现付费相关关键词（若游戏无版号则可能违规）:
$HITS"
fi

# 2. 分发违规 - 外部下载 (4.1)
HITS=$(grep -rnE "\.apk|\.ipa|下载链接|扫码下载|外部下载|官网下载|浏览器下载" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null | grep -v "violation-scan-ignore")
if [ -n "$HITS" ]; then
    add_issue "分发违规" "4.1 引导外部包下载" "发现疑似外部下载引导:
$HITS"
fi

# 3. 分发违规 - Q群 (4.2)
HITS=$(grep -rnE "QQ群|qq群|QQ 群|群号|加群|微信群|进群|入群|群聊|官方群" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null | grep -v "violation-scan-ignore")
if [ -n "$HITS" ]; then
    add_issue "分发违规" "4.2 引导Q群下载" "发现社交群组引导（引导加群+群内分发安装包才构成违规）:
$HITS"
fi

# 4. 运营违规 - 好评 (5.1)
HITS=$(grep -rnE "好评|五星|评分送|好评送|好评返|评价奖励|评论有奖|给个好评|打个好评|满分好评|评分领|评价领" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null | grep -v "violation-scan-ignore")
if [ -n "$HITS" ]; then
    add_issue "运营违规" "5.1 引导好评" "发现好评引导相关关键词:
$HITS"
fi

# 5. 游戏质量 - 敏感词 (7.2)
HAS_CHAT=$(grep -rlnE "聊天|chat|ChatInput|sendMessage|SendMessage|昵称|nickname|setNickname|SetNickname" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null)
if [ -n "$HAS_CHAT" ]; then
    HAS_FILTER=$(grep -rlnE "敏感词|sensitiveWord|wordFilter|badWord|profanity|censor|filterWord|屏蔽词|违禁词" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null)
    if [ -z "$HAS_FILTER" ]; then
        add_issue "游戏质量" "7.2 未屏蔽敏感词" "检测到聊天/昵称功能但未发现敏感词过滤:
涉及文件:
$HAS_CHAT"
    fi
fi

# 6. 外部链接检查
HITS=$(grep -rnE "https?://[^\"' ]{10,}" "$SCRIPTS_DIR" --include="*.lua" 2>/dev/null | grep -v "violation-scan-ignore" | grep -vE "taptap\.|tapimg\.|xdrnd\.|urhox\.|localhost|127\.0\.0\.1")
if [ -n "$HITS" ]; then
    add_issue "内容检查" "外部链接" "发现非平台域名的外部链接，请确认合规:
$HITS"
fi

# === 输出报告 ===
echo "================================"
echo "  violation-scan 扫描报告"
echo "================================"
echo ""

if [ $FOUND_ISSUES -eq 0 ]; then
    echo "[OK] 未发现明显违规风险，代码扫描通过"
    echo ""
    echo "[提醒] 自动扫描仅覆盖代码层面，以下仍需人工确认:"
    echo "  - 内容违规（色情/血腥/涉政）需检查实际画面"
    echo "  - 知识产权问题需确认素材授权"
    echo "  - 资质问题需在开发者中心确认"
    exit 0
else
    echo "发现 ${FOUND_ISSUES} 项潜在风险:"
    echo "$REPORT"
    echo "--------------------------------"
    echo "[提醒] 以上为潜在风险提示，不代表一定违规，请根据实际情况判断。"
    echo "  如需忽略某行检测，在该行末尾添加注释: -- violation-scan-ignore"
    echo ""
    echo "[提醒] 自动扫描仅覆盖代码层面，以下仍需人工确认:"
    echo "  - 内容违规（色情/血腥/涉政）需检查实际画面"
    echo "  - 知识产权问题需确认素材授权"
    echo "  - 资质问题需在开发者中心确认"
    exit 1
fi
