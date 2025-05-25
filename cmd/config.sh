#!/bin/bash
#
# ZeroTier 网关配置文件管理模块
# 统一处理配置文件的创建、软链接部署和模板处理
#

# 全局配置路径定义
SCRIPT_CONFIG_DIR="$SCRIPT_DIR/config"
SYSTEM_CONFIG_DIR="/etc/zt-gateway"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

# 配置文件路径映射表
declare -A CONFIG_PATHS=(
    ["main"]="$SCRIPT_CONFIG_DIR/zt-gateway.conf"
    ["gfwlist"]="$SCRIPT_CONFIG_DIR/zt-gfwlist.conf"
    ["gfwlist_domains"]="$SCRIPT_CONFIG_DIR/gfwlist_domains.txt"
    ["custom_domains"]="$SCRIPT_CONFIG_DIR/custom_domains.txt"
    ["ipset_service"]="$SCRIPT_CONFIG_DIR/ztgw-ipset.service"
    ["sysctl"]="$SCRIPT_CONFIG_DIR/99-zt-gateway.conf"
)

declare -A SYSTEM_PATHS=(
    ["main"]="$SYSTEM_CONFIG_DIR/config"
    ["gfwlist"]="/etc/dnsmasq.d/zt-gfwlist.conf"
    ["gfwlist_domains"]="$SYSTEM_CONFIG_DIR/gfwlist_domains.txt"
    ["custom_domains"]="$SYSTEM_CONFIG_DIR/custom_domains.txt"
    ["ipset_service"]="/etc/systemd/system/ztgw-ipset.service"
    ["sysctl"]="/etc/sysctl.d/99-zt-gateway.conf"
)

# 初始化配置管理系统
init_config_system() {
    log "INFO" "初始化配置管理系统..."

    # 创建必要的目录
    mkdir -p "$SCRIPT_CONFIG_DIR" || handle_error "无法创建项目配置目录"
    mkdir -p "$SYSTEM_CONFIG_DIR" || sudo mkdir -p "$SYSTEM_CONFIG_DIR" || handle_error "无法创建系统配置目录"
    mkdir -p "${SCRIPT_DIR}/logs" || handle_error "无法创建日志目录"
    mkdir -p "${SCRIPT_DIR}/scripts" || handle_error "无法创建脚本目录"

    # 创建 .keep 文件确保目录被Git跟踪
    touch "$SCRIPT_CONFIG_DIR/.keep" 2>/dev/null

    log "INFO" "配置管理系统初始化完成"
}

# 统一的软链接创建函数
create_symlink() {
    local source_file="$1"
    local target_link="$2"
    local description="${3:-配置文件}"

    # 检查源文件是否存在
    if [ ! -f "$source_file" ]; then
        log "ERROR" "源文件不存在: $source_file"
        return 1
    fi

    # 避免自链接（源和目标相同）
    if [ "$source_file" = "$target_link" ]; then
        log "DEBUG" "源和目标相同，跳过软链接创建: $source_file"
        return 0
    fi

    # 确保目标目录存在
    local target_dir=$(dirname "$target_link")
    mkdir -p "$target_dir" 2>/dev/null || sudo mkdir -p "$target_dir" 2>/dev/null || {
        log "ERROR" "无法创建目标目录: $target_dir"
        return 1
    }

    # 尝试创建软链接
    if ln -sf "$source_file" "$target_link" 2>/dev/null; then
        log "INFO" "${description}软链接已创建: $target_link -> $source_file"
        return 0
    elif sudo ln -sf "$source_file" "$target_link" 2>/dev/null; then
        log "INFO" "${description}软链接已创建(sudo): $target_link -> $source_file"
        return 0
    else
        log "WARN" "软链接创建失败，使用复制代替: $target_link"
        if cp -f "$source_file" "$target_link" 2>/dev/null || sudo cp -f "$source_file" "$target_link" 2>/dev/null; then
            log "INFO" "${description}已复制: $target_link"
            return 0
        else
            log "ERROR" "无法创建软链接或复制文件: $target_link"
            return 1
        fi
    fi
}

