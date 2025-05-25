#!/bin/bash
#
# ZeroTier 高级网关配置脚本 - CentOS 重构版
# 功能：配置 CentOS 服务器作为 ZeroTier 网络的网关，支持双向流量及 HTTPS
# 版本：3.1 (重构版)
#

set -e  # 在错误时退出

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 初始化全局变量
DEBUG_MODE=0
ZT_MTU=1400
IPV6_ENABLED=0
GFWLIST_MODE=0
DNS_LOGGING=1
UPDATE_MODE=0
RESTART_MODE=0
SKIP_NETWORK_CHECK=0

# 按依赖顺序加载功能模块
source "$SCRIPT_DIR/cmd/utils.sh"      # 基础工具函数
source "$SCRIPT_DIR/cmd/config.sh"    # 配置管理
source "$SCRIPT_DIR/cmd/args.sh"      # 参数解析
source "$SCRIPT_DIR/cmd/detect.sh"    # 网络检测和帮助
source "$SCRIPT_DIR/cmd/monitor.sh"   # 监控功能
source "$SCRIPT_DIR/cmd/uninstall.sh" # 卸载功能
source "$SCRIPT_DIR/cmd/firewall.sh"  # 防火墙配置
source "$SCRIPT_DIR/cmd/gfwlist.sh"   # GFW List 功能
source "$SCRIPT_DIR/cmd/dnslog.sh"    # DNS 日志功能

# 主函数
main() {
    # 显示启动信息
    echo -e "${GREEN}===== ZeroTier 全局路由网关 v3.1 (重构版) =====${NC}"
    echo -e "${BLUE}正在启动网关配置程序...${NC}"
    echo ""

    # 初始化系统
    log "INFO" "ZeroTier 网关配置开始 - 版本 3.1"

    # 先解析命令行参数 (某些参数如 -h 不需要系统检查)
    parse_arguments "$@"

    # 如果是帮助、状态查看等不需要系统修改的操作，在参数解析时已经处理并退出
    # 以下代码只有在需要进行实际配置时才会执行

    # 系统环境检查
    log "INFO" "开始系统环境检查..."
    check_system_environment

    # 初始化配置系统
    init_config_system

    # 验证参数
    validate_arguments

    # 加载现有配置
    load_config

    # 检测网络环境
    detect_network_environment

    # 配置网关
    configure_gateway

    # 保存配置
    save_config

    # 显示完成信息
    show_completion_summary
}

