#!/bin/bash
#
# ZeroTier 网关 GFW List 处理模块
#

# 配置自动更新 GFW List
SCRIPT_GFWLIST_UPDATE_SCRIPT="$SCRIPT_DIR/scripts/update-gfwlist.sh"
SYSTEM_GFWLIST_UPDATE_SCRIPT="/etc/cron.weekly/update-gfwlist"

# GFW List URL
GFWLIST_URL="https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
# 主程序目录中的配置文件
SCRIPT_CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPT_GFWLIST_LOCAL="$SCRIPT_CONFIG_DIR/gfwlist.txt"
SCRIPT_GFWLIST_DOMAINS="$SCRIPT_CONFIG_DIR/gfwlist_domains.txt"
SCRIPT_DNSMASQ_CONF="$SCRIPT_CONFIG_DIR/zt-gfwlist.conf"
# 系统目标目录中的配置文件
GFWLIST_LOCAL="/etc/zt-gateway/gfwlist.txt"
GFWLIST_DOMAINS="/etc/zt-gateway/gfwlist_domains.txt"
GFWLIST_IPSET="gfwlist"
DNSMASQ_CONF="/etc/dnsmasq.d/zt-gfwlist.conf"

# 下载和更新 GFW List
download_gfwlist() {
    log "INFO" "下载 GFW List..."
    
    # 确保主程序配置目录存在
    mkdir -p "$SCRIPT_CONFIG_DIR"
    # 确保系统目标目录存在
    mkdir -p /etc/zt-gateway
    mkdir -p /etc/dnsmasq.d
    
    # 下载 GFW List 到主程序目录
    if ! curl -s -o "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_URL"; then
        if ! wget -q -O "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_URL"; then
            handle_error "下载 GFW List 失败，请检查网络连接"
        fi
    fi
    
    log "INFO" "下载完成，开始解析..."
    
    # 解码 Base64 编码的 GFW List
    base64 -d "$SCRIPT_GFWLIST_LOCAL" > "${SCRIPT_GFWLIST_LOCAL}.decoded" 2>/dev/null || handle_error "解码 GFW List 失败"
    
    # 提取域名
    grep -v '^!' "${SCRIPT_GFWLIST_LOCAL}.decoded" | # 删除注释
        grep -v '^\[' | # 删除分类标题
        grep -v '^@@' | # 删除白名单
        grep -o '[a-zA-Z0-9][-a-zA-Z0-9]*\(\.[a-zA-Z0-9][-a-zA-Z0-9]*\)\+' | # 提取域名
        sort | uniq > "$SCRIPT_GFWLIST_DOMAINS"
    
    log "INFO" "已解析 $(wc -l < "$SCRIPT_GFWLIST_DOMAINS") 个域名"
    
    # 清理临时文件
    rm -f "${SCRIPT_GFWLIST_LOCAL}.decoded"
    
    # 设置更新时间
    echo "更新时间: $(date)" > "${SCRIPT_GFWLIST_LOCAL}.info"
    
    # 创建软链接到系统目录
    ln -sf "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_LOCAL" 2>/dev/null || {
        # 如果直接创建软链接失败，尝试用sudo
        sudo ln -sf "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_LOCAL" 2>/dev/null || {
            # 如果软链接创建失败，直接复制文件（备用方案）
            log "WARN" "无法创建软链接，使用复制替代"
            cp -f "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_LOCAL"
        }
    }
    
    # 创建域名列表的软链接
    ln -sf "$SCRIPT_GFWLIST_DOMAINS" "$GFWLIST_DOMAINS" 2>/dev/null || {
        sudo ln -sf "$SCRIPT_GFWLIST_DOMAINS" "$GFWLIST_DOMAINS" 2>/dev/null || {
            log "WARN" "无法创建域名列表软链接，使用复制替代"
            cp -f "$SCRIPT_GFWLIST_DOMAINS" "$GFWLIST_DOMAINS"
        }
    }
    
    # 创建info文件的软链接
    ln -sf "${SCRIPT_GFWLIST_LOCAL}.info" "${GFWLIST_LOCAL}.info" 2>/dev/null || {
        sudo ln -sf "${SCRIPT_GFWLIST_LOCAL}.info" "${GFWLIST_LOCAL}.info" 2>/dev/null || {
            cp -f "${SCRIPT_GFWLIST_LOCAL}.info" "${GFWLIST_LOCAL}.info"
        }
    }
    
    return 0
}

