#!/bin/bash
#
# ZeroTier 网关卸载功能
#

# 卸载功能
uninstall_gateway() {
    echo -e "${YELLOW}警告: 此操作将卸载 ZeroTier 网关配置${NC}"
    read -p "是否继续? (y/n): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "操作已取消"
        exit 0
    fi
    
    # 清除 iptables 规则
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # 保存清空后的规则
    iptables-save > /etc/sysconfig/iptables
    
    # 禁用 IP 转发
    sysctl -w net.ipv4.ip_forward=0
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.d/*
    
    # 清理 GFW List 相关配置
    if command -v ipset &>/dev/null && ipset list gfwlist &>/dev/null; then
        echo -e "${YELLOW}清理 GFW List ipset...${NC}"
        ipset destroy gfwlist
    fi
    
    # 清理 dnsmasq 配置
    if [ -f "/etc/dnsmasq.d/zt-gfwlist.conf" ]; then
        echo -e "${YELLOW}清理 dnsmasq GFW List 配置...${NC}"
        rm -f /etc/dnsmasq.d/zt-gfwlist.conf
        systemctl restart dnsmasq &>/dev/null || true
    fi
    
    # 恢复原始的 resolv.conf
    if [ -f "/etc/resolv.conf.ztgw.bak" ]; then
        echo -e "${YELLOW}恢复原始 DNS 配置...${NC}"
        cp -f "/etc/resolv.conf.ztgw.bak" "/etc/resolv.conf"
    fi
    
    # 清理定时更新任务
    if [ -f "/etc/cron.weekly/update-gfwlist" ]; then
        echo -e "${YELLOW}清理 GFW List 自动更新配置...${NC}"
        rm -f /etc/cron.weekly/update-gfwlist
    fi
    
    # 清理系统目录中的 GFW List 相关文件
    echo -e "${YELLOW}清理 GFW List 数据文件...${NC}"
    rm -f /etc/zt-gateway/gfwlist.txt
    rm -f /etc/zt-gateway/gfwlist_domains.txt
    rm -f /etc/zt-gateway/gfwlist.txt.info
    
    # 清理策略路由
    echo -e "${YELLOW}清理策略路由...${NC}"
    ip rule del fwmark 1 table gfw 2>/dev/null || true
    ip route flush table gfw 2>/dev/null || true
    sed -i '/200 gfw/d' /etc/iproute2/rt_tables 2>/dev/null || true
    
    # 删除配置文件
    rm -f /etc/sysconfig/zt-gateway-config
    rm -f /etc/NetworkManager/dispatcher.d/99-ztmtu.sh
    rm -rf "$CONFIG_DIR"
    
    echo -e "${GREEN}ZeroTier 网关配置已移除${NC}"
}