#!/bin/bash
#
# ZeroTier 网关接口检测和帮助信息
#

# 显示帮助信息
show_help() {
    echo -e "${GREEN}ZeroTier 网关配置脚本 - 终极版${NC}"
    echo "用法: $0 [选项]"
    echo ""
    echo "基本选项:"
    echo "  -h, --help       显示此帮助信息"
    echo "  -z, --zt-if      指定 ZeroTier 接口名称 (默认: 自动检测)"
    echo "  -w, --wan-if     指定外网接口名称 (默认: 自动检测)"
    echo "  -m, --mtu        指定 ZeroTier 接口 MTU (默认: 1400)"
    echo "  -s, --status     显示当前配置状态"
    echo "  -b, --backup     备份当前 iptables 规则"
    echo ""
    echo "高级选项:"
    echo "  -d, --debug      启用调试模式"
    echo "  -r, --restart    重新应用现有配置"
    echo "  -u, --update     更新网关配置但保留接口设置"
    echo "  --ipv6           启用 IPv6 支持"
    echo "  --stats          显示网关流量统计"
    echo "  --test           测试网关连通性"
    echo "  --uninstall      卸载网关配置"
    echo "  --skip-network   跳过网络连接检查（如果 ping 被防火墙阻止）"
    echo ""
    echo "GFW List 选项:"
    echo "  -g, --gfwlist        启用 GFW List 分流模式 (仅 GFW List 中的域名走全局路由)"
    echo "  -G, --update-gfwlist 更新 GFW List"
    echo "  -S, --gfwlist-status 显示 GFW List 状态"
    echo "  --test-gfw          测试 GFW List 解析和 ipset 添加功能"
    echo ""
    echo "DNS日志选项(默认启用):"
    echo "  --show-dns-log      显示DNS查询日志"
    echo "  --dns-log-count 数量 指定显示的日志记录数量"
    echo "  --dns-log-domain 域名 按域名筛选日志"
    echo "  --dns-log-status 状态 按状态(已转发|未转发)筛选日志"
    echo "  --reset-dns-log     重置DNS日志"
    echo ""
    echo "自定义域名管理:"
    echo "  --list-domains      列出自定义域名"
    echo "  --add-domain 域名   添加自定义域名到 GFW List"
    echo "  --remove-domain 域名 从 GFW List 中删除自定义域名"
    echo "  --test-domain 域名   测试指定域名的解析和 ipset 添加情况"
    echo ""
    echo "代理服务:"
    echo "  端口 3128 (Squid)   所有通过端口 3128 的流量将由 Squid 代理决定路由"
    echo "                      这些流量不受 GFW List 分流规则影响"
    echo "                      支持原生 Squid 或 Docker 容器中的 Squid"
    echo "  --test-squid        测试 Squid 代理配置和连接状态"
    echo ""
}

# 自动检测 ZeroTier 接口
detect_zt_interface() {
    log "DEBUG" "开始检测 ZeroTier 接口..."

    # 方法1：检查网络接口名称
    log "DEBUG" "方法1：检查网络接口名称..."
    local zt_interfaces=($(ip link show | grep -o 'zt[a-zA-Z0-9]*' | sort -u))

    if [ "$DEBUG_MODE" = "1" ]; then
        log "DEBUG" "发现的 ZeroTier 接口: ${zt_interfaces[*]}"
    fi

    # 方法2：如果方法1未找到任何接口，检查 ZeroTier 程序状态
    if [ ${#zt_interfaces[@]} -eq 0 ] && command -v zerotier-cli >/dev/null; then
        log "DEBUG" "方法2：通过 zerotier-cli 检查..."
        local zt_info=$(zerotier-cli listnetworks 2>/dev/null)
        if [ $? -eq 0 ]; then
            # 从 zerotier-cli 输出提取接口名称
            zt_interfaces=($(echo "$zt_info" | awk 'NR>1 {print $8}' | grep -v '-' | sort -u))
            if [ "$DEBUG_MODE" = "1" ]; then
                log "DEBUG" "zerotier-cli 输出: $zt_info"
                log "DEBUG" "提取的接口: ${zt_interfaces[*]}"
            fi
        else
            log "DEBUG" "无法获取 ZeroTier 网络信息"
        fi
    fi

    # 处理检测结果
    if [ ${#zt_interfaces[@]} -eq 0 ]; then
        log "DEBUG" "未检测到 ZeroTier 接口"
        echo ""  # 没有找到
    elif [ ${#zt_interfaces[@]} -eq 1 ]; then
        log "DEBUG" "检测到单个 ZeroTier 接口: ${zt_interfaces[0]}"
        echo "${zt_interfaces[0]}"  # 只找到一个接口
    else
        log "DEBUG" "检测到多个 ZeroTier 接口: ${zt_interfaces[*]}"
        # 找到多个接口，返回一个空字符串，稍后会要求用户选择
        echo "multiple"
        ZT_MULTIPLE_INTERFACES=("${zt_interfaces[@]}")
    fi
}

# 自动检测 WAN 接口
detect_wan_interface() {
    log "DEBUG" "开始检测 WAN 接口..."

    # 检查默认路由使用的接口
    log "DEBUG" "方法1：检查默认路由..."
    local default_if=$(ip route | grep default | grep -v "linkdown\|tun\|zt\|docker\|veth" | head -1 | awk '{print $5}')

    if [ "$DEBUG_MODE" = "1" ]; then
        log "DEBUG" "默认路由信息:"
        ip route | grep default | head -3
        log "DEBUG" "检测到的默认接口: $default_if"
    fi

    if [ -n "$default_if" ]; then
        log "DEBUG" "使用默认路由接口: $default_if"
        echo "$default_if"
    else
        # 备用方法：查找非 lo、zt、tun 等的第一个活动接口
        log "DEBUG" "方法2：查找活动接口..."
        local first_if=$(ip -o link show up | grep -v 'lo\|zt\|tun\|docker\|veth' | head -1 | awk -F': ' '{print $2}' | cut -d '@' -f1)

        if [ "$DEBUG_MODE" = "1" ]; then
            log "DEBUG" "活动接口列表:"
            ip -o link show up | head -5
            log "DEBUG" "筛选后的第一个接口: $first_if"
        fi

        if [ -n "$first_if" ]; then
            log "DEBUG" "使用第一个活动接口: $first_if"
            echo "$first_if"
        else
            log "DEBUG" "使用默认接口名: eth0"
            echo "eth0"  # 默认值
        fi
    fi
}