# 配置 dnsmasq 进行域名解析和 IP 集合管理
setup_dnsmasq() {
    log "INFO" "配置 dnsmasq 进行域名解析..."
    
    # 确保已安装 dnsmasq
    if ! rpm -q dnsmasq &>/dev/null; then
        log "INFO" "安装 dnsmasq..."
        yum install -y dnsmasq || handle_error "安装 dnsmasq 失败"
    fi
    
    # 确保目录存在
    mkdir -p "$SCRIPT_CONFIG_DIR"
    mkdir -p /etc/dnsmasq.d
    
    # 生成 dnsmasq 配置到主程序目录
    echo "# ZeroTier Gateway GFW List 配置 - $(date)" > "$SCRIPT_DNSMASQ_CONF"
    echo "# 自动生成，请勿手动修改" >> "$SCRIPT_DNSMASQ_CONF"
    echo "" >> "$SCRIPT_DNSMASQ_CONF"
    
    # 配置上游 DNS 服务器（使用 Google 和 Cloudflare 的 DNS）
    echo "# 上游 DNS 服务器配置" >> "$SCRIPT_DNSMASQ_CONF"
    echo "server=8.8.8.8" >> "$SCRIPT_DNSMASQ_CONF"
    echo "server=8.8.4.4" >> "$SCRIPT_DNSMASQ_CONF"
    echo "server=1.1.1.1" >> "$SCRIPT_DNSMASQ_CONF"
    echo "server=1.0.0.1" >> "$SCRIPT_DNSMASQ_CONF"
    echo "" >> "$SCRIPT_DNSMASQ_CONF"
    
    # 配置基本参数
    echo "# 基本配置" >> "$SCRIPT_DNSMASQ_CONF"
    echo "cache-size=10000" >> "$SCRIPT_DNSMASQ_CONF"
    echo "min-cache-ttl=3600" >> "$SCRIPT_DNSMASQ_CONF"
    echo "dns-forward-max=1000" >> "$SCRIPT_DNSMASQ_CONF"
    echo "neg-ttl=600" >> "$SCRIPT_DNSMASQ_CONF"
    echo "" >> "$SCRIPT_DNSMASQ_CONF"
    
    # 添加域名解析规则
    echo "# GFW List 域名规则 - 共 $(wc -l < "$SCRIPT_GFWLIST_DOMAINS") 条" >> "$SCRIPT_DNSMASQ_CONF"
    while IFS= read -r domain; do
        echo "ipset=/$domain/$GFWLIST_IPSET" >> "$SCRIPT_DNSMASQ_CONF"
    done < "$SCRIPT_GFWLIST_DOMAINS"
    
    # 配置 dnsmasq 监听本地
    if [ -f "/etc/dnsmasq.conf" ]; then
        if ! grep -q "^listen-address=" "/etc/dnsmasq.conf"; then
            echo "listen-address=127.0.0.1" >> "/etc/dnsmasq.conf"
        fi
    fi
    
    # 创建配置文件软链接
    ln -sf "$SCRIPT_DNSMASQ_CONF" "$DNSMASQ_CONF" 2>/dev/null || {
        sudo ln -sf "$SCRIPT_DNSMASQ_CONF" "$DNSMASQ_CONF" 2>/dev/null || {
            log "WARN" "无法创建dnsmasq配置软链接，使用复制替代"
            cp -f "$SCRIPT_DNSMASQ_CONF" "$DNSMASQ_CONF"
        }
    }
    
    # 启用并重启 dnsmasq
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    
    # 配置系统使用本地 DNS
    if [ -f "/etc/resolv.conf" ]; then
        # 备份原始 resolv.conf (如果备份文件不存在)
        if [ ! -f "/etc/resolv.conf.ztgw.bak" ]; then
            cp -f "/etc/resolv.conf" "/etc/resolv.conf.ztgw.bak"
        fi
        # 替换为本地 DNS
        echo "# Generated by ZeroTier Gateway" > "/etc/resolv.conf"
        echo "nameserver 127.0.0.1" >> "/etc/resolv.conf"
    fi
    
    log "INFO" "dnsmasq 配置完成"
    return 0
}