# 创建配置文件
create_config_file() {
    local config_key="$1"
    local content="$2"
    local description="${3:-配置文件}"

    local project_config="${CONFIG_PATHS[$config_key]}"
    local system_config="${SYSTEM_PATHS[$config_key]}"

    if [ -z "$project_config" ] || [ -z "$system_config" ]; then
        log "ERROR" "未知的配置文件类型: $config_key"
        return 1
    fi

    # 创建项目配置文件
    echo "$content" > "$project_config" || {
        log "ERROR" "无法创建项目配置文件: $project_config"
        return 1
    }

    log "INFO" "${description}已创建: $project_config"

    # 创建软链接到系统位置
    create_symlink "$project_config" "$system_config" "$description"
}

# 从模板处理配置文件
process_template() {
    local template_name="$1"
    local config_key="$2"
    local description="${3:-配置文件}"

    local template_file="$TEMPLATE_DIR/${template_name}.template"
    local project_config="${CONFIG_PATHS[$config_key]}"
    local system_config="${SYSTEM_PATHS[$config_key]}"

    if [ ! -f "$template_file" ]; then
        log "ERROR" "模板文件不存在: $template_file"
        return 1
    fi

    if [ -z "$project_config" ] || [ -z "$system_config" ]; then
        log "ERROR" "未知的配置文件类型: $config_key"
        return 1
    fi

    # 处理模板变量替换
    local temp_content=$(cat "$template_file")

    # 替换常用变量
    temp_content="${temp_content//\{\{SCRIPT_DIR\}\}/$SCRIPT_DIR}"
    temp_content="${temp_content//\{\{ZT_INTERFACE\}\}/$ZT_INTERFACE}"
    temp_content="${temp_content//\{\{WAN_INTERFACE\}\}/$WAN_INTERFACE}"
    temp_content="${temp_content//\{\{ZT_NETWORK\}\}/$ZT_NETWORK}"
    temp_content="${temp_content//\{\{LOG_FILE\}\}/$LOG_FILE}"
    temp_content="${temp_content//\{\{CONFIG_DIR\}\}/$SCRIPT_CONFIG_DIR}"

    # 条件处理
    if [ "$IPV6_ENABLED" = "1" ]; then
        temp_content="${temp_content//\{\{#IPV6\}\}/}"
        temp_content="${temp_content//\{\{\/IPV6\}\}/}"
    else
        # 移除IPv6相关内容
        temp_content=$(echo "$temp_content" | sed '/{{#IPV6}}/,/{{\/IPV6}}/d')
    fi

    if [ "$GFWLIST_MODE" = "1" ]; then
        temp_content="${temp_content//\{\{#GFWLIST\}\}/}"
        temp_content="${temp_content//\{\{\/GFWLIST\}\}/}"
    else
        # 移除GFWList相关内容
        temp_content=$(echo "$temp_content" | sed '/{{#GFWLIST}}/,/{{\/GFWLIST}}/d')
    fi

    # 生成项目配置文件
    echo "$temp_content" > "$project_config" || {
        log "ERROR" "无法生成配置文件: $project_config"
        return 1
    }

    log "INFO" "${description}已从模板生成: $project_config"

    # 创建软链接到系统位置
    create_symlink "$project_config" "$system_config" "$description"
}

# 获取配置文件路径
get_config_path() {
    local config_key="$1"
    local path_type="${2:-project}"  # project|system

    if [ "$path_type" = "system" ]; then
        echo "${SYSTEM_PATHS[$config_key]}"
    else
        echo "${CONFIG_PATHS[$config_key]}"
    fi
}

# 检查配置文件状态
check_config_status() {
    local config_key="$1"
    local project_config="${CONFIG_PATHS[$config_key]}"
    local system_config="${SYSTEM_PATHS[$config_key]}"

    if [ -z "$project_config" ] || [ -z "$system_config" ]; then
        echo "未知配置"
        return 1
    fi

    if [ ! -f "$project_config" ]; then
        echo "项目配置不存在"
        return 1
    fi

    if [ ! -e "$system_config" ]; then
        echo "系统配置不存在"
        return 1
    fi

    if [ -L "$system_config" ]; then
        local link_target=$(readlink "$system_config")
        if [ "$link_target" = "$project_config" ]; then
            echo "软链接正常"
            return 0
        else
            echo "软链接错误(指向: $link_target)"
            return 1
        fi
    else
        echo "系统配置为复制文件"
        return 0
    fi
}

