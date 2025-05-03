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
    iptables -t nat -A POSTROUTING -s $ZT_NETWORK -o $WAN_INTERFACE -j MASQUERADE
    iptables -t nat -A POSTROUTING -o $ZT_INTERFACE -j MASQUERADE
    iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    # 允许必要的服务
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 9993 -j ACCEPT

    # IPv6 防火墙规则 (如果启用)
    if [ "$IPV6_ENABLED" = "1" ]; then
        setup_ipv6_firewall "$ZT_INTERFACE"
    fi

    # 防止 DoS 攻击的简单限速
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

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