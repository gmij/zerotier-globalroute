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
    
    # 删除配置文件
    rm -f /etc/sysconfig/zt-gateway-config
    rm -f /etc/NetworkManager/dispatcher.d/99-ztmtu.sh
    rm -rf "$CONFIG_DIR"
    
    echo -e "${GREEN}ZeroTier 网关配置已移除${NC}"
}