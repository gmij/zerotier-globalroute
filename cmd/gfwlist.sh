#!/bin/bash
#
# ZeroTier 网关 GFW List 处理模块
#

# 从配置文件加载变量
source_config_if_exists() {
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# 确保配置已加载
source_config_if_exists

# 配置变量（优先使用配置文件中的值）
GFWLIST_URL="${GFWLIST_URL:-https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt}"
GFWLIST_LOCAL="${GFWLIST_LOCAL:-$SCRIPT_DIR/config/gfwlist.txt}"
GFWLIST_DOMAINS="${GFWLIST_DOMAINS:-$SCRIPT_DIR/config/gfwlist_domains.txt}"
CUSTOM_DOMAINS="${CUSTOM_DOMAINS:-$SCRIPT_DIR/config/custom_domains.txt}"
DNSMASQ_CONF="${DNSMASQ_CONF:-/etc/dnsmasq.d/zt-gfwlist.conf}"
GFWLIST_IPSET="${GFWLIST_IPSET:-gfwlist}"
GFWLIST_UPDATE_SCRIPT="$SCRIPT_DIR/scripts/update-gfwlist.sh"

# 下载和更新 GFW List
download_gfwlist() {
    log "INFO" "下载 GFW List..."

    # 确保配置目录存在
    mkdir -p "$(dirname "$GFWLIST_LOCAL")"
    mkdir -p /etc/dnsmasq.d

    # 下载 GFW List
    if ! curl -s -o "$GFWLIST_LOCAL" "$GFWLIST_URL"; then
        if ! wget -q -O "$GFWLIST_LOCAL" "$GFWLIST_URL"; then
            handle_error "下载 GFW List 失败，请检查网络连接"
        fi
    fi

    log "INFO" "下载完成，开始解析..."

    # 解码 Base64 编码的 GFW List
    base64 -d "$GFWLIST_LOCAL" > "${GFWLIST_LOCAL}.decoded" 2>/dev/null || handle_error "解码 GFW List 失败"

    # 提取域名
    grep -v '^!' "${GFWLIST_LOCAL}.decoded" | # 删除注释
        grep -v '^\[' | # 删除分类标题
        grep -v '^@@' | # 删除白名单
        grep -o '[a-zA-Z0-9][-a-zA-Z0-9]*\(\.[a-zA-Z0-9][-a-zA-Z0-9]*\)\+' | # 提取域名
        sort | uniq > "$SCRIPT_GFWLIST_DOMAINS"

    log "INFO" "已解析 $(wc -l < "$SCRIPT_GFWLIST_DOMAINS") 个域名"

    # 清理临时文件
    rm -f "${SCRIPT_GFWLIST_LOCAL}.decoded"

    # 设置更新时间
    echo "更新时间: $(date)" > "${SCRIPT_GFWLIST_LOCAL}.info"

    # 创建软链接到系统目录，先检查源和目标是否相同
    if [ "$SCRIPT_GFWLIST_LOCAL" != "$GFWLIST_LOCAL" ]; then
        # 确保目标目录存在
        mkdir -p $(dirname "$GFWLIST_LOCAL") 2>/dev/null
        ln -sf "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_LOCAL" 2>/dev/null || {
            # 如果直接创建软链接失败，尝试用sudo
            sudo ln -sf "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_LOCAL" 2>/dev/null || {
                # 如果软链接创建失败，直接复制文件（备用方案）
                log "INFO" "使用复制代替软链接"
                cp -f "$SCRIPT_GFWLIST_LOCAL" "$GFWLIST_LOCAL"
            }
        }
    fi

    # 创建域名列表的软链接
    if [ "$SCRIPT_GFWLIST_DOMAINS" != "$GFWLIST_DOMAINS" ]; then
        mkdir -p $(dirname "$GFWLIST_DOMAINS") 2>/dev/null
        ln -sf "$SCRIPT_GFWLIST_DOMAINS" "$GFWLIST_DOMAINS" 2>/dev/null || {
            sudo ln -sf "$SCRIPT_GFWLIST_DOMAINS" "$GFWLIST_DOMAINS" 2>/dev/null || {
                log "INFO" "使用复制代替域名列表软链接"
                cp -f "$SCRIPT_GFWLIST_DOMAINS" "$GFWLIST_DOMAINS"
            }
        }
    fi

    # 创建info文件的软链接
    if [ "${SCRIPT_GFWLIST_LOCAL}.info" != "${GFWLIST_LOCAL}.info" ]; then
        mkdir -p $(dirname "${GFWLIST_LOCAL}.info") 2>/dev/null
        ln -sf "${SCRIPT_GFWLIST_LOCAL}.info" "${GFWLIST_LOCAL}.info" 2>/dev/null || {
            sudo ln -sf "${SCRIPT_GFWLIST_LOCAL}.info" "${GFWLIST_LOCAL}.info" 2>/dev/null || {
                log "INFO" "使用复制代替info文件软链接"
                cp -f "${SCRIPT_GFWLIST_LOCAL}.info" "${GFWLIST_LOCAL}.info"
            }
        }
    fi

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

    # 配置上游 DNS 服务器（使用阿里DNS作为主要DNS，Google和Cloudflare为备用）
    echo "# 上游 DNS 服务器配置" >> "$SCRIPT_DNSMASQ_CONF"
    echo "server=223.5.5.5" >> "$SCRIPT_DNSMASQ_CONF"  # 阿里DNS主
    echo "server=223.6.6.6" >> "$SCRIPT_DNSMASQ_CONF"  # 阿里DNS备用
    echo "server=8.8.8.8" >> "$SCRIPT_DNSMASQ_CONF"    # Google DNS (备用)
    echo "server=1.1.1.1" >> "$SCRIPT_DNSMASQ_CONF"    # Cloudflare DNS (备用)
    echo "" >> "$SCRIPT_DNSMASQ_CONF"

    # 配置基本参数
    echo "# 基本配置" >> "$SCRIPT_DNSMASQ_CONF"
    echo "cache-size=10000" >> "$SCRIPT_DNSMASQ_CONF"
    echo "min-cache-ttl=3600" >> "$SCRIPT_DNSMASQ_CONF"
    echo "dns-forward-max=1000" >> "$SCRIPT_DNSMASQ_CONF"
    echo "neg-ttl=600" >> "$SCRIPT_DNSMASQ_CONF"

    # 添加日志配置
    if [ "$DNS_LOGGING" = "1" ]; then
        echo "# DNS 日志配置" >> "$SCRIPT_DNSMASQ_CONF"
        echo "log-queries=extra" >> "$SCRIPT_DNSMASQ_CONF"
        echo "log-facility=${SCRIPT_DIR}/logs/dnsmasq.log" >> "$SCRIPT_DNSMASQ_CONF"
        echo "log-async=50" >> "$SCRIPT_DNSMASQ_CONF"

        # 确保日志目录和文件存在且有正确权限
        mkdir -p "${SCRIPT_DIR}/logs"
        touch "${SCRIPT_DIR}/logs/dnsmasq.log"
        chmod 644 "${SCRIPT_DIR}/logs/dnsmasq.log"

        # 确保dnsmasq可以写入日志目录
        chown -R dnsmasq:dnsmasq "${SCRIPT_DIR}/logs" 2>/dev/null || {
            log "INFO" "尝试使用sudo设置日志目录权限"
            sudo chown -R dnsmasq:dnsmasq "${SCRIPT_DIR}/logs" 2>/dev/null || {
                log "INFO" "无法设置日志目录权限，尝试设置为所有用户可写"
                chmod 777 "${SCRIPT_DIR}/logs"
            }
        }

        # 如果dnsmasq配置文件存在，确保日志配置正确
        if [ -f "/etc/dnsmasq.conf" ]; then
            # 确保dnsmasq的主配置文件不会覆盖我们的日志设置
            sed -i '/^log-facility=/d' "/etc/dnsmasq.conf"
            sed -i '/^log-queries/d' "/etc/dnsmasq.conf"

            # 添加一个配置，让dnsmasq加载我们的配置文件
            if ! grep -q "conf-dir=/etc/dnsmasq.d" "/etc/dnsmasq.conf"; then
                echo "conf-dir=/etc/dnsmasq.d" >> "/etc/dnsmasq.conf"
            fi
        fi
    fi
    echo "" >> "$SCRIPT_DNSMASQ_CONF"

    # 添加 GFW List 域名解析规则
    echo "# GFW List 域名规则 - 共 $(wc -l < "$SCRIPT_GFWLIST_DOMAINS") 条" >> "$SCRIPT_DNSMASQ_CONF"
    while IFS= read -r domain; do
        echo "ipset=/$domain/$GFWLIST_IPSET" >> "$SCRIPT_DNSMASQ_CONF"
    done < "$SCRIPT_GFWLIST_DOMAINS"

    # 确保自定义域名列表文件存在
    touch "$SCRIPT_CUSTOM_DOMAINS" 2>/dev/null

    # 添加自定义域名解析规则
    local custom_count=0
    if [ -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        custom_count=$(wc -l < "$SCRIPT_CUSTOM_DOMAINS" 2>/dev/null || echo '0')
        if [ "$custom_count" -gt 0 ]; then
            echo "" >> "$SCRIPT_DNSMASQ_CONF"
            echo "# 自定义域名规则 - 共 $custom_count 条" >> "$SCRIPT_DNSMASQ_CONF"
            while IFS= read -r domain; do
                # 跳过空行和注释行
                [[ -z "$domain" || "$domain" == \#* ]] && continue
                echo "ipset=/$domain/$GFWLIST_IPSET" >> "$SCRIPT_DNSMASQ_CONF"
            done < "$SCRIPT_CUSTOM_DOMAINS"
        fi
    fi
    log "INFO" "添加了 $custom_count 个自定义域名"

    # 检查是否存在可能的DNS端口冲突
    local is_port_conflict=0

    # 检查是否有其他服务占用DNS端口53
    if netstat -tuln | grep -q ':53 '; then
        log "WARN" "检测到DNS端口53可能被占用，尝试使用备用端口..."
        is_port_conflict=1
    fi

    # 检查systemd-resolved是否运行
    if systemctl is-active --quiet systemd-resolved; then
        log "WARN" "检测到systemd-resolved服务正在运行，可能会与dnsmasq冲突"
        is_port_conflict=1
    fi

    # 如果存在端口冲突，使用备用端口5353
    if [ "$is_port_conflict" = "1" ]; then
        echo "# 使用备用端口避免冲突" >> "$SCRIPT_DNSMASQ_CONF"
        echo "port=5353" >> "$SCRIPT_DNSMASQ_CONF"
        log "INFO" "已配置dnsmasq使用备用端口5353"
        # 更新resolv.conf以使用正确的端口
        if [ -f "/etc/resolv.conf" ]; then
            if [ ! -f "/etc/resolv.conf.ztgw.bak" ]; then
                cp -f "/etc/resolv.conf" "/etc/resolv.conf.ztgw.bak"
            fi
            # 配置使用本地DNS服务的特定端口
            echo "# Generated by ZeroTier Gateway" > "/etc/resolv.conf"
            echo "nameserver 127.0.0.1#5353" >> "/etc/resolv.conf"
            log "INFO" "已配置系统使用本地DNS服务端口5353"
        fi
    fi

    # 配置 dnsmasq 只监听本地接口
    if [ -f "/etc/dnsmasq.conf" ]; then
        # 备份原始配置
        cp -f "/etc/dnsmasq.conf" "/etc/dnsmasq.conf.bak"

        # 移除旧的监听配置
        sed -i '/^listen-address=/d' "/etc/dnsmasq.conf"

        # 只监听本地接口，避免与其他DNS服务冲突
        echo "listen-address=127.0.0.1" >> "/etc/dnsmasq.conf"
        # 检查是否已有接口绑定配置
        if ! grep -q "^bind-interfaces" "/etc/dnsmasq.conf"; then
            echo "bind-interfaces" >> "/etc/dnsmasq.conf"
        fi
    fi

    # 创建配置文件软链接，先检查源和目标是否相同
    if [ "$SCRIPT_DNSMASQ_CONF" != "$DNSMASQ_CONF" ]; then
        # 确保目标目录存在
        mkdir -p $(dirname "$DNSMASQ_CONF") 2>/dev/null
        ln -sf "$SCRIPT_DNSMASQ_CONF" "$DNSMASQ_CONF" 2>/dev/null || {
            sudo ln -sf "$SCRIPT_DNSMASQ_CONF" "$DNSMASQ_CONF" 2>/dev/null || {
                log "INFO" "使用复制代替dnsmasq配置软链接"
                cp -f "$SCRIPT_DNSMASQ_CONF" "$DNSMASQ_CONF"
            }
        }
    fi

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

    # 添加初始IP地址到ipset (默认DNS服务器)
    log "INFO" "添加初始IP到ipset..."
    ipset add "$GFWLIST_IPSET" 223.5.5.5 2>/dev/null || log "INFO" "IP 223.5.5.5 已存在"
    ipset add "$GFWLIST_IPSET" 223.6.6.6 2>/dev/null || log "INFO" "IP 223.6.6.6 已存在"
    ipset add "$GFWLIST_IPSET" 8.8.8.8 2>/dev/null || log "INFO" "IP 8.8.8.8 已存在"
    ipset add "$GFWLIST_IPSET" 1.1.1.1 2>/dev/null || log "INFO" "IP 1.1.1.1 已存在"

    # 添加一些常见国外网站的IP，确保基本功能可用
    log "INFO" "添加常见网站IP..."
    # 尝试解析并添加Google的IP
    for ip in $(dig +short google.com @223.5.5.5 2>/dev/null); do
        ipset add "$GFWLIST_IPSET" $ip 2>/dev/null && log "INFO" "添加IP: $ip (Google)"
    done

    # 保存 ipset 配置
    mkdir -p /etc/sysconfig/
    echo "IPSET_SAVE_ON_STOP=yes" > /etc/sysconfig/ipset
    echo "IPSET_SAVE_ON_RESTART=yes" > /etc/sysconfig/ipset

    # 创建 ipset 服务启动时加载的配置
    # 保存包含初始IP的ipset列表
    ipset save > /etc/sysconfig/ipset.conf

    log "INFO" "IP 集合配置完成"
    return 0
}

# 初始化 GFW List 模式
init_gfwlist_mode() {
    log "INFO" "初始化 GFW List 模式..."

    # 下载和解析 GFW List
    download_gfwlist

    # 初始化自定义域名列表
    init_custom_domains

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
SCRIPT_CUSTOM_DOMAINS="\$CONFIG_DIR/custom_domains.txt"
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
    echo "server=223.5.5.5" >> "\$SCRIPT_DNSMASQ_CONF"  # 阿里DNS主
    echo "server=223.6.6.6" >> "\$SCRIPT_DNSMASQ_CONF"  # 阿里DNS备用
    echo "server=8.8.8.8" >> "\$SCRIPT_DNSMASQ_CONF"    # Google DNS (备用)
    echo "server=1.1.1.1" >> "\$SCRIPT_DNSMASQ_CONF"    # Cloudflare DNS (备用)
    echo "" >> "\$SCRIPT_DNSMASQ_CONF"

    # 基本配置
    echo "# 基本配置" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "cache-size=10000" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "min-cache-ttl=3600" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "dns-forward-max=1000" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "neg-ttl=600" >> "\$SCRIPT_DNSMASQ_CONF"
    echo "" >> "\$SCRIPT_DNSMASQ_CONF"

    # 添加GFW List域名规则
    echo "# GFW List 域名规则 - 共 \$(wc -l < "\$SCRIPT_GFWLIST_DOMAINS") 条" >> "\$SCRIPT_DNSMASQ_CONF"
    while IFS= read -r domain; do
        echo "ipset=/\$domain/\$GFWLIST_IPSET" >> "\$SCRIPT_DNSMASQ_CONF"
    done < "\$SCRIPT_GFWLIST_DOMAINS"

    # 添加自定义域名规则
    if [ -f "\$SCRIPT_CUSTOM_DOMAINS" ]; then
        custom_count=\$(grep -v '^#' "\$SCRIPT_CUSTOM_DOMAINS" | grep -v '^$' | wc -l)
        if [ "\$custom_count" -gt 0 ]; then
            echo "" >> "\$SCRIPT_DNSMASQ_CONF"
            echo "# 自定义域名规则 - 共 \$custom_count 条" >> "\$SCRIPT_DNSMASQ_CONF"
            grep -v '^#' "\$SCRIPT_CUSTOM_DOMAINS" | grep -v '^$' | while read -r domain; do
                echo "ipset=/\$domain/\$GFWLIST_IPSET" >> "\$SCRIPT_DNSMASQ_CONF"
            done
        fi
    fi

    # 更新软链接或复制文件，先检查源和目标是否相同
    if [ "\$SCRIPT_GFWLIST_LOCAL" != "/etc/zt-gateway/gfwlist.txt" ]; then
        mkdir -p /etc/zt-gateway/ 2>/dev/null
        ln -sf "\$SCRIPT_GFWLIST_LOCAL" "/etc/zt-gateway/gfwlist.txt" 2>/dev/null || cp -f "\$SCRIPT_GFWLIST_LOCAL" "/etc/zt-gateway/gfwlist.txt"
    fi

    if [ "\$SCRIPT_GFWLIST_DOMAINS" != "/etc/zt-gateway/gfwlist_domains.txt" ]; then
        mkdir -p /etc/zt-gateway/ 2>/dev/null
        ln -sf "\$SCRIPT_GFWLIST_DOMAINS" "/etc/zt-gateway/gfwlist_domains.txt" 2>/dev/null || cp -f "\$SCRIPT_GFWLIST_DOMAINS" "/etc/zt-gateway/gfwlist_domains.txt"
    fi

    if [ "\${SCRIPT_GFWLIST_LOCAL}.info" != "/etc/zt-gateway/gfwlist.txt.info" ]; then
        mkdir -p /etc/zt-gateway/ 2>/dev/null
        ln -sf "\${SCRIPT_GFWLIST_LOCAL}.info" "/etc/zt-gateway/gfwlist.txt.info" 2>/dev/null || cp -f "\${SCRIPT_GFWLIST_LOCAL}.info" "/etc/zt-gateway/gfwlist.txt.info"
    fi

    if [ "\$SCRIPT_DNSMASQ_CONF" != "\$DNSMASQ_CONF" ]; then
        mkdir -p $(dirname "\$DNSMASQ_CONF") 2>/dev/null
        ln -sf "\$SCRIPT_DNSMASQ_CONF" "\$DNSMASQ_CONF" 2>/dev/null || cp -f "\$SCRIPT_DNSMASQ_CONF" "\$DNSMASQ_CONF"
    fi

    # 重启 dnsmasq
    systemctl restart dnsmasq

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] GFW List 更新成功，共 \$(wc -l < "\$SCRIPT_GFWLIST_DOMAINS") 个域名" >> "\$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] GFW List 更新失败，无法下载" >> "\$LOG_FILE"
fi
EOL

    # 设置执行权限
    chmod +x "$SCRIPT_GFWLIST_UPDATE_SCRIPT"

    # 创建软链接到系统cron目录，先检查源和目标是否相同
    if [ "$SCRIPT_GFWLIST_UPDATE_SCRIPT" != "$SYSTEM_GFWLIST_UPDATE_SCRIPT" ]; then
        # 确保目标目录存在
        mkdir -p $(dirname "$SYSTEM_GFWLIST_UPDATE_SCRIPT") 2>/dev/null
        ln -sf "$SCRIPT_GFWLIST_UPDATE_SCRIPT" "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null || {
            sudo ln -sf "$SCRIPT_GFWLIST_UPDATE_SCRIPT" "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null || {
                log "INFO" "使用复制代替自动更新脚本软链接"
                cp -f "$SCRIPT_GFWLIST_UPDATE_SCRIPT" "$SYSTEM_GFWLIST_UPDATE_SCRIPT"
            }
        }
    fi

    # 确保系统脚本有执行权限
    chmod +x "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null || sudo chmod +x "$SYSTEM_GFWLIST_UPDATE_SCRIPT" 2>/dev/null

    log "INFO" "定期更新配置完成"
    return 0
}

