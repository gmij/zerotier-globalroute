#!/bin/bash
#
# ZeroTier 网关防火墙规则配置
#

# 配置防火墙规则的主函数
setup_firewall() {
    local ZT_INTERFACE="$1"
    local WAN_INTERFACE="$2"
    local ZT_NETWORK="$3"
    local IPV6_ENABLED="$4"
    local GFWLIST_MODE="$5"

    # 确保 conntrack 模块已加载
    modprobe nf_conntrack

    # 清除现有规则
    log "INFO" "清除现有防火墙规则..."
    cleanup_firewall

    # 设置默认策略
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    # 创建自定义链，便于管理
    iptables -N ZT-IN 2>/dev/null || iptables -F ZT-IN
    iptables -N ZT-FWD 2>/dev/null || iptables -F ZT-FWD
    iptables -N ZT-OUT 2>/dev/null || iptables -F ZT-OUT

    # 基本规则
    log "INFO" "配置基本防火墙规则..."
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i $ZT_INTERFACE -j ZT-IN
    iptables -A FORWARD -i $ZT_INTERFACE -j ZT-FWD
    iptables -A OUTPUT -o $ZT_INTERFACE -j ZT-OUT

    # ZeroTier 入站规则
    iptables -A ZT-IN -j ACCEPT

    # ZeroTier 转发规则
    iptables -A ZT-FWD -o $ZT_INTERFACE -j ACCEPT  # ZeroTier 内部流量
    iptables -A ZT-FWD -o $WAN_INTERFACE -j ACCEPT  # ZeroTier 到外网

    # 转发规则
    iptables -A FORWARD -i $ZT_INTERFACE -o $ZT_INTERFACE -j ACCEPT
    iptables -A FORWARD -i $WAN_INTERFACE -o $ZT_INTERFACE -j ACCEPT
    iptables -A FORWARD -i $ZT_INTERFACE -o $WAN_INTERFACE -j ACCEPT
    iptables -A FORWARD -i $WAN_INTERFACE -o $ZT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

    # NAT 和 MSS 调整规则
    log "INFO" "配置 NAT 和 MSS 规则..."
    
    # 如果启用了 GFW List 模式，配置分流规则
    if [ "$GFWLIST_MODE" = "1" ]; then
        log "INFO" "配置 GFW List 分流规则..."
        
        # 确保 ipset 已创建
        if ! ipset list gfwlist &>/dev/null; then
            log "INFO" "创建 gfwlist ipset..."
            ipset create gfwlist hash:ip timeout 86400
            
            # 添加DNS以确保至少有一个IP在集合中
            ipset add gfwlist 223.5.5.5  # 阿里DNS主
            ipset add gfwlist 223.6.6.6  # 阿里DNS备用
            ipset add gfwlist 8.8.8.8    # Google DNS (备用)
            ipset add gfwlist 1.1.1.1    # Cloudflare DNS (备用)
        fi
        
        # 获取默认网关
        local DEFAULT_GW=$(ip route | grep default | grep -v linkdown | head -1 | awk '{print $3}')
        
        if [ -n "$DEFAULT_GW" ]; then
            # 添加策略路由
            if ! grep -q "200 gfw" /etc/iproute2/rt_tables; then
                echo "200 gfw" >> /etc/iproute2/rt_tables
            fi
            
            # 配置策略路由表
            ip route flush table gfw 2>/dev/null || true
            ip route add default via $DEFAULT_GW dev $WAN_INTERFACE table gfw
            
            # 删除可能的重复规则
            ip rule del fwmark 1 table gfw 2>/dev/null || true
            
            # 添加新规则 - 确保优先级低于Squid路由规则
            ip rule add fwmark 1 table gfw prio 32764
            
            # 添加 mark 规则，用于路由选择 (排除 Squid 代理端口 3128 的流量)
            iptables -t mangle -A PREROUTING -i $ZT_INTERFACE -p tcp ! --dport 3128 -m set --match-set gfwlist dst -j MARK --set-mark 1
            iptables -t mangle -A PREROUTING -i $ZT_INTERFACE -p udp -m set --match-set gfwlist dst -j MARK --set-mark 1
            
            # 为 Squid 代理流量添加特殊处理
            iptables -t nat -A POSTROUTING -s $ZT_NETWORK -p tcp --dport 3128 -o $WAN_INTERFACE -j MASQUERADE
            
            # 添加基本NAT规则，确保基本连接可用（排除已经处理的 Squid 流量）
            iptables -t nat -A POSTROUTING -s $ZT_NETWORK -p tcp ! --dport 3128 -o $WAN_INTERFACE -j MASQUERADE
            iptables -t nat -A POSTROUTING -s $ZT_NETWORK -p udp -o $WAN_INTERFACE -j MASQUERADE
            
            log "INFO" "GFW List 分流规则配置完成"
        else
            log "WARN" "无法获取默认网关，分流可能无法正常工作"
        fi
    else
        # 常规 NAT 规则（排除 Squid 流量）
        iptables -t nat -A POSTROUTING -s $ZT_NETWORK -p tcp ! --dport 3128 -o $WAN_INTERFACE -j MASQUERADE
        iptables -t nat -A POSTROUTING -s $ZT_NETWORK -p udp -o $WAN_INTERFACE -j MASQUERADE
        # 单独处理 Squid 代理流量
        iptables -t nat -A POSTROUTING -s $ZT_NETWORK -p tcp --dport 3128 -o $WAN_INTERFACE -j MASQUERADE
    fi
    
    iptables -t nat -A POSTROUTING -o $ZT_INTERFACE -j MASQUERADE
    iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    # 允许必要的服务
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 9993 -j ACCEPT
    
    # 允许 Squid 代理端口（3128）的入站流量
    iptables -A INPUT -p tcp --dport 3128 -j ACCEPT
    
    log "INFO" "配置 Squid 代理流量规则..."
    
    # 为 Squid 流量设置单独的策略路由表
    if ! grep -q "210 squid" /etc/iproute2/rt_tables; then
        echo "210 squid" >> /etc/iproute2/rt_tables
    fi
    
    # 获取默认网关
    local DEFAULT_GW=$(ip route | grep default | grep -v linkdown | head -1 | awk '{print $3}')
    
    if [ -n "$DEFAULT_GW" ]; then
        # 配置 Squid 代理路由表 - 不受 GFW List 影响的直接路由
        ip route flush table squid 2>/dev/null || true
        ip route add default via $DEFAULT_GW dev $WAN_INTERFACE table squid
        
        # 删除可能的重复规则
        ip rule del fwmark 2 table squid 2>/dev/null || true
        
        # 1. 对于来自 ZeroTier 网络到 Squid 代理端口的流量（入站）- 最高优先级
        iptables -t mangle -I PREROUTING 1 -i $ZT_INTERFACE -p tcp --dport 3128 -j MARK --set-mark 2
        
        # 2. 对于从Squid发出的请求 - 最高优先级
        iptables -t mangle -I OUTPUT 1 -p tcp --sport 3128 -j MARK --set-mark 2
        
        # 3. 确保这些标记不会被重新标记 - 最高优先级
        iptables -t mangle -I PREROUTING 1 -m mark --mark 2 -j ACCEPT
        iptables -t mangle -I OUTPUT 1 -m mark --mark 2 -j ACCEPT
        
        # 4. 确保 NAT 正确处理 Squid 流量 - 最高优先级
        iptables -t nat -I POSTROUTING 1 -m mark --mark 2 -j MASQUERADE
        
        # 5. 连接跟踪 - 配置一次，减少重复
        iptables -t mangle -A PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --restore-mark
        iptables -t mangle -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --restore-mark
        iptables -t mangle -A OUTPUT -m mark ! --mark 0 -j CONNMARK --save-mark
        iptables -t mangle -A PREROUTING -m mark ! --mark 0 -j CONNMARK --save-mark
        
        # 6. 添加策略路由规则 - 确保优先级明确
        ip rule add fwmark 2 table squid prio 32763
        
        log "INFO" "Squid 代理流量规则配置完成"
    else
        log "ERROR" "无法获取默认网关，Squid 路由无法配置"
    fi
    
    # IPv6 防火墙规则 (如果启用)
    if [ "$IPV6_ENABLED" = "1" ]; then
        setup_ipv6_firewall "$ZT_INTERFACE"
    fi

    # 保存规则
    save_firewall_rules
}

