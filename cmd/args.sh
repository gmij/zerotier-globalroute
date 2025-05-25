#!/bin/bash
#
# ZeroTier 网关参数解析模块
# 统一处理命令行参数解析和参数验证
#

# 默认参数
ZT_INTERFACE=""
WAN_INTERFACE=""
ZT_MTU=1400
DEBUG_MODE=0
IPV6_ENABLED=0
GFWLIST_MODE=0
DNS_LOGGING=1  # 默认启用DNS日志
RESTART_MODE=0
UPDATE_MODE=0

# 显示版本信息
show_version() {
    echo -e "${GREEN}ZeroTier 全局路由网关 v3.0${NC}"
    echo -e "${BLUE}专为 CentOS 系统设计的 ZeroTier 网关配置工具${NC}"
    echo ""
}

# 解析命令行参数
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -z|--zt-if)
                ZT_INTERFACE="$2"
                shift
                ;;
            -w|--wan-if)
                WAN_INTERFACE="$2"
                shift
                ;;
            -m|--mtu)
                if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 576 ] && [ "$2" -le 9000 ]; then
                    ZT_MTU="$2"
                else
                    handle_error "无效的 MTU 值: $2 (范围: 576-9000)"
                fi
                shift
                ;;
            -s|--status)
                init_config_system
                load_config
                show_status
                exit 0
                ;;
            -b|--backup)
                backup_file="/root/iptables-backup-$(date +%Y%m%d-%H%M%S).rules"
                iptables-save > "$backup_file"
                echo -e "${GREEN}已备份当前规则到: $backup_file${NC}"
                exit 0
                ;;
            -d|--debug)
                DEBUG_MODE=1
                ;;
            -r|--restart)
                RESTART_MODE=1
                ;;
            -u|--update)
                UPDATE_MODE=1
                ;;
            -U|--uninstall)
                uninstall_gateway
                exit 0
                ;;
            --ipv6)
                IPV6_ENABLED=1
                ;;
            --stats)
                init_config_system
                show_traffic_stats
                exit 0
                ;;
            --test)
                init_config_system
                test_gateway
                exit $?
                ;;
            -g|--gfwlist)
                GFWLIST_MODE=1
                ;;
            -G|--update-gfwlist)
                init_config_system
                update_gfwlist
                exit 0
                ;;
            -S|--gfwlist-status)
                init_config_system
                check_gfwlist_status
                exit 0
                ;;
            --test-gfw)
                init_config_system
                load_config
                if [ "$GFWLIST_MODE" != "1" ]; then
                    log "WARN" "GFW List 模式未启用，先启用再测试"
                    GFWLIST_MODE=1
                    init_gfwlist_mode
                fi
                test_gfwlist
                exit $?
                ;;
            --show-dns-log)
                init_config_system
                show_dns_log
                exit 0
                ;;
            --dns-log-count)
                init_config_system
                show_dns_log "$2"
                shift
                exit 0
                ;;
            --dns-log-domain)
                init_config_system
                show_dns_log_by_domain "$2"
                shift
                exit 0
                ;;
            --dns-log-status)
                init_config_system
                show_dns_log_by_status "$2"
                shift
                exit 0
                ;;
            --reset-dns-log)
                init_config_system
                reset_dns_log
                exit 0
                ;;
            --list-domains)
                init_config_system
                list_custom_domains
                exit 0
                ;;
            --add-domain)
                init_config_system
                add_custom_domain "$2"
                shift
                exit 0
                ;;
            --remove-domain)
                init_config_system
                remove_custom_domain "$2"
                shift
                exit 0
                ;;
            --test-domain)
                init_config_system
                test_domain_resolution "$2"
                shift
                exit 0
                ;;
            --test-squid)
                init_config_system
                test_squid_proxy
                exit 0
                ;;
            --no-dns-log)
                DNS_LOGGING=0
                ;;
            --config-status)
                init_config_system
                show_config_management_status
                exit 0
                ;;
            --sync-configs)
                init_config_system
                sync_all_configs
                exit $?
                ;;
            --backup-configs)
                init_config_system
                backup_configs
                exit 0
                ;;
            *)
                log "ERROR" "未知参数: $1"
                echo -e "${YELLOW}使用 --help 查看帮助信息${NC}"
                exit 1
                ;;
        esac
        shift
    done
}

