#!/bin/bash
#
# ZeroTier 网关防火墙规则配置模块 (重构版)
# 版本：3.1
#

# 配置防火墙规则的主函数
setup_firewall() {
    # 检查防火墙规则是否已经配置，防止重复配置
    if [ "$FIREWALL_CONFIGURED" = "1" ]; then
        log "DEBUG" "防火墙规则已配置，跳过..."
        return 0
    fi

    local zt_interface="$ZT_INTERFACE"
    local wan_interface="$WAN_INTERFACE"
    local zt_network="$ZT_NETWORK"
    local ipv6_enabled="$IPV6_ENABLED"
    local gfwlist_mode="$GFWLIST_MODE"
    local dns_logging="$DNS_LOGGING"

    log "INFO" "开始配置防火墙规则..."
    log "INFO" "ZT接口: $zt_interface, WAN接口: $wan_interface"
    log "INFO" "IPv6: $ipv6_enabled, GFW模式: $gfwlist_mode, DNS日志: $dns_logging"

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
    create_custom_chains

    # 配置基本规则
    configure_basic_rules "$zt_interface" "$wan_interface"

    # 配置NAT规则
    configure_nat_rules "$zt_interface" "$wan_interface" "$zt_network" "$gfwlist_mode"

    # 配置转发规则
    configure_forward_rules "$zt_interface" "$wan_interface" "$zt_network"

    # 如果启用了IPv6，配置IPv6规则
    if [ "$ipv6_enabled" = "1" ]; then
        configure_ipv6_rules "$zt_interface" "$wan_interface"
    fi

    # 如果启用了GFW List模式，配置特殊规则
    if [ "$gfwlist_mode" = "1" ]; then
        configure_gfwlist_rules "$zt_interface" "$wan_interface"
    fi

    # 如果启用了DNS日志，配置DNS日志规则
    if [ "$dns_logging" = "1" ]; then
        configure_dns_logging_rules "$zt_interface"
    fi

    # 保存防火墙规则
    save_firewall_rules

    log "INFO" "防火墙规则配置完成"
}

# 创建自定义链
create_custom_chains() {
    log "INFO" "创建自定义防火墙链..."

    # 创建自定义链，便于管理
    iptables -N ZT-IN 2>/dev/null || iptables -F ZT-IN
    iptables -N ZT-FWD 2>/dev/null || iptables -F ZT-FWD
    iptables -N ZT-OUT 2>/dev/null || iptables -F ZT-OUT
    iptables -N ZT-NAT 2>/dev/null || iptables -F ZT-NAT

    # 如果启用GFW模式，创建特殊链
    if [ "$GFWLIST_MODE" = "1" ]; then
        iptables -t nat -N ZT-GFW 2>/dev/null || iptables -t nat -F ZT-GFW
        iptables -t mangle -N ZT-MARK 2>/dev/null || iptables -t mangle -F ZT-MARK
    fi
}

# 配置基本规则
configure_basic_rules() {
    local zt_interface="$1"
    local wan_interface="$2"

    log "INFO" "配置基本防火墙规则..."

    # 基本规则
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # ZeroTier接口规则
    iptables -A INPUT -i "$zt_interface" -j ZT-IN
    iptables -A FORWARD -i "$zt_interface" -j ZT-FWD
    iptables -A OUTPUT -o "$zt_interface" -j ZT-OUT

    # ZeroTier 入站规则
    iptables -A ZT-IN -j ACCEPT

    # ZeroTier 转发规则
    iptables -A ZT-FWD -o "$zt_interface" -j ACCEPT  # ZeroTier 内部流量
    iptables -A ZT-FWD -o "$wan_interface" -j ACCEPT  # ZeroTier 到外网

    # 允许必要的服务
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 9993 -j ACCEPT  # ZeroTier 端口
    iptables -A INPUT -p tcp --dport 3128 -j ACCEPT  # Squid 代理端口

    log "INFO" "基础防火墙规则配置完成"
}