# 清理防火墙规则
cleanup_firewall() {
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
}

# 配置 IPv6 防火墙规则
setup_ipv6_firewall() {
    local ZT_INTERFACE="$1"
    
    log "INFO" "配置 IPv6 防火墙规则..."
    
    # 清除现有 IPv6 规则
    ip6tables -F
    ip6tables -t nat -F 2>/dev/null || true
    ip6tables -t mangle -F
    
    # 设置默认 IPv6 策略
    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT ACCEPT
    
    # 基本 IPv6 规则
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A FORWARD -i $ZT_INTERFACE -j ACCEPT
    ip6tables -A FORWARD -o $ZT_INTERFACE -j ACCEPT
    
    # 保存 IPv6 规则
    if command -v ip6tables-save >/dev/null 2>&1; then
        ip6tables-save > /etc/sysconfig/ip6tables
    fi
}

# 保存防火墙规则
save_firewall_rules() {
    log "INFO" "保存防火墙规则..."
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/sysconfig/iptables || handle_error "保存 iptables 规则失败"
    else
        log "WARN" "无法找到 iptables-save 命令，跳过保存规则"
    fi
}

# 重启防火墙服务
restart_firewall_service() {
    log "INFO" "重启 iptables 服务..."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable iptables
        systemctl restart iptables
    else
        log "WARN" "systemctl 不可用，使用传统方法重启 iptables"
        service iptables restart
    fi
}

