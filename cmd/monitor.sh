#!/bin/bash
#
# ZeroTier 网关监控和测试功能
#

# 从配置文件加载变量
source_config_if_exists() {
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# 网关测试功能
test_gateway() {
    log "INFO" "测试 ZeroTier 网关连通性..."

    # 确保配置已加载
    source_config_if_exists

    if [ -z "$ZT_INTERFACE" ]; then
        handle_error "找不到配置文件或ZeroTier接口配置，请先运行配置脚本"
    fi

    local test_result=0

    # 1. 检查 ZeroTier 接口状态
    log "DEBUG" "检查 ZeroTier 接口状态..."
    if ! ip link show "$ZT_INTERFACE" >/dev/null 2>&1; then
        log "ERROR" "ZeroTier 接口 $ZT_INTERFACE 不存在"
        test_result=1
    else
        log "INFO" "ZeroTier 接口 $ZT_INTERFACE 状态正常"
    fi

    # 2. 检查 IP 转发
    log "DEBUG" "检查 IP 转发..."
    local ip_forward=$(sysctl -n net.ipv4.ip_forward)
    if [ "$ip_forward" != "1" ]; then
        log "ERROR" "IP 转发未启用"
        test_result=1
    else
        log "INFO" "IP 转发已启用"
    fi

    # 3. 测试 ZeroTier 接口连通性
    log "DEBUG" "测试 ZeroTier 接口连通性..."
    if ping -c 1 -I "$ZT_INTERFACE" 8.8.8.8 >/dev/null 2>&1; then
        log "INFO" "从 ZeroTier 接口到外网连通性正常"
    else
        log "ERROR" "从 ZeroTier 接口到外网连通性异常"
        test_result=1
    fi

    # 4. 检查 NAT 规则
    log "DEBUG" "检查 NAT 规则..."
    local nat_rules=$(iptables -t nat -L -v -n | grep MASQUERADE | wc -l)
    if [ "$nat_rules" -gt 0 ]; then
        log "INFO" "NAT 规则配置正确"
    else
        log "ERROR" "NAT 规则不存在"
        test_result=1
    fi

    # 5. 检查 ZeroTier 服务状态
    log "DEBUG" "检查 ZeroTier 服务状态..."
    if systemctl is-active --quiet zerotier-one; then
        log "INFO" "ZeroTier 服务运行正常"
    else
        echo -e "${RED}ZeroTier 服务未运行${NC}"
        return 1
    fi

    echo -e "${GREEN}网关基础检查完成${NC}"
    return 0
}

# 显示流量统计
show_traffic_stats() {
    echo -e "${GREEN}===== ZeroTier 网关流量统计 =====${NC}"

    # 加载配置
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    if [ -z "$ZT_INTERFACE" ] || ! ip link show "$ZT_INTERFACE" >/dev/null 2>&1; then
        handle_error "无法找到有效的 ZeroTier 接口"
    fi

    # 获取流量统计
    local rx_bytes=$(cat /sys/class/net/$ZT_INTERFACE/statistics/rx_bytes)
    local tx_bytes=$(cat /sys/class/net/$ZT_INTERFACE/statistics/tx_bytes)
    local rx_packets=$(cat /sys/class/net/$ZT_INTERFACE/statistics/rx_packets)
    local tx_packets=$(cat /sys/class/net/$ZT_INTERFACE/statistics/tx_packets)

    # 转换为可读形式
    local rx_mb=$(echo "scale=2; $rx_bytes/1048576" | bc)
    local tx_mb=$(echo "scale=2; $tx_bytes/1048576" | bc)

    echo -e "${YELLOW}接口: $ZT_INTERFACE${NC}"
    echo "接收: $rx_mb MB ($rx_packets 数据包)"
    echo "发送: $tx_mb MB ($tx_packets 数据包)"
    echo ""

    echo -e "${YELLOW}连接追踪:${NC}"
    if [ -f /proc/net/nf_conntrack ]; then
        echo "当前连接数: $(cat /proc/net/nf_conntrack | wc -l)"
        echo "连接跟踪限制: $(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo '未知')"
        echo "连接跟踪使用率: $(awk 'BEGIN{printf "%.1f%%", 100*'$(cat /proc/net/nf_conntrack | wc -l)'/'$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo '1000')'}'))"
    else
        echo "无法获取连接跟踪信息"
    fi
    echo ""

    echo -e "${YELLOW}防火墙统计:${NC}"
    iptables -L -v -n | grep -E 'Chain INPUT|Chain FORWARD|Chain OUTPUT|Chain ZT-'
    echo ""
}

# 显示当前配置状态
show_status() {
    echo -e "${GREEN}===== ZeroTier 网关状态 =====${NC}"
    echo -e "${YELLOW}配置文件:${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo "未找到配置文件"
    fi
    echo ""
    echo -e "${YELLOW}网络接口:${NC}"
    ip addr | grep -E "$ZT_INTERFACE|$WAN_INTERFACE"
    echo ""
    echo -e "${YELLOW}IP 转发状态:${NC}"
    sysctl net.ipv4.ip_forward
    echo ""
    echo -e "${YELLOW}MTU 设置:${NC}"
    ip link show $ZT_INTERFACE | grep mtu
    echo ""
    echo -e "${YELLOW}当前 iptables 规则:${NC}"
    iptables -L -v -n | head -n 20
    echo "... (更多规则省略) ..."
    echo ""
    echo -e "${YELLOW}NAT 规则:${NC}"
    iptables -t nat -L -v -n
    echo ""
    echo -e "${YELLOW}iptables 服务状态:${NC}"
    systemctl status iptables --no-pager
    echo ""
    echo -e "${YELLOW}日志文件末尾:${NC}"
    tail -n 10 "$LOG_FILE"
}