# 配置NAT规则
configure_nat_rules() {
    local zt_interface="$1"
    local wan_interface="$2"
    local zt_network="$3"
    local gfwlist_mode="$4"

    log "INFO" "配置NAT规则..."

    # 检查是否启用GFW分流模式
    if [ "$gfwlist_mode" = "1" ]; then
        # GFW分流模式的特殊处理
        if command -v ip >/dev/null 2>&1; then
            local default_gateway=$(ip route | grep default | head -1 | awk '{print $3}')
            if [ -n "$default_gateway" ]; then
                # 配置GFW分流规则
                configure_gfwlist_rules "$zt_interface" "$wan_interface"
                log "INFO" "GFW List 分流规则配置完成"
            else
                log "WARN" "无法获取默认网关，分流可能无法正常工作"
            fi
        else
            log "WARN" "无法获取默认网关，分流可能无法正常工作"
        fi
    else
        # 常规 NAT 规则（排除 Squid 流量）
        iptables -t nat -A POSTROUTING -s "$zt_network" -p tcp ! --dport 3128 -o "$wan_interface" -j MASQUERADE
        iptables -t nat -A POSTROUTING -s "$zt_network" -p udp -o "$wan_interface" -j MASQUERADE
        # 单独处理 Squid 代理流量
        iptables -t nat -A POSTROUTING -s "$zt_network" -p tcp --dport 3128 -o "$wan_interface" -j MASQUERADE
    fi

    iptables -t nat -A POSTROUTING -o "$zt_interface" -j MASQUERADE
    iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    # 如果启用了DNS日志功能
    if [ "$DNS_LOGGING" = "1" ]; then
        log "INFO" "已启用DNS日志功能，dnsmasq将直接记录DNS查询..."

        # 初始化DNS日志功能
        init_dns_logging

        log "INFO" "DNS日志功能已配置完成"
    fi
}

# 配置转发规则
configure_forward_rules() {
    local zt_interface="$1"
    local wan_interface="$2"
    local zt_network="$3"

    log "INFO" "配置转发规则..."

    # 允许从ZeroTier网络到WAN接口的转发
    iptables -A FORWARD -i "$zt_interface" -o "$wan_interface" -j ACCEPT

    # 允许已建立的连接和相关连接从WAN接口返回到ZeroTier网络
    iptables -A FORWARD -i "$wan_interface" -o "$zt_interface" -m state --state RELATED,ESTABLISHED -j ACCEPT

    # 在自定义链中添加转发规则
    iptables -A ZT-FWD -i "$zt_interface" -o "$wan_interface" -j ACCEPT
    iptables -A ZT-FWD -i "$wan_interface" -o "$zt_interface" -m state --state RELATED,ESTABLISHED -j ACCEPT

    log "INFO" "转发规则配置完成"
}

# 配置GFW规则
configure_gfw_rules() {
    local zt_interface="$1"
    local wan_interface="$2"
    local zt_network="$3"

    log "INFO" "配置GFW分流规则..."

    # 确保ipset存在
    if ! ipset list gfwlist >/dev/null 2>&1; then
        log "ERROR" "GFW ipset不存在，请先配置GFW List"
        return 1
    fi

    # 获取默认网关
    local default_gw=$(ip route | grep default | grep -v linkdown | head -1 | awk '{print $3}')

    if [ -n "$default_gw" ]; then
        # 添加策略路由表
        if ! grep -q "200 gfw" /etc/iproute2/rt_tables; then
            echo "200 gfw" >> /etc/iproute2/rt_tables
        fi

        # 配置策略路由表
        ip route flush table gfw 2>/dev/null || true
        ip route add default via "$default_gw" dev "$wan_interface" table gfw

        # 删除可能的重复规则
        ip rule del fwmark 1 table gfw 2>/dev/null || true

        # 添加新规则
        ip rule add fwmark 1 table gfw prio 32764

        # 添加mark规则用于路由选择
        iptables -t mangle -A PREROUTING -i "$zt_interface" -p tcp -m set --match-set gfwlist dst -j MARK --set-mark 1
        iptables -t mangle -A PREROUTING -i "$zt_interface" -p udp -m set --match-set gfwlist dst -j MARK --set-mark 1

        log "INFO" "GFW分流规则配置完成"
    else
        log "ERROR" "无法获取默认网关，GFW路由无法配置"
        return 1
    fi
}