# 检测网络环境
detect_network_environment() {
    log "INFO" "检测网络环境..."

    # 在调试模式下显示当前网络接口信息
    if [ "$DEBUG_MODE" = "1" ]; then
        show_network_interfaces
    fi    # 调试模式下检查 ZeroTier 状态
    if [ "$DEBUG_MODE" = "1" ]; then
        check_zerotier_status
    fi

    # 检测ZeroTier接口
    if [ -z "$ZT_INTERFACE" ]; then
        log "DEBUG" "自动检测 ZeroTier 接口..."
        # 获取接口名并去除可能的额外字符
        ZT_INTERFACE=$(detect_zt_interface)

        # 确保变量没有不可见字符
        ZT_INTERFACE=$(echo "$ZT_INTERFACE" | tr -d '\r\n \t')
        log "DEBUG" "检测到的 ZeroTier 接口（清理后）: '$ZT_INTERFACE'"

        if [ -z "$ZT_INTERFACE" ]; then
            # 在出错前再次检查 ZeroTier 状态
            check_zerotier_status
            handle_error "未找到 ZeroTier 网络接口，请确认已加入网络"
        elif [ "$ZT_INTERFACE" = "multiple" ]; then
            # 处理多个接口的情况
            echo -e "${YELLOW}检测到多个 ZeroTier 接口:${NC}"
            for i in "${!ZT_MULTIPLE_INTERFACES[@]}"; do
                echo "  $((i+1)). ${ZT_MULTIPLE_INTERFACES[i]}"
            done
            read -p "请选择要使用的接口编号: " choice
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#ZT_MULTIPLE_INTERFACES[@]}" ]; then
                ZT_INTERFACE="${ZT_MULTIPLE_INTERFACES[$((choice-1))]}"
                # 清理选择的接口名
                ZT_INTERFACE=$(echo "$ZT_INTERFACE" | tr -d '\r\n \t')
                log "INFO" "用户选择接口: $ZT_INTERFACE"
            else
                handle_error "无效的选择"
            fi
        fi
    fi
    log "INFO" "使用 ZeroTier 接口: $ZT_INTERFACE"

    # 检测WAN接口
    if [ -z "$WAN_INTERFACE" ]; then
        log "DEBUG" "自动检测 WAN 接口..."
        WAN_INTERFACE=$(detect_wan_interface)
        if [ -z "$WAN_INTERFACE" ]; then
            handle_error "未能检测到外网接口"
        fi
    fi
    log "INFO" "使用外网接口: $WAN_INTERFACE"    # 验证接口是否存在
    log "DEBUG" "验证 ZeroTier 接口 '$ZT_INTERFACE' 是否存在..."
    if [ -z "$ZT_INTERFACE" ]; then
        handle_error "ZeroTier 接口名为空，检测失败"
    fi

    # 显示调试信息，帮助诊断问题
    if [ "$DEBUG_MODE" = "1" ]; then
        log "DEBUG" "所有网络接口列表:"
        ip link show | grep -E '^[0-9]+:' | cut -d' ' -f2 | tr -d ':'
    fi

    if ! ip link show "$ZT_INTERFACE" >/dev/null 2>&1; then
        handle_error "ZeroTier 接口 '$ZT_INTERFACE' 不存在，请检查接口名称是否正确"
    else
        log "DEBUG" "确认 ZeroTier 接口 '$ZT_INTERFACE' 存在"
    fi

    log "DEBUG" "验证外网接口 '$WAN_INTERFACE' 是否存在..."
    if ! ip link show "$WAN_INTERFACE" >/dev/null 2>&1; then
        handle_error "外网接口 '$WAN_INTERFACE' 不存在"
    else
        log "DEBUG" "确认外网接口 '$WAN_INTERFACE' 存在"
    fi    # 获取网络信息
    log "DEBUG" "获取网络信息..."

    # 确保接口名称已清理
    ZT_INTERFACE=$(clean_interface_name "$ZT_INTERFACE")
    WAN_INTERFACE=$(clean_interface_name "$WAN_INTERFACE")

    # 获取网络信息
    ZT_NETWORK=$(get_zt_network "$ZT_INTERFACE")
    WAN_IP=$(get_interface_ip "$WAN_INTERFACE")

    log "INFO" "ZeroTier 网络: $ZT_NETWORK"
    log "INFO" "外网 IP: $WAN_IP"

    # 在调试模式下显示详细信息
    if [ "$DEBUG_MODE" = "1" ]; then
        log "DEBUG" "网络环境详细信息:"
        log "DEBUG" "  ZeroTier 接口: $ZT_INTERFACE"
        log "DEBUG" "  ZeroTier 网络: $ZT_NETWORK"
        log "DEBUG" "  WAN 接口: $WAN_INTERFACE"
        log "DEBUG" "  WAN IP: $WAN_IP"
        log "DEBUG" "  MTU 设置: $ZT_MTU"
    fi
}

