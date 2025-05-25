#!/bin/bash
#
# GitHub Copilot 对话记录管理模块
# 用于记录 AI 助手与用户的对话和代码修改历史
# 存储在 vibe.history 目录下，每次对话生成一个 MD 文件
#

# 对话记录目录
CONVERSATION_HISTORY_DIR="${SCRIPT_DIR}/vibe.history"

# 初始化对话记录系统
init_conversation_history() {
    log "INFO" "初始化对话记录系统..."

    # 创建对话记录目录
    mkdir -p "$CONVERSATION_HISTORY_DIR" || {
        log "ERROR" "无法创建对话记录目录: $CONVERSATION_HISTORY_DIR"
        return 1
    }

    # 创建 README 文件
    if [ ! -f "$CONVERSATION_HISTORY_DIR/README.md" ]; then
        create_conversation_readme
    fi

    log "INFO" "对话记录系统初始化完成"
}

# 创建对话记录目录的 README 文件
create_conversation_readme() {
    local readme_file="$CONVERSATION_HISTORY_DIR/README.md"

    cat > "$readme_file" << 'EOF'
# GitHub Copilot 对话记录

这个目录包含了 GitHub Copilot AI 助手与用户的对话记录和代码修改历史。

## 目录说明

- 每个对话记录文件按时间戳命名：`YYYY-MM-DD_HH-MM-SS_conversation.md`
- 每个文件包含：
  - 对话主题和用户需求
  - AI 响应摘要
  - 修改的文件列表
  - 修改小结和技术要点
  - 测试建议和注意事项

## 文件命名规则

```
2025-05-25_14-30-15_conversation.md  # 对话记录
2025-05-25_15-20-30_conversation.md  # 下一次对话记录
```

## 查看历史记录

```bash
# 查看最近的对话记录
ls -lt *.md | head -10

# 搜索特定主题的对话
grep -l "关键词" *.md
```

## 自动清理

- 默认保留最近 50 个对话记录
- 超过 90 天的记录会被自动清理

---
*此目录由 GitHub Copilot 对话记录系统管理*
EOF

    log "DEBUG" "对话记录 README 文件已创建: $readme_file"
}

# 创建新的对话记录
create_conversation_record() {
    local topic="$1"
    local user_request="$2"
    local ai_summary="$3"
    local modified_files="$4"
    local modification_summary="$5"
    local modification_type="${6:-代码修改}"

    # 生成时间戳
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local record_file="$CONVERSATION_HISTORY_DIR/${timestamp}_conversation.md"

    # 使用模板生成记录文件
    if [ -f "$SCRIPT_DIR/templates/conversation-record.md.template" ]; then
        process_conversation_template "$record_file" "$topic" "$user_request" "$ai_summary" \
                                    "$modified_files" "$modification_summary" "$modification_type"
    else
        # 直接生成记录文件
        generate_conversation_record_direct "$record_file" "$topic" "$user_request" "$ai_summary" \
                                           "$modified_files" "$modification_summary" "$modification_type"
    fi

    log "INFO" "对话记录已创建: $record_file"
    echo "$record_file"
}

# 处理对话记录模板
process_conversation_template() {
    local output_file="$1"
    local topic="$2"
    local user_request="$3"
    local ai_summary="$4"
    local modified_files="$5"
    local modification_summary="$6"
    local modification_type="$7"

    local template_file="$SCRIPT_DIR/templates/conversation-record.md.template"
    local temp_content=$(cat "$template_file")

    # 替换模板变量
    temp_content="${temp_content//\{\{TIMESTAMP\}\}/$(date '+%Y-%m-%d %H:%M:%S')}"
    temp_content="${temp_content//\{\{DATE\}\}/$(date '+%Y年%m月%d日')}"
    temp_content="${temp_content//\{\{SESSION_ID\}\}/$(date '+%Y%m%d%H%M%S')}"
    temp_content="${temp_content//\{\{CONVERSATION_TOPIC\}\}/$topic}"
    temp_content="${temp_content//\{\{USER_REQUEST\}\}/$user_request}"
    temp_content="${temp_content//\{\{AI_RESPONSE_SUMMARY\}\}/$ai_summary}"
    temp_content="${temp_content//\{\{MODIFIED_FILES_LIST\}\}/$modified_files}"
    temp_content="${temp_content//\{\{MODIFICATION_SUMMARY\}\}/$modification_summary}"
    temp_content="${temp_content//\{\{MODIFICATION_TYPE\}\}/$modification_type}"
    temp_content="${temp_content//\{\{TECHNICAL_POINTS\}\}/- 遵循 Shell 脚本编码规范\n- 使用配置文件集中管理\n- 采用模块化设计}"
    temp_content="${temp_content//\{\{CODE_CHANGES_DETAIL\}\}/详见修改的文件列表和修改小结}"
    temp_content="${temp_content//\{\{TESTING_SUGGESTIONS\}\}/- 验证脚本语法\n- 测试配置文件生成\n- 检查服务启动状态}"
    temp_content="${temp_content//\{\{NOTES_AND_WARNINGS\}\}/请在测试环境中验证修改效果后再部署到生产环境}"
    temp_content="${temp_content//\{\{RECORD_GENERATED_TIME\}\}/$(date '+%Y-%m-%d %H:%M:%S')}"

    # 写入文件
    echo "$temp_content" > "$output_file"
}

