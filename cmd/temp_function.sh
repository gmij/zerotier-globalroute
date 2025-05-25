# 显示网络接口信息（调试用）
show_network_interfaces() {
    if [ "$DEBUG_MODE" = "1" ]; then
        log "DEBUG" "当前网络接口信息:"
        echo "============ 网络接口列表 ============"
        ip -o link show | while read -r line; do
            local if_name=$(echo "$line" | awk -F': ' '{print $2}' | cut -d'@' -f1)
            local if_state=$(echo "$line" | grep -o 'state [A-Z]*' | awk '{print $2}')
            echo "接口: $if_name, 状态: $if_state"

            # 显示 IP 地址
            local ip_addr=$(ip addr show "$if_name" 2>/dev/null | grep 'inet ' | head -1 | awk '{print $2}')
            if [ -n "$ip_addr" ]; then
                echo "  IP: $ip_addr"
            fi
        done
        echo "===================================="
    fi
}