# 配置Squid代理规则
configure_squid_rules() {
    local zt_interface="$1"
    local wan_interface="$2"

    log "INFO" "配置Squid代理流量规则..."

    # 获取默认网关
    local default_gw=$(ip route | grep default | grep -v linkdown | head -1 | awk '{print $3}')

    if [ -n "$default_gw" ]; then
        # 配置Squid代理路由表
        if ! grep -q "201 squid" /etc/iproute2/rt_tables; then
            echo "201 squid" >> /etc/iproute2/rt_tables
        fi

        ip route flush table squid 2>/dev/null || true
        ip route add default via "$default_gw" dev "$wan_interface" table squid

        # 删除可能的重复规则
        ip rule del fwmark 2 table squid 2>/dev/null || true

        # 对于来自ZeroTier网络到Squid代理端口的流量
        iptables -t mangle -I PREROUTING 1 -i "$zt_interface" -p tcp --dport 3128 -j MARK --set-mark 2

        # 对于从Squid发出的请求
        iptables -t mangle -I OUTPUT 1 -p tcp --sport 3128 -j MARK --set-mark 2

        # 确保这些标记不会被重新标记
        iptables -t mangle -I PREROUTING 1 -m mark --mark 2 -j ACCEPT
        iptables -t mangle -I OUTPUT 1 -m mark --mark 2 -j ACCEPT

        # 确保NAT正确处理Squid流量
        iptables -t nat -I POSTROUTING 1 -m mark --mark 2 -j MASQUERADE

        # 添加策略路由规则
        ip rule add fwmark 2 table squid prio 32763

        log "INFO" "Squid代理流量规则配置完成"
    else
        log "ERROR" "无法获取默认网关，Squid路由无法配置"
        return 1
    fi
}

# 配置DNS日志规则
configure_dns_logging_rules() {
    local zt_interface="$1"

    # 检查DNS规则是否已经配置
    if [ "$DNS_RULES_CONFIGURED" = "1" ]; then
        log "DEBUG" "DNS日志防火墙规则已配置，跳过..."
        return 0
    fi

    log "INFO" "配置DNS日志相关规则..."
    # 允许ZeroTier网络上的DNS查询流量
    iptables -A ZT-IN -i "$zt_interface" -p udp --dport 53 -j ACCEPT
    iptables -A ZT-IN -i "$zt_interface" -p tcp --dport 53 -j ACCEPT

    log "INFO" "DNS日志相关规则已配置"
    export DNS_RULES_CONFIGURED=1
}

# 配置GFWList分流规则
configure_gfwlist_rules() {
    local zt_interface="$1"
    local wan_interface="$2"

    log "INFO" "配置GFWList分流规则..."

    # 检查ipset是否已安装
    if ! command -v ipset >/dev/null 2>&1; then
        log "ERROR" "ipset未安装，无法配置GFWList分流"
        return 1
    fi

    # 创建gfwlist ipset（如果不存在）
    ipset list gfwlist >/dev/null 2>&1 || {
        ipset create gfwlist hash:ip hashsize 4096
        log "DEBUG" "创建ipset: gfwlist"
    }

    # 添加iptables规则，对GFWList中的IP进行标记
    iptables -t mangle -A PREROUTING -i "$zt_interface" -m set --match-set gfwlist dst -j MARK --set-mark 1
    iptables -t nat -A POSTROUTING -s "$zt_network" -m mark --mark 1 -o "$wan_interface" -j MASQUERADE

    log "INFO" "GFWList分流规则配置完成"
}