# 同步所有配置文件到系统位置
sync_all_configs() {
    log "INFO" "同步所有配置文件到系统位置..."

    local sync_count=0
    local error_count=0

    for config_key in "${!CONFIG_PATHS[@]}"; do
        local project_config="${CONFIG_PATHS[$config_key]}"
        local system_config="${SYSTEM_PATHS[$config_key]}"

        if [ -f "$project_config" ]; then
            if create_symlink "$project_config" "$system_config" "配置文件($config_key)"; then
                ((sync_count++))
            else
                ((error_count++))
            fi
        fi
    done

    log "INFO" "配置同步完成：成功 $sync_count 个，失败 $error_count 个"
    return $error_count
}

# 备份配置文件
backup_configs() {
    local backup_dir="${SCRIPT_DIR}/backups/$(date +%Y%m%d-%H%M%S)"

    log "INFO" "备份配置文件到: $backup_dir"
    mkdir -p "$backup_dir" || {
        log "ERROR" "无法创建备份目录: $backup_dir"
        return 1
    }

    # 备份项目配置
    if [ -d "$SCRIPT_CONFIG_DIR" ]; then
        cp -r "$SCRIPT_CONFIG_DIR" "$backup_dir/project-config" || {
            log "ERROR" "备份项目配置失败"
            return 1
        }
    fi

    # 备份系统配置
    if [ -d "$SYSTEM_CONFIG_DIR" ]; then
        sudo cp -r "$SYSTEM_CONFIG_DIR" "$backup_dir/system-config" 2>/dev/null || {
            log "WARN" "备份系统配置失败或需要权限"
        }
    fi

    log "INFO" "配置文件备份完成: $backup_dir"
    echo "$backup_dir"
}

# 处理模板文件
process_template() {
    local template_file="$1"
    local output_file="$2"
    local template_path="$SCRIPT_DIR/templates/$template_file"

    if [ ! -f "$template_path" ]; then
        handle_error "模板文件不存在: $template_path"
    fi

    log "DEBUG" "处理模板文件: $template_file -> $output_file"

    # 设置生成时间
    GENERATION_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    # 创建输出目录
    mkdir -p "$(dirname "$output_file")"

    # 处理模板替换
    local temp_file=$(mktemp)
    cp "$template_path" "$temp_file"

    # 替换所有配置变量
    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # 移除值中的引号
        value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')

        # 在模板中替换变量
        sed -i "s/\\b${key}\\b/${value}/g" "$temp_file"
    done < "$CONFIG_FILE"

    # 处理特殊占位符
    handle_special_placeholders "$temp_file"

    # 移动到最终位置
    if [ -w "$(dirname "$output_file")" ]; then
        mv "$temp_file" "$output_file"
    else
        sudo mv "$temp_file" "$output_file"
    fi

    log "INFO" "模板处理完成: $output_file"
}

# 处理特殊占位符
handle_special_placeholders() {
    local file="$1"

    # 处理IPv6设置
    if [ "$IPV6_ENABLED" = "1" ]; then
        local ipv6_settings="net.ipv6.conf.all.forwarding=1\nnet.ipv6.conf.default.forwarding=1"
        sed -i "s/#IPV6_SETTINGS#/$ipv6_settings/" "$file"
    else
        sed -i "s/#IPV6_SETTINGS#/# IPv6 转发已禁用/" "$file"
    fi

    # 处理高级网络设置
    if [ "$ADVANCED_NETWORK_OPTIMIZATION" = "1" ]; then
        local advanced_settings=""
        [ "$ENABLE_BBR_CONGESTION_CONTROL" = "1" ] && advanced_settings="${advanced_settings}net.core.default_qdisc=fq\n"
        [ "$ENABLE_FAST_OPEN" = "1" ] && advanced_settings="${advanced_settings}net.ipv4.tcp_fastopen=3\n"
        sed -i "s/#ADVANCED_NETWORK_SETTINGS#/$advanced_settings/" "$file"
    else
        sed -i "s/#ADVANCED_NETWORK_SETTINGS#/# 高级网络优化已禁用/" "$file"
    fi
}