# 直接生成对话记录（无模板时的备用方案）
generate_conversation_record_direct() {
    local output_file="$1"
    local topic="$2"
    local user_request="$3"
    local ai_summary="$4"
    local modified_files="$5"
    local modification_summary="$6"
    local modification_type="$7"

    cat > "$output_file" << EOF
# GitHub Copilot 对话记录

**时间**: $(date '+%Y-%m-%d %H:%M:%S')
**日期**: $(date '+%Y年%m月%d日')
**会话ID**: $(date '+%Y%m%d%H%M%S')

## 对话主题

$topic

## 用户需求

$user_request

## AI 响应摘要

$ai_summary

## 修改的文件

\`\`\`
$modified_files
\`\`\`

## 修改小结

$modification_summary

### 修改类型
- $modification_type

### 技术要点
- 遵循 Shell 脚本编码规范
- 使用配置文件集中管理
- 采用模块化设计

### 遵循的编码规范
- [x] Shell 脚本规范 (#!/bin/bash, 大写变量名)
- [x] 日志函数使用 (log "INFO" "消息")
- [x] 配置文件集中管理
- [x] 软链接部署方式

## 代码变更详情

详见修改的文件列表和修改小结

## 测试建议

- 验证脚本语法
- 测试配置文件生成
- 检查服务启动状态

## 注意事项

请在测试环境中验证修改效果后再部署到生产环境

---
*记录生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
*生成方式: GitHub Copilot 自动记录*
EOF

    log "DEBUG" "直接生成对话记录完成: $output_file"
}

# 查看最近的对话记录
show_recent_conversations() {
    local limit="${1:-5}"  # 默认显示最近5条记录

    echo -e "${GREEN}===== 最近的对话记录 (最多 $limit 条) =====${NC}"
    echo ""

    if [ ! -d "$CONVERSATION_HISTORY_DIR" ]; then
        echo -e "${YELLOW}暂无对话记录${NC}"
        return 0
    fi

    # 按时间倒序列出记录文件
    find "$CONVERSATION_HISTORY_DIR" -name "*_conversation.md" -type f -printf '%T@ %p\n' 2>/dev/null | \
    sort -nr | head -n "$limit" | \
    while read timestamp filepath; do
        local filename=$(basename "$filepath")
        local date_part=$(echo "$filename" | cut -d'_' -f1-2)
        local readable_date=$(echo "$date_part" | sed 's/_/ /' | sed 's/-/:/3' | sed 's/-/:/3')

        # 尝试从文件中提取主题
        local topic=$(grep "^## 对话主题" "$filepath" -A 1 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')

        echo -e "${BLUE}[$readable_date]${NC} $topic"
        echo -e "  文件: ${CYAN}$filename${NC}"
        echo ""
    done

    echo -e "${YELLOW}查看完整记录: ls $CONVERSATION_HISTORY_DIR/${NC}"
}

# 搜索对话记录
search_conversations() {
    local search_term="$1"

    if [ -z "$search_term" ]; then
        log "ERROR" "请提供搜索关键词"
        return 1
    fi

    echo -e "${GREEN}===== 搜索结果: '$search_term' =====${NC}"
    echo ""

    if [ ! -d "$CONVERSATION_HISTORY_DIR" ]; then
        echo -e "${YELLOW}暂无对话记录${NC}"
        return 0
    fi

    # 在所有记录文件中搜索
    grep -l -i "$search_term" "$CONVERSATION_HISTORY_DIR"/*_conversation.md 2>/dev/null | \
    while read filepath; do
        local filename=$(basename "$filepath")
        local topic=$(grep "^## 对话主题" "$filepath" -A 1 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')

        echo -e "${BLUE}匹配文件:${NC} $filename"
        echo -e "${CYAN}主题:${NC} $topic"

        # 显示匹配的行
        grep -i -n --color=always "$search_term" "$filepath" | head -3
        echo ""
    done
}

# 清理过期的对话记录
cleanup_old_conversations() {
    local max_files="${1:-50}"  # 默认保留最近50个文件
    local max_days="${2:-90}"   # 默认保留90天内的文件

    log "DEBUG" "清理过期的对话记录..."

    if [ ! -d "$CONVERSATION_HISTORY_DIR" ]; then
        return 0
    fi

    # 按修改时间删除超过保留天数的文件
    find "$CONVERSATION_HISTORY_DIR" -name "*_conversation.md" -type f -mtime +$max_days -delete 2>/dev/null

    # 限制最大文件数量
    local file_count=$(find "$CONVERSATION_HISTORY_DIR" -name "*_conversation.md" -type f | wc -l)
    if [ "$file_count" -gt "$max_files" ]; then
        find "$CONVERSATION_HISTORY_DIR" -name "*_conversation.md" -type f -printf '%T@ %p\n' | \
        sort -n | head -n -$max_files | cut -d' ' -f2- | \
        xargs rm -f 2>/dev/null
        log "INFO" "已清理超出数量限制的对话记录文件"
    fi

    log "DEBUG" "对话记录清理完成"
}

# 快速记录对话（便捷函数）
quick_conversation_record() {
    local topic="$1"
    local user_request="$2"
    local modified_files="$3"
    local summary="${4:-GitHub Copilot 协助完成代码修改}"

    create_conversation_record "$topic" "$user_request" "$summary" "$modified_files" "$summary"
}