# 创建和配置 ipset
setup_ipset() {
    log "INFO" "配置 IP 集合..."
    
    # 确保已安装 ipset
    if ! command -v ipset &>/dev/null; then
        log "INFO" "安装 ipset..."
        yum install -y ipset || handle_error "安装 ipset 失败"
    fi
    
    # 创建 ipset
    ipset destroy "$GFWLIST_IPSET" 2>/dev/null
    ipset create "$GFWLIST_IPSET" hash:ip timeout 86400 || handle_error "创建 ipset 失败"
    
    # 保存 ipset 配置
    mkdir -p /etc/sysconfig/
    echo "IPSET_SAVE_ON_STOP=yes" > /etc/sysconfig/ipset
    echo "IPSET_SAVE_ON_RESTART=yes" > /etc/sysconfig/ipset
    
    # 创建 ipset 服务启动时加载的配置
    # 保存一个空的 ipset 列表，包括 gfwlist 的设置
    ipset save > /etc/sysconfig/ipset.conf
    
    log "INFO" "IP 集合配置完成"
    return 0
}

# 初始化 GFW List 模式
init_gfwlist_mode() {
    log "INFO" "初始化 GFW List 模式..."
    
    # 下载和解析 GFW List
    download_gfwlist
    
    # 设置 ipset
    setup_ipset
    
    # 配置 dnsmasq
    setup_dnsmasq
    
    # 设置定期更新
    setup_auto_update
    
    log "INFO" "GFW List 模式初始化完成"
    return 0
}

# 设置自动更新
setup_auto_update() {
    log "INFO" "配置 GFW List 定期自动更新..."
    
    # 确保scripts目录存在
    mkdir -p "$SCRIPT_DIR/scripts"
    
    # 创建更新脚本到主程序目录
    cat > "$SCRIPT_GFWLIST_UPDATE_SCRIPT" << EOL
#!/bin/bash
#
# ZeroTier 网关 GFW List 自动更新脚本
# 每周自动运行

SCRIPT_DIR="$SCRIPT_DIR"
CONFIG_DIR="\$SCRIPT_DIR/config"
LOG_FILE="/var/log/zt-gateway.log"
GFWLIST_URL="$GFWLIST_URL"
SCRIPT_GFWLIST_LOCAL="\$CONFIG_DIR/gfwlist.txt"
SCRIPT_GFWLIST_DOMAINS="\$CONFIG_DIR/gfwlist_domains.txt"
SCRIPT_DNSMASQ_CONF="\$CONFIG_DIR/zt-gfwlist.conf"
GFWLIST_IPSET="gfwlist"
DNSMASQ_CONF="/etc/dnsmasq.d/zt-gfwlist.conf"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] 开始自动更新 GFW List..." >> "\$LOG_FILE"

# 确保配置目录存在
mkdir -p "\$CONFIG_DIR"