# 配置IPv6规则
configure_ipv6_rules() {
    local zt_interface="$1"
    local wan_interface="$2"

    log "INFO" "配置IPv6规则..."

    # 检查ip6tables是否可用
    if ! command -v ip6tables >/dev/null 2>&1; then
        log "WARN" "ip6tables未安装，跳过IPv6规则配置"
        return 1
    fi

    # 基本IPv6防火墙规则
    ip6tables -F
    ip6tables -t nat -F

    # 默认策略
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT

    # 允许本地连接
    ip6tables -A INPUT -i lo -j ACCEPT

    # 允许已建立连接的返回流量
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 允许ICMPv6（对IPv6必要）
    ip6tables -A INPUT -p ipv6-icmp -j ACCEPT

    # 允许ZeroTier接口的传入流量
    ip6tables -A INPUT -i "$zt_interface" -j ACCEPT

    # 配置转发规则
    ip6tables -A FORWARD -i "$zt_interface" -o "$wan_interface" -j ACCEPT
    ip6tables -A FORWARD -i "$wan_interface" -o "$zt_interface" -m state --state RELATED,ESTABLISHED -j ACCEPT

    # 配置NAT（如果需要）
    if command -v ip6tables-nat >/dev/null 2>&1; then
        ip6tables -t nat -A POSTROUTING -o "$wan_interface" -j MASQUERADE
    fi

    log "INFO" "IPv6规则配置完成"
}

# 保存防火墙规则
save_firewall_rules() {
    log "INFO" "保存防火墙规则..."

    # 使用统一的配置管理保存规则
    local iptables_rules_file="/etc/sysconfig/iptables"
    local ip6tables_rules_file="/etc/sysconfig/ip6tables"

    # 保存IPv4规则
    iptables-save > "$iptables_rules_file" || {
        log "ERROR" "保存IPv4防火墙规则失败"
        return 1
    }

    # 如果启用了IPv6，保存IPv6规则
    if [ "$IPV6_ENABLED" = "1" ]; then
        ip6tables-save > "$ip6tables_rules_file" || {
            log "ERROR" "保存IPv6防火墙规则失败"
            return 1
        }
    fi

    log "INFO" "防火墙规则已保存"
}

# 清理防火墙规则
cleanup_firewall() {
    log "DEBUG" "清理现有防火墙规则..."

    # 清空所有表和链
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -t raw -F 2>/dev/null || true

    # 删除自定义链
    iptables -X ZT-IN 2>/dev/null || true
    iptables -X ZT-FWD 2>/dev/null || true
    iptables -X ZT-OUT 2>/dev/null || true
    iptables -X ZT-NAT 2>/dev/null || true
    iptables -t nat -X ZT-GFW 2>/dev/null || true
    iptables -t mangle -X ZT-MARK 2>/dev/null || true

    # 清理IPv6规则（如果需要）
    if [ "$IPV6_ENABLED" = "1" ]; then
        ip6tables -F 2>/dev/null || true
        ip6tables -t nat -F 2>/dev/null || true
        ip6tables -t mangle -F 2>/dev/null || true
    fi

    # 清理策略路由
    ip rule del fwmark 1 table gfw 2>/dev/null || true
    ip rule del fwmark 2 table squid 2>/dev/null || true
    ip route flush table gfw 2>/dev/null || true
    ip route flush table squid 2>/dev/null || true
}

# 重启防火墙服务
restart_firewall_service() {
    log "INFO" "重启防火墙服务..."

    # 启用并重启 iptables 服务
    systemctl enable iptables
    systemctl restart iptables || {
        log "ERROR" "重启iptables服务失败"
        return 1
    }

    # 如果启用了IPv6，也处理ip6tables
    if [ "$IPV6_ENABLED" = "1" ]; then
        systemctl enable ip6tables
        systemctl restart ip6tables || {
            log "WARN" "重启ip6tables服务失败"
        }
    fi

    log "INFO" "防火墙服务重启完成"
}

# 测试防火墙规则
test_firewall_rules() {
    log "INFO" "测试防火墙规则..."

    # 检查基本规则是否存在
    if ! iptables -L ZT-IN &>/dev/null; then
        log "ERROR" "ZeroTier自定义链未找到"
        return 1
    fi

    # 检查NAT规则
    if ! iptables -t nat -L POSTROUTING | grep -q MASQUERADE; then
        log "ERROR" "NAT规则未找到"
        return 1
    fi

    # 检查GFW规则（如果启用）
    if [ "$GFWLIST_MODE" = "1" ]; then
        if ! ip rule show | grep -q "fwmark 0x1"; then
            log "ERROR" "GFW分流规则未找到"
            return 1
        fi
    fi

    log "INFO" "防火墙规则测试通过"
    return 0
}