# 更新 GFW List
update_gfwlist() {
    log "INFO" "更新 GFW List..."

    # 确保自定义域名列表存在
    if [ ! -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        init_custom_domains
    fi

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

    # 获取自定义域名数量
    local custom_domain_count=0
    if [ -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        custom_domain_count=$(grep -v '^#' "$SCRIPT_CUSTOM_DOMAINS" | grep -v '^$' | wc -l)
    fi

    # 检查 Squid 代理状态
    local squid_status="未知"
    if systemctl is-active --quiet squid; then
        squid_status="${GREEN}运行中${NC}"
    elif systemctl is-active --quiet squid3; then
        squid_status="${GREEN}运行中${NC}"
    else
        squid_status="${YELLOW}未运行${NC}"
    fi

    # 检查 3128 端口是否开放
    local port_status="未知"
    if netstat -tuln | grep -q ':3128 '; then
        port_status="${GREEN}已开放${NC}"
    else
        port_status="${YELLOW}未开放${NC}"
    fi

    echo -e "GFW List 模式: $status"
    echo -e "GFW List 域名列表: ${YELLOW}$domain_count${NC} 个域名"
    echo -e "自定义域名列表: ${YELLOW}$custom_domain_count${NC} 个域名"
    echo -e "配置文件位置: ${BLUE}$SCRIPT_CONFIG_DIR${NC}"
    echo -e "DNS 服务: $dnsmasq_status"
    echo -e "DNS 服务器: $dns_servers"
    echo -e "Squid 代理: $squid_status (端口 3128: $port_status)"
    echo -e "自动更新: $auto_update"
    echo -e "最后更新: $update_time"
    echo ""

    # 显示进一步操作的提示
    echo -e "${YELLOW}提示:${NC}"
    echo -e "- 更新 GFW List: ./zerotier-gateway.sh --update-gfwlist"
    echo -e "- 查看自定义域名: ./zerotier-gateway.sh --list-domains"
    echo -e "- 添加自定义域名: ./zerotier-gateway.sh --add-domain example.com"
    echo -e "- 查看详细流量: ./zerotier-gateway.sh --stats"
}

# 测试GFW List DNS解析和ipset添加功能
test_gfwlist() {
    echo -e "${GREEN}===== 测试 GFW List 功能 =====${NC}"
    echo ""

    # 检查ipset状态
    echo -e "${YELLOW}检查 ipset 状态...${NC}"
    if ! ipset list "$GFWLIST_IPSET" &>/dev/null; then
        echo -e "${RED}错误: ipset '$GFWLIST_IPSET' 不存在${NC}"
        return 1
    fi

    IP_COUNT=$(ipset list "$GFWLIST_IPSET" | grep -c "^[0-9]")
    echo -e "当前 ipset 中的IP数量: ${GREEN}$IP_COUNT${NC}"

    # 检查dnsmasq服务状态
    echo -e "\n${YELLOW}检查 dnsmasq 服务状态...${NC}"
    if systemctl is-active --quiet dnsmasq; then
        echo -e "dnsmasq 服务: ${GREEN}运行中${NC}"
    else
        echo -e "dnsmasq 服务: ${RED}未运行${NC}"
        echo -e "正在修复dnsmasq配置并尝试启动服务..."

        # 修复可能的端口冲突问题
        if [ -f "/etc/dnsmasq.conf" ]; then
            # 确保只监听本地地址
            sed -i '/^listen-address=/d' "/etc/dnsmasq.conf"
            echo "listen-address=127.0.0.1" >> "/etc/dnsmasq.conf"

            # 如果systemd-resolved在运行，配置dnsmasq使用不同的端口
            if systemctl is-active --quiet systemd-resolved; then
                echo -e "检测到systemd-resolved正在运行，配置dnsmasq使用5353端口..."
                sed -i '/^port=/d' "/etc/dnsmasq.conf"
                echo "port=5353" >> "/etc/dnsmasq.conf"
            fi
        fi

        # 尝试启动服务
        systemctl restart dnsmasq
        sleep 1
        if systemctl is-active --quiet dnsmasq; then
            echo -e "dnsmasq 服务已修复并启动: ${GREEN}成功${NC}"
        else
            echo -e "${RED}无法启动 dnsmasq 服务${NC}"
            return 1
        fi
    fi

    # 测试DNS解析
    echo -e "\n${YELLOW}测试DNS解析 (使用本地DNS)...${NC}"

    # 检测dnsmasq使用的端口
    local dns_port="53"
    if grep -q "^port=5353" /etc/dnsmasq.conf 2>/dev/null; then
        dns_port="5353"
        echo "检测到dnsmasq使用端口: 5353"
    else
        echo "使用默认DNS端口: 53"
    fi

    echo -e "解析 google.com..."
    # 尝试使用标准端口和备用端口
    GOOGLE_IPS=$(dig +short google.com @127.0.0.1 -p $dns_port)
    if [ -z "$GOOGLE_IPS" ]; then
        echo -e "${YELLOW}尝试其他DNS端口...${NC}"
        if [ "$dns_port" = "53" ]; then
            GOOGLE_IPS=$(dig +short google.com @127.0.0.1 -p 5353)
        else
            GOOGLE_IPS=$(dig +short google.com @127.0.0.1)
        fi
    fi

    if [ -z "$GOOGLE_IPS" ]; then
        echo -e "${RED}无法解析 google.com${NC}"
    else
        echo -e "${GREEN}成功解析 google.com: $GOOGLE_IPS${NC}"
    fi

    # 测试添加到ipset
    echo -e "\n${YELLOW}检查解析的IP是否已添加到ipset...${NC}"
    for ip in $GOOGLE_IPS; do
        if ipset test "$GFWLIST_IPSET" $ip 2>/dev/null; then
            echo -e "IP $ip ${GREEN}已存在${NC}于 ipset 中"
        else
            echo -e "IP $ip ${RED}不在${NC} ipset 中"
        fi
    done

    # 测试其他常见网站
    echo -e "\n${YELLOW}测试解析其他常见网站...${NC}"
    for domain in www.youtube.com facebook.com twitter.com github.com; do
        echo -e "解析 $domain..."
        # 使用已经确定有效的DNS端口
        if [ -n "$GOOGLE_IPS" ]; then
            # 使用第一次成功解析的方式
            IPS=$(dig +short $domain @127.0.0.1 ${dns_port:+-p $dns_port})
        else
            # 尝试多种解析方式
            IPS=$(dig +short $domain @127.0.0.1 -p $dns_port)
            if [ -z "$IPS" ] && [ "$dns_port" = "53" ]; then
                IPS=$(dig +short $domain @127.0.0.1 -p 5353)
            elif [ -z "$IPS" ]; then
                IPS=$(dig +short $domain @127.0.0.1)
            fi
        fi

        if [ -z "$IPS" ]; then
            echo -e "${RED}无法解析 $domain${NC}"
        else
            echo -e "${GREEN}成功解析 $domain${NC}"
            for ip in $IPS; do
                if ipset test "$GFWLIST_IPSET" $ip 2>/dev/null; then
                    echo -e "- IP $ip ${GREEN}已添加${NC}到 ipset"
                else
                    echo -e "- IP $ip ${RED}未添加${NC}到 ipset"
                fi
            done
        fi
        echo ""
    done

    # 输出统计信息
    echo -e "\n${YELLOW}测试完成${NC}"
    NEW_IP_COUNT=$(ipset list "$GFWLIST_IPSET" | grep -c "^[0-9]")
    echo -e "ipset IP数量: ${GREEN}$NEW_IP_COUNT${NC} (测试前: $IP_COUNT)"
    if [ $NEW_IP_COUNT -gt $IP_COUNT ]; then
        echo -e "${GREEN}测试成功: DNS查询已成功添加IP到ipset!${NC}"
    else
        echo -e "${YELLOW}注意: 测试过程中没有新IP添加到ipset${NC}"
        echo -e "这可能是因为:"
        echo -e "1. 域名已经被解析过，IP已经在ipset中"
        echo -e "2. DNS解析没有正确将IP添加到ipset"
        echo -e "3. 解析的域名不在GFW列表中"
    fi

    return 0
}

# 初始化自定义域名列表
init_custom_domains() {
    log "INFO" "初始化自定义域名列表..."

    # 确保配置目录存在
    mkdir -p "$SCRIPT_CONFIG_DIR"
    mkdir -p /etc/zt-gateway

    # 如果自定义域名列表文件不存在，创建它
    if [ ! -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        echo "# ZeroTier 网关自定义域名列表" > "$SCRIPT_CUSTOM_DOMAINS"
        echo "# 每行一个域名，支持通配符（如 *.example.com）" >> "$SCRIPT_CUSTOM_DOMAINS"
        echo "# 以#开头的行为注释" >> "$SCRIPT_CUSTOM_DOMAINS"
        echo "" >> "$SCRIPT_CUSTOM_DOMAINS"
        echo "# 示例:" >> "$SCRIPT_CUSTOM_DOMAINS"
        echo "#example.com" >> "$SCRIPT_CUSTOM_DOMAINS"
        echo "#*.example.org" >> "$SCRIPT_CUSTOM_DOMAINS"
    fi

    # 创建自定义域名列表软链接，先检查源和目标是否相同
    if [ "$SCRIPT_CUSTOM_DOMAINS" != "$CUSTOM_DOMAINS" ]; then
        # 确保目标目录存在
        mkdir -p $(dirname "$CUSTOM_DOMAINS") 2>/dev/null
        ln -sf "$SCRIPT_CUSTOM_DOMAINS" "$CUSTOM_DOMAINS" 2>/dev/null || {
            sudo ln -sf "$SCRIPT_CUSTOM_DOMAINS" "$CUSTOM_DOMAINS" 2>/dev/null || {
                log "INFO" "使用复制代替自定义域名列表软链接"
                cp -f "$SCRIPT_CUSTOM_DOMAINS" "$CUSTOM_DOMAINS"
            }
        }
    fi

    log "INFO" "自定义域名列表初始化完成"
    return 0
}

# 添加自定义域名
add_custom_domain() {
    local domain="$1"
    if [ -z "$domain" ]; then
        handle_error "请指定要添加的域名"
    fi

    # 确保自定义域名列表已初始化
    if [ ! -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        init_custom_domains
    fi

    # 检查域名是否已存在
    if grep -q "^$domain$" "$SCRIPT_CUSTOM_DOMAINS"; then
        log "WARN" "域名 $domain 已存在于自定义列表中"
        return 0
    fi

    # 添加域名
    echo "$domain" >> "$SCRIPT_CUSTOM_DOMAINS"
    log "INFO" "已添加域名 $domain 到自定义列表"

    # 更新 dnsmasq 配置
    setup_dnsmasq

    # 测试解析
    log "INFO" "测试解析 $domain..."
    local dns_port="53"
    if grep -q "^port=5353" /etc/dnsmasq.conf 2>/dev/null; then
        dns_port="5353"
    fi

    # 尝试解析域名
    local ips=$(dig +short $domain @127.0.0.1 -p $dns_port)
    if [ -z "$ips" ] && [ "$dns_port" = "53" ]; then
        ips=$(dig +short $domain @127.0.0.1 -p 5353)
    elif [ -z "$ips" ] && [ "$dns_port" = "5353" ]; then
        ips=$(dig +short $domain @127.0.0.1)
    fi

    if [ -n "$ips" ]; then
        log "INFO" "域名 $domain 解析成功，IP: $ips"
    else
        log "WARN" "域名 $domain 解析失败，但已添加到列表"
    fi

    return 0
}

# 删除自定义域名
remove_custom_domain() {
    local domain="$1"
    if [ -z "$domain" ]; then
        handle_error "请指定要删除的域名"
    fi

    # 确保自定义域名列表存在
    if [ ! -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        log "WARN" "自定义域名列表不存在"
        return 1
    fi

    # 检查域名是否存在
    if ! grep -q "^$domain$" "$SCRIPT_CUSTOM_DOMAINS"; then
        log "WARN" "域名 $domain 不在自定义列表中"
        return 1
    fi

    # 删除域名
    sed -i "/^$domain$/d" "$SCRIPT_CUSTOM_DOMAINS"
    log "INFO" "已删除域名 $domain 从自定义列表"

    # 更新 dnsmasq 配置
    setup_dnsmasq

    return 0
}

# 列出自定义域名
list_custom_domains() {
    echo -e "${GREEN}===== 自定义域名列表 =====${NC}"

    # 确保自定义域名列表存在
    if [ ! -f "$SCRIPT_CUSTOM_DOMAINS" ]; then
        echo -e "${YELLOW}自定义域名列表尚未创建${NC}"
        return 0
    fi

    # 计算非注释和非空行的数量
    local count=$(grep -v '^#' "$SCRIPT_CUSTOM_DOMAINS" | grep -v '^$' | wc -l)
    echo -e "共 ${YELLOW}$count${NC} 个自定义域名:"
    echo ""

    # 输出所有非注释和非空行
    grep -v '^#' "$SCRIPT_CUSTOM_DOMAINS" | grep -v '^$'

    echo ""
    echo -e "${YELLOW}提示:${NC}"
    echo -e "- 添加域名: ./zerotier-gateway.sh --add-domain example.com"
    echo -e "- 删除域名: ./zerotier-gateway.sh --remove-domain example.com"

    return 0
}

# 测试自定义域名
test_custom_domain() {
    local domain="$1"
    if [ -z "$domain" ]; then
        handle_error "请指定要测试的域名"
    fi

    echo -e "${GREEN}===== 测试自定义域名 $domain =====${NC}"

    # 检查DNS服务
    if ! systemctl is-active --quiet dnsmasq; then
        echo -e "${RED}错误: dnsmasq 服务未运行${NC}"
        return 1
    fi

    # 检测DNS端口
    local dns_port="53"
    if grep -q "^port=5353" /etc/dnsmasq.conf 2>/dev/null; then
        dns_port="5353"
        echo -e "使用DNS端口: 5353"
    else
        echo -e "使用DNS端口: 53"
    fi

    # 尝试解析域名
    echo -e "解析 $domain..."
    local ips=$(dig +short $domain @127.0.0.1 -p $dns_port)
    if [ -z "$ips" ] && [ "$dns_port" = "53" ]; then
        ips=$(dig +short $domain @127.0.0.1 -p 5353)
    elif [ -z "$ips" ] && [ "$dns_port" = "5353" ]; then
        ips=$(dig +short $domain @127.0.0.1)
    fi

    if [ -z "$ips" ]; then
        echo -e "${RED}无法解析 $domain${NC}"
        return 1
    fi

    echo -e "${GREEN}成功解析 $domain${NC}"
    echo -e "解析结果: $ips"

    # 检查IP是否在ipset中
    echo -e "\n${YELLOW}检查解析的IP是否添加到ipset...${NC}"
    for ip in $ips; do
        if ipset test "$GFWLIST_IPSET" $ip 2>/dev/null; then
            echo -e "IP $ip ${GREEN}已添加${NC}到 ipset"
        else
            echo -e "IP $ip ${RED}未添加${NC}到 ipset"
        fi
    done

    # 检查是否可以通过 Squid 代理访问
    echo -e "\n${YELLOW}检查 Squid 代理状态...${NC}"
    if netstat -tuln | grep -q ':3128 '; then
        echo -e "Squid 代理端口 ${GREEN}已开放${NC}，您可以通过 http://$domain:3128 访问此域名"
        echo -e "注意: 通过 Squid 代理的流量将由 Squid 决定路由方式，不受 GFW List 规则影响"
    else
        echo -e "Squid 代理端口 ${YELLOW}未开放${NC}"
    fi

    return 0
}

# 测试 Squid 代理功能
test_squid_proxy() {
    echo -e "${GREEN}===== 测试 Squid 代理 (端口 3128) =====${NC}"
    echo ""

    # 检查 Squid 服务是否运行
    local squid_running=0
    if systemctl is-active --quiet squid; then
        echo -e "Squid 服务状态: ${GREEN}运行中${NC} (squid)"
        squid_running=1
    elif systemctl is-active --quiet squid3; then
        echo -e "Squid 服务状态: ${GREEN}运行中${NC} (squid3)"
        squid_running=1
    else
        echo -e "Squid 服务状态: ${RED}未运行${NC}"
    fi

    # 检查 3128 端口是否开放
    echo -e "\n${YELLOW}检查端口 3128 状态...${NC}"
    if netstat -tuln | grep -q ':3128 '; then
        echo -e "端口 3128: ${GREEN}已开放${NC}"
        local pid=$(netstat -tuln | grep ':3128 ' | awk '{print $7}' | cut -d'/' -f1)
        if [ -n "$pid" ]; then
            local pname=$(ps -p $pid -o comm=)
            echo -e "端口被进程占用: $pname (PID: $pid)"
        fi
    else
        echo -e "端口 3128: ${RED}未开放${NC}"
        echo -e "请确认 Squid 配置正确并监听在端口 3128"
    fi

    # 检查防火墙规则
    echo -e "\n${YELLOW}检查防火墙规则...${NC}"
    echo -e "INPUT 链中的 Squid 规则:"
    iptables -L INPUT -n | grep -i "dpt:3128" || echo "未找到针对端口 3128 的 INPUT 规则"

    echo -e "\nPREROUTING 链中的 Squid 规则:"
    iptables -t nat -L PREROUTING -n | grep -i "dpt:3128" || echo "未找到针对端口 3128 的 NAT PREROUTING 规则"

    echo -e "\nPOSTROUTING 链中的 Squid 规则:"
    iptables -t nat -L POSTROUTING -n | grep -i "dpt:3128\|squid" || echo "未找到针对端口 3128 的 NAT POSTROUTING 规则"

    echo -e "\nMANGLE 规则中的 Squid 相关规则:"
    iptables -t mangle -L -n | grep -i "dpt:3128\|spt:3128\|mark match 0x2" || echo "未找到 Squid 相关的 MANGLE 规则"

    echo -e "\nCONNMARK 规则检查:"
    iptables -t mangle -L -n | grep -i "CONNMARK" || echo "未找到 CONNMARK 相关规则"

    # 检查策略路由规则
    echo -e "\n${YELLOW}检查策略路由规则...${NC}"
    echo -e "策略路由表配置:"
    grep "squid" /etc/iproute2/rt_tables || echo "未找到 Squid 的路由表配置"

    echo -e "\n路由策略规则:"
    ip rule list | grep "fwmark 2" || echo "未找到 Squid 的策略路由规则"

    echo -e "\nSquid 路由表内容:"
    ip route show table squid || echo "Squid 路由表不存在或为空"

    # 如果 Squid 运行中，尝试检查配置
    if [ "$squid_running" = "1" ]; then
        echo -e "\n${YELLOW}检查 Squid 配置...${NC}"
        local squid_cmd="squid"
        if command -v squid3 &> /dev/null; then
            squid_cmd="squid3"
        fi

        # 检查 Squid 监听端口
        echo -e "Squid 监听端口:"
        $squid_cmd -v 2>/dev/null | grep -i "listening" || echo "无法获取 Squid 监听信息"

        # 检查 Squid 配置文件
        if [ -f "/etc/squid/squid.conf" ]; then
            echo -e "\nSquid 配置文件检查 (/etc/squid/squid.conf):"
            grep -i "^http_port" /etc/squid/squid.conf || echo "未找到 http_port 配置"
        elif [ -f "/etc/squid3/squid.conf" ]; then
            echo -e "\nSquid 配置文件检查 (/etc/squid3/squid.conf):"
            grep -i "^http_port" /etc/squid3/squid.conf || echo "未找到 http_port 配置"
        else
            echo -e "\n未找到 Squid 配置文件"
        fi
    fi

    # 检查 Docker 容器中的 Squid
    echo -e "\n${YELLOW}检查 Docker 容器中的 Squid...${NC}"
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        echo -e "Docker 状态: ${GREEN}运行中${NC}"
        echo -e "搜索映射到 3128 端口的 Docker 容器:"
        docker ps | grep -E ":[0-9]+->3128/tcp" || echo "未找到映射到 3128 端口的容器"

        # 如果有容器，显示详细信息
        local container_id=$(docker ps | grep -E ":[0-9]+->3128/tcp" | awk '{print $1}')
        if [ -n "$container_id" ]; then
            echo -e "\n${GREEN}检测到 Squid 容器${NC} (ID: $container_id)"
            echo -e "容器网络配置:"
            docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container_id
            echo -e "端口映射:"
            docker port $container_id
        fi
    else
        echo -e "Docker 状态: ${RED}未运行或未安装${NC}"
    fi

    echo -e "\n${YELLOW}测试与外部的连接...${NC}"
    echo -e "通过 Squid 代理测试连接到 google.com:"
    if command -v curl &> /dev/null; then
        curl -I -x 127.0.0.1:3128 -m 5 http://www.google.com 2>/dev/null && \
            echo -e "${GREEN}成功通过 Squid 代理连接到 google.com${NC}" || \
            echo -e "${RED}无法通过 Squid 代理连接到 google.com${NC}"
    else
        echo -e "未安装 curl，无法进行连接测试"
    fi

    # 测试防火墙标记是否生效
    echo -e "\n${YELLOW}测试防火墙标记规则...${NC}"
    echo -e "发送测试连接到 Squid 端口，检查标记应用:"
    if command -v curl &> /dev/null; then
        # 启动后台流量监控
        echo "启动流量监控..."
        timeout 3 iptables -t mangle -L PREROUTING -v -n -x > /dev/null &
        # 发送测试连接
        curl -I -s -x 127.0.0.1:3128 -m 2 http://www.baidu.com >/dev/null
        sleep 1
        # 检查标记
        iptables -t mangle -L PREROUTING -v -n | grep "mark match 0x2" | grep -q "dpt:3128" && \
            echo -e "${GREEN}Squid 流量标记规则正常工作${NC}" || \
            echo -e "${RED}Squid 流量标记规则可能未正确应用${NC}"
    fi

    echo -e "\n${YELLOW}建议:${NC}"
    echo -e "1. 确保 Squid 服务已启动且监听在端口 3128"
    echo -e "2. 检查 Squid 配置是否正确，特别是 http_port 设置"
    echo -e "3. 确认防火墙规则是否正确设置"
    echo -e "4. 如果使用 Docker 容器，确保端口映射正确 (3128:3128)"
    echo -e "5. 可以尝试重启 Squid 服务或容器"
    echo -e "5. 查看 Squid 日志以获取更多信息: cat /var/log/squid/access.log"

    return 0
}