# 下载 GFW List
if curl -s -o "\$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_URL" || wget -q -O "\$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_URL"; then
    # 解码 Base64
    base64 -d "\$SCRIPT_GFWLIST_LOCAL" > "\${SCRIPT_GFWLIST_LOCAL}.decoded" 2>/dev/null
    
    # 提取域名
    grep -v '^!' "\${SCRIPT_GFWLIST_LOCAL}.decoded" | grep -v '^\[' | grep -v '^@@' | grep -o '[a-zA-Z0-9][-a-zA-Z0-9]*\(\.[a-zA-Z0-9][-a-zA-Z0-9]*\)\+' | sort | uniq > "\$SCRIPT_GFWLIST_DOMAINS"
    
    # 清理临时文件
    rm -f "\${SCRIPT_GFWLIST_LOCAL}.decoded"
    
    # 设置更新时间
    echo "更新时间: $(date)" > "\${SCRIPT_GFWLIST_LOCAL}.info"
    
    # 更新 dnsmasq 配置
    echo "# ZeroTier Gateway GFW List 配置 - $(date)" > "\$SCRIPT_DNSMASQ_CONF"
    echo "# 自动生成，请勿手动修改" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "" >> "\$SCRIPT_DNSMASQ_CONF"
    
    # 上游 DNS 配置
    echo "# 上游 DNS 服务器配置" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "server=8.8.8.8" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "server=8.8.4.4" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "server=1.1.1.1" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "server=1.0.0.1" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "" >> "\$SCRIPT_DNSMASQ_CONF"
    
    # 基本配置
    echo "# 基本配置" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "cache-size=10000" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "min-cache-ttl=3600" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "dns-forward-max=1000" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "neg-ttl=600" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "" >> "\$SCRIPT_DNSMASQ_CONF"
    
    # 添加域名规则
    echo "# GFW List 域名规则 - 共 \$(wc -l < "\$SCRIPT_GFWLIST_DOMAINS") 条" >> "\$SCRIPT_DNSMASQ_CONF"
    while IFS= read -r domain; do
        echo "ipset=/\$domain/\$GFWLIST_IPSET" >> "\$SCRIPT_DNSMASQ_CONF"
    done < "\$SCRIPT_GFWLIST_DOMAINS"
    
    # 更新软链接或复制文件
    ln -sf "\$SCRIPT_GFWLIST_LOCAL" "/etc/zt-gateway/gfwlist.txt" 2>/dev/null || cp -f "\$SCRIPT_GFWLIST_LOCAL" "/etc/zt-gateway/gfwlist.txt"
    ln -sf "\$SCRIPT_GFWLIST_DOMAINS" "/etc/zt-gateway/gfwlist_domains.txt" 2>/dev/null || cp -f "\$SCRIPT_GFWLIST_DOMAINS" "/etc/zt-gateway/gfwlist_domains.txt"
    ln -sf "\${SCRIPT_GFWLIST_LOCAL}.info" "/etc/zt-gateway/gfwlist.txt.info" 2>/dev/null || cp -f "\${SCRIPT_GFWLIST_LOCAL}.info" "/etc/zt-gateway/gfwlist.txt.info"
    ln -sf "\$SCRIPT_DNSMASQ_CONF" "\$DNSMASQ_CONF" 2>/dev/null || cp -f "\$SCRIPT_DNSMASQ_CONF" "\$DNSMASQ_CONF"
    
    # 重启 dnsmasq
    systemctl restart dnsmasq
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] GFW List 更新成功，共 \$(wc -l < "\$SCRIPT_GFWLIST_DOMAINS") 个域名" >> "\$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] GFW List 更新失败，无法下载" >> "\$LOG_FILE"
fi
EOL
    
    # 设置执行权限
    chmod +x "$SCRIPT_GFWLIST_UPDATE_SCRIPT"
    
    # 创建软链接到系统cron目录
    ln -sf "$SCRIPT_GFWLIST_UPDATE_SCRIPT" "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null || {
        sudo ln -sf "$SCRIPT_GFWLIST_UPDATE_SCRIPT" "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null || {
            log "WARN" "无法创建自动更新脚本软链接，使用复制替代"
            cp -f "$SCRIPT_GFWLIST_UPDATE_SCRIPT" "$SYSTEM_GFWLIST_UPDATE_SCRIPT"
        }
    }
    
    # 确保系统脚本有执行权限
    chmod +x "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null || sudo chmod +x "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null
    
    log "INFO" "定期更新配置完成"
    return 0
}