# 配置网关
configure_gateway() {
    log "INFO" "开始配置网关..."

    # 检查是否以 root 运行
    if [ "$EUID" -ne 0 ]; then
        handle_error "请使用 root 权限运行此脚本"
    fi

    # 准备目录
    prepare_dirs

    # 确保 iptables-services 已安装
    if ! rpm -q iptables-services &>/dev/null; then
        log "INFO" "安装 iptables-services..."
        yum install -y iptables-services || handle_error "安装 iptables-services 失败"
    fi

    # 检查接口是否存在
    ip link show "$ZT_INTERFACE" >/dev/null 2>&1 || handle_error "ZeroTier 接口 $ZT_INTERFACE 不存在"
    ip link show "$WAN_INTERFACE" >/dev/null 2>&1 || handle_error "外网接口 $WAN_INTERFACE 不存在"

    # 获取 ZeroTier 网络 ID (如果可能的话)
    ZT_NETWORK_ID=""
    if command -v zerotier-cli >/dev/null 2>&1; then
        ZT_NETWORK_ID=$(zerotier-cli listnetworks | grep -v NETWORK | awk '{print $3}' | head -1)
        if [ -n "$ZT_NETWORK_ID" ]; then
            log "INFO" "ZeroTier 网络 ID: $ZT_NETWORK_ID"
        fi
    fi

    # 配置内核参数
    log "INFO" "配置内核参数..."
    configure_kernel_parameters

    # 调整网络接口设置
    log "INFO" "调整网络接口设置..."
    configure_network_interfaces

    # 配置功能模块
    configure_feature_modules    # 配置防火墙规则
    log "INFO" "配置防火墙规则..."
    # 再次确保接口名称清理（以防之前的清理结果被覆盖）
    ZT_INTERFACE=$(clean_interface_name "$ZT_INTERFACE")
    WAN_INTERFACE=$(clean_interface_name "$WAN_INTERFACE")
    setup_firewall "$ZT_INTERFACE" "$WAN_INTERFACE" "$ZT_NETWORK" "$IPV6_ENABLED" "$GFWLIST_MODE" "$DNS_LOGGING"

    # 配置系统服务
    configure_system_services

    # 测试网关连通性
    log "INFO" "测试网关连通性..."
    test_gateway_connectivity
}

# 配置内核参数
configure_kernel_parameters() {
    # 使用配置管理系统处理 sysctl 配置
    local sysctl_template="sysctl.conf.template"

    if [ -f "$SCRIPT_DIR/templates/$sysctl_template" ]; then
        # 处理模板并应用配置
        process_template "$sysctl_template" "/etc/sysctl.d/99-zt-gateway.conf"

        # 应用 sysctl 配置
        sysctl -p /etc/sysctl.d/99-zt-gateway.conf || handle_error "应用内核参数失败"
        log "INFO" "内核参数配置完成"
    else
        handle_error "找不到 sysctl 配置模板文件"
    fi
}

# 配置网络接口
configure_network_interfaces() {
    # 调整 ZeroTier 接口的 MTU
    log "INFO" "调整 $ZT_INTERFACE MTU 为 $ZT_MTU..."
    ip link set "$ZT_INTERFACE" mtu "$ZT_MTU" || handle_error "调整 MTU 失败"

    # 创建网络接口监控脚本
    log "INFO" "配置网络接口监控脚本..."
    local network_monitor_template="network-monitor.sh.template"

    if [ -f "$SCRIPT_DIR/templates/$network_monitor_template" ]; then
        process_template "$network_monitor_template" "/etc/NetworkManager/dispatcher.d/99-ztmtu.sh"
        chmod +x /etc/NetworkManager/dispatcher.d/99-ztmtu.sh
        log "INFO" "网络监控脚本配置完成"
    else
        handle_error "找不到网络监控脚本模板"
    fi
}

# 配置功能模块
configure_feature_modules() {
    # 配置防火墙规则
    log "INFO" "配置防火墙规则..."
    setup_firewall "$ZT_INTERFACE" "$WAN_INTERFACE" "$ZT_NETWORK"

    # 如果启用了 GFW List 模式，初始化相关设置
    if [ "$GFWLIST_MODE" = "1" ]; then
        log "INFO" "启用 GFW List 分流模式..."
        download_gfwlist
        configure_gfw_rules "$ZT_INTERFACE" "$WAN_INTERFACE" "$ZT_NETWORK"

        # 配置 ipset 初始化服务
        setup_ipset_service
    fi

    # 如果启用了 DNS 日志功能，初始化相关设置
    if [ "$DNS_LOGGING" = "1" ]; then
        log "INFO" "启用 DNS 日志功能..."
        init_dns_logging
        configure_dns_logging_rules "$ZT_INTERFACE"
    fi
}