# 验证参数
validate_arguments() {
    log "DEBUG" "验证命令行参数..."

    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        handle_error "请使用 root 权限运行此脚本"
    fi

    # 检查ZeroTier是否安装
    if ! command -v zerotier-cli &> /dev/null; then
        handle_error "ZeroTier 未安装，请先安装 ZeroTier 客户端"
    fi

    # 检查ZeroTier服务状态
    if ! systemctl is-active --quiet zerotier-one; then
        log "WARN" "ZeroTier 服务未运行，尝试启动..."
        systemctl start zerotier-one || handle_error "无法启动 ZeroTier 服务"
    fi

    log "DEBUG" "参数验证完成"
}

# 加载配置文件
load_config() {
    local config_file=$(get_config_path "main")

    if [ -f "$config_file" ]; then
        log "INFO" "加载配置文件: $config_file"
        source "$config_file"

        # 验证配置完整性
        if [ -z "$ZT_INTERFACE" ] || [ -z "$WAN_INTERFACE" ]; then
            log "WARN" "配置文件中缺少网络接口信息，将重新检测"
        fi
    else
        log "INFO" "配置文件不存在，将创建新配置"
    fi
}

# 保存配置文件
save_config() {
    local config_content=""

    config_content+="# ZeroTier 网关配置文件"$'\n'
    config_content+="# 自动生成于: $(date)"$'\n'
    config_content+=""$'\n'
    config_content+="# 网络接口配置"$'\n'
    config_content+="ZT_INTERFACE=\"$ZT_INTERFACE\""$'\n'
    config_content+="WAN_INTERFACE=\"$WAN_INTERFACE\""$'\n'
    config_content+="ZT_MTU=\"$ZT_MTU\""$'\n'
    config_content+=""$'\n'
    config_content+="# 功能开关"$'\n'
    config_content+="IPV6_ENABLED=\"$IPV6_ENABLED\""$'\n'
    config_content+="GFWLIST_MODE=\"$GFWLIST_MODE\""$'\n'
    config_content+="DNS_LOGGING=\"$DNS_LOGGING\""$'\n'
    config_content+="DEBUG_MODE=\"$DEBUG_MODE\""$'\n'
    config_content+=""$'\n'
    config_content+="# 网络信息"$'\n'
    config_content+="ZT_NETWORK=\"$ZT_NETWORK\""$'\n'
    config_content+="WAN_IP=\"$WAN_IP\""$'\n'
    config_content+=""$'\n'
    config_content+="# 配置状态"$'\n'
    config_content+="CONFIG_VERSION=\"3.0\""$'\n'
    config_content+="INSTALL_DATE=\"$(date '+%Y-%m-%d %H:%M:%S')\""$'\n'

    create_config_file "main" "$config_content" "主配置文件"
    log "INFO" "配置已保存"
}

# 显示配置管理状态
show_config_management_status() {
    echo -e "${GREEN}===== 配置文件管理状态 =====${NC}"
    echo ""

    for config_key in "${!CONFIG_PATHS[@]}"; do
        local status=$(check_config_status "$config_key")
        local status_color="$GREEN"

        case "$status" in
            *"不存在"*) status_color="$RED" ;;
            *"错误"*) status_color="$RED" ;;
            *"复制文件"*) status_color="$YELLOW" ;;
        esac

        echo -e "${BLUE}$config_key${NC}: ${status_color}$status${NC}"
    done

    echo ""
    echo -e "${YELLOW}配置目录:${NC}"
    echo -e "  项目配置: $SCRIPT_CONFIG_DIR"
    echo -e "  系统配置: $SYSTEM_CONFIG_DIR"
}