# 更新 GFW List
update_gfwlist() {
    log "INFO" "更新 GFW List..."
    
    # 下载和解析 GFW List
    download_gfwlist
    
    # 重新配置 dnsmasq
    setup_dnsmasq
    
    log "INFO" "GFW List 更新完成"
    return 0
}

# 检查 GFW List 模式状态
check_gfwlist_status() {
    echo -e "${GREEN}===== GFW List 分流状态 =====${NC}"
    
    local status="未知"
    
    # 检查 ipset 是否存在
    if ipset list "$GFWLIST_IPSET" &>/dev/null; then
        local ipset_count=$(ipset list "$GFWLIST_IPSET" | grep -c "^[0-9]")
        status="${GREEN}活跃${NC} (ipset 包含 ${YELLOW}$ipset_count${NC} 个 IP)"
    else
        status="${RED}未配置或未激活${NC}"
    fi
    
    # 检查更新时间
    local update_time="未知"
    if [ -f "${SCRIPT_GFWLIST_LOCAL}.info" ]; then
        update_time=$(cat "${SCRIPT_GFWLIST_LOCAL}.info" | sed 's/更新时间: //')
    elif [ -f "${GFWLIST_LOCAL}.info" ]; then
        update_time=$(cat "${GFWLIST_LOCAL}.info" | sed 's/更新时间: //')
    fi
    
    # 检查 dnsmasq 服务状态
    local dnsmasq_status="未知"
    if systemctl is-active --quiet dnsmasq; then
        dnsmasq_status="${GREEN}运行中${NC}"
    else
        dnsmasq_status="${RED}未运行${NC}"
    fi
    
    # 显示 DNS 服务器设置
    local dns_servers="未配置"
    if [ -f "/etc/resolv.conf" ] && grep -q "nameserver" "/etc/resolv.conf"; then
        dns_servers=$(grep "nameserver" "/etc/resolv.conf" | awk '{print $2}' | tr '\n' ' ')
    fi
    
    # 检查自动更新脚本
    local auto_update="未配置"
    if [ -f "$SCRIPT_GFWLIST_UPDATE_SCRIPT" ] && [ -x "$SCRIPT_GFWLIST_UPDATE_SCRIPT" ]; then
        auto_update="${GREEN}已配置${NC} (每周自动更新)"
    elif [ -f "$SYSTEM_GFWLIST_UPDATE_SCRIPT" ] && [ -x "$SYSTEM_GFWLIST_UPDATE_SCRIPT" ]; then
        auto_update="${GREEN}已配置${NC} (每周自动更新)"
    fi
    
    # 获取域名数量
    local domain_count=0
    if [ -f "$SCRIPT_GFWLIST_DOMAINS" ]; then
        domain_count=$(wc -l < "$SCRIPT_GFWLIST_DOMAINS" 2>/dev/null || echo '0')
    elif [ -f "$GFWLIST_DOMAINS" ]; then
        domain_count=$(wc -l < "$GFWLIST_DOMAINS" 2>/dev/null || echo '0')
    fi
    
    echo -e "GFW List 模式: $status"
    echo -e "域名列表: ${YELLOW}$domain_count${NC} 个域名"
    echo -e "配置文件位置: ${BLUE}$SCRIPT_CONFIG_DIR${NC}"
    echo -e "DNS 服务: $dnsmasq_status"
    echo -e "DNS 服务器: $dns_servers"
    echo -e "自动更新: $auto_update"
    echo -e "最后更新: $update_time"
    echo ""
    
    # 显示进一步操作的提示
    echo -e "${YELLOW}提示:${NC}"
    echo -e "- 更新 GFW List: ./zerotier-gateway.sh --update-gfwlist"
    echo -e "- 查看详细流量: ./zerotier-gateway.sh --stats"
}