# 设置 ipset 服务
setup_ipset_service() {
    log "INFO" "创建 ipset 初始化脚本和服务..."

    # 创建 ipset 初始化脚本
    local ipset_init_template="ipset-init.sh.template"
    if [ -f "$SCRIPT_DIR/templates/$ipset_init_template" ]; then
        process_template "$ipset_init_template" "/usr/local/bin/ipset-init.sh"
        chmod +x /usr/local/bin/ipset-init.sh
    else
        handle_error "找不到 ipset 初始化脚本模板"
    fi

    # 创建 systemd 服务单元
    local ipset_service_template="ztgw-ipset.service.template"
    if [ -f "$SCRIPT_DIR/templates/$ipset_service_template" ]; then
        process_template "$ipset_service_template" "/etc/systemd/system/ztgw-ipset.service"
        systemctl daemon-reload
        systemctl enable ztgw-ipset.service
        log "INFO" "已启用 ipset 初始化服务"
    else
        handle_error "找不到 ipset 服务模板"
    fi

    # 立即运行初始化脚本
    /usr/local/bin/ipset-init.sh
}

# 配置系统服务
configure_system_services() {
    # 启用并重启防火墙服务
    restart_firewall_service

    # 配置时间同步
    if ! rpm -q chrony &>/dev/null; then
        log "INFO" "安装和配置 chrony 时间同步..."
        yum install -y chrony || handle_error "安装 chrony 失败"
        systemctl enable chronyd
        systemctl start chronyd
        chronyc makestep
    fi

    # 创建状态监控脚本
    log "INFO" "创建状态监控脚本..."
    local status_script_template="status-script.sh.template"
    if [ -f "$SCRIPT_DIR/templates/$status_script_template" ]; then
        process_template "$status_script_template" "/usr/local/bin/zt-status"
        chmod +x /usr/local/bin/zt-status
    else
        handle_error "找不到状态脚本模板文件"
    fi

    # 创建定时检查脚本
    log "INFO" "创建定时检查脚本..."
    local daily_check_template="daily-check.sh.template"
    if [ -f "$SCRIPT_DIR/templates/$daily_check_template" ]; then
        process_template "$daily_check_template" "/etc/cron.daily/zt-gateway-check"
        chmod +x /etc/cron.daily/zt-gateway-check
    else
        handle_error "找不到定时检查脚本模板文件"
    fi
}

# 显示完成信息
show_completion_summary() {
    log "INFO" "ZeroTier 网关配置完成"
    echo ""
    echo -e "${GREEN}===== ZeroTier 网关配置完成！ =====${NC}"
    echo -e "${GREEN}已配置的接口: ZT=$ZT_INTERFACE, WAN=$WAN_INTERFACE${NC}"
    echo -e "${GREEN}ZeroTier 网络: $ZT_NETWORK${NC}"

    if [ "$GFWLIST_MODE" = "1" ]; then
        echo ""
        echo -e "${YELLOW}GFW List 分流模式已启用！${NC}"
        echo -e "${YELLOW}仅 GFW List 中的网站会通过 ZeroTier 全局路由，其他网站走正常线路。${NC}"
        echo -e "${YELLOW}您可以使用 --update-gfwlist 参数更新 GFW List，使用 --gfwlist-status 查看状态。${NC}"
    else
        echo ""
        echo -e "${GREEN}您现在可以通过 ZeroTier 网络访问互联网，${NC}"
        echo -e "${GREEN}并且外部流量可以通过此服务器访问 ZeroTier 网络。${NC}"
    fi

    if [ "$DNS_LOGGING" = "1" ]; then
        echo ""
        echo -e "${YELLOW}DNS 日志功能已启用！${NC}"
        echo -e "${YELLOW}您可以使用以下命令查看 DNS 查询日志:${NC}"
        echo -e "${GREEN}  - 查看基本DNS日志: $0 --show-dns-log${NC}"
        echo -e "${GREEN}  - 按域名筛选日志: $0 --dns-log-domain <域名>${NC}"
        echo -e "${GREEN}  - 按状态筛选日志: $0 --dns-log-status \"已转发\"${NC}"
        echo -e "${GREEN}  - 显示更多记录:   $0 --dns-log-count 100${NC}"
        echo -e "${GREEN}  - 通过状态脚本:   /usr/local/bin/zt-status --dns-log${NC}"
    fi

    if [ "$IPV6_ENABLED" = "1" ]; then
        echo ""
        echo -e "${BLUE}IPv6 转发功能已启用${NC}"
    fi

    echo ""
    echo -e "${YELLOW}配置已通过 iptables-services 设置为开机自启动${NC}"
    echo -e "${YELLOW}如需查看总体状态，请运行: /usr/local/bin/zt-status${NC}"
    echo ""
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