# 检查防火墙规则是否存在
check_firewall_rules() {
    local ZT_INTERFACE="$1"
    local WAN_INTERFACE="$2"
    local ZT_NETWORK="$3"
    
    log "INFO" "检查防火墙规则..."
    
    # 检查基本链
    local has_chains=1
    iptables -L ZT-IN -n >/dev/null 2>&1 || has_chains=0
    
    # 检查 NAT 规则
    local nat_rules=$(iptables -t nat -L -v -n | grep MASQUERADE | wc -l)
    
    if [ "$has_chains" -eq 0 ] || [ "$nat_rules" -eq 0 ]; then
        log "WARN" "防火墙规则不完整，需要重新配置"
        return 1
    else
        log "INFO" "防火墙规则检查通过"
        return 0
    fi
}

# 更新防火墙规则（保留现有状态）
update_firewall_rules() {
    local ZT_INTERFACE="$1"
    local WAN_INTERFACE="$2"
    local ZT_NETWORK="$3"
    local IPV6_ENABLED="$4"
    
    log "INFO" "更新防火墙规则（保留链结构）..."
    
    # 清除现有自定义链内容但保留链结构
    iptables -F ZT-IN 2>/dev/null 
    iptables -F ZT-FWD 2>/dev/null
    iptables -F ZT-OUT 2>/dev/null
    
    # 重新应用规则
    setup_firewall "$ZT_INTERFACE" "$WAN_INTERFACE" "$ZT_NETWORK" "$IPV6_ENABLED"
}

# 专门检测 Squid 服务状态
check_squid_service() {
    local SQUID_PORT="3128"
    local squid_running=0
    
    log "INFO" "检测 Squid 服务状态..."
    
    # 检测 squid 服务
    if systemctl is-active --quiet squid; then
        log "INFO" "Squid 服务正在运行 (squid)"
        squid_running=1
    elif systemctl is-active --quiet squid3; then
        log "INFO" "Squid 服务正在运行 (squid3)"
        squid_running=1
    fi
    
    # 检测端口是否开放 - 包括容器映射的端口
    if netstat -tuln | grep -q ":${SQUID_PORT} "; then
        log "INFO" "检测到 ${SQUID_PORT} 端口已开放"
        squid_running=1
    fi
    
    # 检查 Docker 是否在运行，以及是否存在映射到 3128 端口的容器
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        if docker ps 2>/dev/null | grep -F ":3128" > /dev/null 2>&1; then
            log "INFO" "检测到 Docker 容器中的 Squid 服务 (端口映射)"
            squid_running=1
        fi
    fi
    
    if [ "$squid_running" = "0" ]; then
        log "WARN" "Squid 服务可能未运行，但仍将配置端口路由规则"
    fi
    
    return $squid_running
}