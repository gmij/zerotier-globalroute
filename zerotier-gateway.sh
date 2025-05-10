#!/bin/bash
#
# ZeroTier 高级网关配置脚本 - CentOS 终极版
# 功能：配置 CentOS 服务器作为 ZeroTier 网络的网关，支持双向流量及 HTTPS
# 版本：3.0 (Final)
#

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 加载功能模块
source "$SCRIPT_DIR/cmd/utils.sh"
source "$SCRIPT_DIR/cmd/detect.sh"
source "$SCRIPT_DIR/cmd/monitor.sh"
source "$SCRIPT_DIR/cmd/uninstall.sh"
source "$SCRIPT_DIR/cmd/firewall.sh"
source "$SCRIPT_DIR/cmd/gfwlist.sh"

# 默认参数
ZT_INTERFACE=""
WAN_INTERFACE=""
ZT_MTU=1400
DEBUG_MODE=0
IPV6_ENABLED=0
GFWLIST_MODE=0

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -z|--zt-if) ZT_INTERFACE="$2"; shift ;;
        -w|--wan-if) WAN_INTERFACE="$2"; shift ;;
        -m|--mtu) ZT_MTU="$2"; shift ;;
        -s|--status) 
            # 准备目录
            prepare_dirs
            # 加载配置
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            fi
            show_status
            exit 0 
            ;;
        -b|--backup) 
            backup_file="/root/iptables-backup-$(date +%Y%m%d-%H%M%S).rules"
            iptables-save > "$backup_file" 
            echo -e "${GREEN}已备份当前规则到: $backup_file${NC}"
            exit 0 
            ;;
        -d|--debug) DEBUG_MODE=1 ;;
        -r|--restart) RESTART_MODE=1 ;;
        -u|--update) UPDATE_MODE=1 ;;        -U|--uninstall) 
            uninstall_gateway
            exit 0
            ;;
        --ipv6) IPV6_ENABLED=1 ;;
        --stats) 
            prepare_dirs
            show_traffic_stats
            exit 0
            ;;
        --test) 
            prepare_dirs
            test_gateway
            exit $?
            ;;
        -g|--gfwlist) 
            GFWLIST_MODE=1 
            ;;
        -G|--update-gfwlist)
            prepare_dirs
            update_gfwlist
            exit 0
            ;;
        -S|--gfwlist-status)
            prepare_dirs
            check_gfwlist_status
            exit 0
            ;;        --test-gfw)
            prepare_dirs
            # 检查是否已安装GFW List模式
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                if [ "$GFWLIST_MODE" != "1" ]; then
                    log "WARN" "GFW List 模式未启用，先启用再测试"
                    GFWLIST_MODE=1
                    # 初始化GFW List模式
                    init_gfwlist_mode
                fi
            else
                log "WARN" "找不到配置文件，初始化GFW List模式"
                GFWLIST_MODE=1
                # 初始化GFW List模式
                init_gfwlist_mode
            fi
            # 运行测试
            test_gfwlist
            exit $?
            ;;
        --list-domains)
            prepare_dirs
            # 确认GFW List模式已启用
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            fi
            if [ "$GFWLIST_MODE" != "1" ]; then
                log "WARN" "GFW List 模式未启用，无法查看自定义域名列表"
                exit 1
            fi
            list_custom_domains
            exit 0
            ;;
        --add-domain)
            if [ -z "$2" ]; then
                handle_error "请指定要添加的域名，例如: --add-domain example.com"
            fi
            domain="$2"
            prepare_dirs
            # 确认GFW List模式已启用
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            fi
            if [ "$GFWLIST_MODE" != "1" ]; then
                log "WARN" "GFW List 模式未启用，先启用再添加"
                GFWLIST_MODE=1
                init_gfwlist_mode
            fi
            add_custom_domain "$domain"
            shift  # 额外移动一次，跳过域名参数
            exit 0
            ;;
        --remove-domain)
            if [ -z "$2" ]; then
                handle_error "请指定要删除的域名，例如: --remove-domain example.com"
            fi
            domain="$2"
            prepare_dirs
            # 确认GFW List模式已启用
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            fi
            if [ "$GFWLIST_MODE" != "1" ]; then
                log "WARN" "GFW List 模式未启用，无法删除域名"
                exit 1
            fi
            remove_custom_domain "$domain"
            shift  # 额外移动一次，跳过域名参数
            exit 0
            ;;        --test-domain)
            if [ -z "$2" ]; then
                handle_error "请指定要测试的域名，例如: --test-domain example.com"
            fi
            domain="$2"
            prepare_dirs
            # 确认GFW List模式已启用
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            fi
            if [ "$GFWLIST_MODE" != "1" ]; then
                log "WARN" "GFW List 模式未启用，无法测试域名"
                exit 1
            fi
            test_custom_domain "$domain"
            shift  # 额外移动一次，跳过域名参数
            exit 0
            ;;
        --test-squid)
            prepare_dirs
            # 这个功能不需要 GFW List 模式启用也能测试
            test_squid_proxy
            exit 0
            ;;
        *) handle_error "未知参数: $1" ;;
    esac
    shift
done

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    handle_error "请使用 root 权限运行此脚本"
fi

# 准备目录
prepare_dirs

# 重启模式 - 重新应用现有配置
if [ "$RESTART_MODE" = "1" ]; then
    log "INFO" "重启模式：重新应用现有配置"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        if [ -z "$ZT_INTERFACE" ] || [ -z "$WAN_INTERFACE" ]; then
            handle_error "配置文件中找不到必要的接口信息"
        fi
    else
        handle_error "找不到配置文件，无法重启"
    fi
fi

# 更新模式 - 保留接口设置
if [ "$UPDATE_MODE" = "1" ] && [ -f "$CONFIG_FILE" ]; then
    log "INFO" "更新模式：保留现有接口设置"
    source "$CONFIG_FILE"
    if [ -z "$ZT_INTERFACE" ]; then ZT_INTERFACE=""; fi
    if [ -z "$WAN_INTERFACE" ]; then WAN_INTERFACE=""; fi
fi

# 确保 iptables-services 已安装
if ! rpm -q iptables-services &>/dev/null; then
    log "INFO" "安装 iptables-services..."
    yum install -y iptables-services || handle_error "安装 iptables-services 失败"
fi

# 自动检测接口
if [ -z "$ZT_INTERFACE" ]; then
    log "INFO" "正在自动检测 ZeroTier 网络接口..."
    ZT_INTERFACE=$(detect_zt_interface)
    
    # 如果发现多个 ZT 接口，要求用户选择
    if [ "$ZT_INTERFACE" = "multiple" ]; then
        log "INFO" "检测到多个 ZeroTier 接口"
        echo -e "${YELLOW}检测到多个 ZeroTier 接口:${NC}"
        for i in "${!ZT_MULTIPLE_INTERFACES[@]}"; do
            local zt_ip=$(ip -o -f inet addr show ${ZT_MULTIPLE_INTERFACES[$i]} 2>/dev/null | awk '{print $4}')
            echo "  $((i+1)). ${ZT_MULTIPLE_INTERFACES[$i]} - IP: ${zt_ip:-未分配}"
        done
        echo ""
        read -p "请选择要使用的接口编号 (1-${#ZT_MULTIPLE_INTERFACES[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#ZT_MULTIPLE_INTERFACES[@]}"]; then
            ZT_INTERFACE="${ZT_MULTIPLE_INTERFACES[$((choice-1))]}"
            log "INFO" "用户选择了接口: $ZT_INTERFACE"
        else
            handle_error "无效选择"
        fi
    elif [ -z "$ZT_INTERFACE" ]; then
        handle_error "未检测到任何 ZeroTier 网络接口。请确保 ZeroTier 已安装并连接到网络。"
    else
        log "INFO" "已检测到 ZeroTier 接口: $ZT_INTERFACE"
    fi
fi

if [ -z "$WAN_INTERFACE" ]; then
    log "INFO" "正在自动检测外网接口..."
    WAN_INTERFACE=$(detect_wan_interface)
    log "INFO" "已检测到外网接口: $WAN_INTERFACE"
fi

# 检查接口是否存在
ip link show $ZT_INTERFACE >/dev/null 2>&1 || handle_error "ZeroTier 接口 $ZT_INTERFACE 不存在"
ip link show $WAN_INTERFACE >/dev/null 2>&1 || handle_error "外网接口 $WAN_INTERFACE 不存在"

# 获取 ZeroTier 网络的 CIDR
ZT_NETWORK=$(ip -o -f inet addr show $ZT_INTERFACE 2>/dev/null | awk '{print $4}')
if [ -z "$ZT_NETWORK" ]; then
    handle_error "无法获取 $ZT_INTERFACE 的 IP 地址。请确保 ZeroTier 已连接并分配了 IP。"
fi
log "INFO" "ZeroTier 网络: $ZT_NETWORK"

# 获取 ZeroTier 网络 ID (如果可能的话)
ZT_NETWORK_ID=""
if command -v zerotier-cli >/dev/null 2>&1; then
    ZT_NETWORK_ID=$(zerotier-cli listnetworks | grep -v NETWORK | awk '{print $3}' | head -1)
    if [ -n "$ZT_NETWORK_ID" ]; then
        log "INFO" "ZeroTier 网络 ID: $ZT_NETWORK_ID"
    fi
fi

# 保存配置到文件
cat > "$CONFIG_FILE" << EOL
# ZeroTier Gateway Configuration - $(date)
# 由脚本自动生成，请勿手动编辑

# 接口配置
ZT_INTERFACE="$ZT_INTERFACE"
WAN_INTERFACE="$WAN_INTERFACE"
ZT_MTU="$ZT_MTU"
ZT_NETWORK="$ZT_NETWORK"
ZT_NETWORK_ID="$ZT_NETWORK_ID"

# 功能设置
IPV6_ENABLED="$IPV6_ENABLED"
GFWLIST_MODE="$GFWLIST_MODE"

# 脚本版本
SCRIPT_VERSION="3.0"

# 最后更新时间
LAST_UPDATE="$(date)"
EOL

# 保存ZeroTier网卡信息到CentOS配置
log "INFO" "保存接口配置以在重启后使用..."
cat > /etc/sysconfig/zt-gateway-config << EOL
# ZeroTier Gateway Configuration - 由脚本自动生成
ZT_INTERFACE="$ZT_INTERFACE"
WAN_INTERFACE="$WAN_INTERFACE"
ZT_MTU="$ZT_MTU"
ZT_NETWORK="$ZT_NETWORK"
EOL

# 优化性能的内核参数
log "INFO" "配置内核参数..."

# 使用模板生成 sysctl 配置
SYSCTL_TEMPLATE="$SCRIPT_DIR/templates/sysctl.conf.template"
if [ -f "$SYSCTL_TEMPLATE" ];then
    # 读取模板文件
    SYSCTL_CONFIG=$(cat "$SYSCTL_TEMPLATE")
    
    # 添加 IPv6 设置（如果启用）
    if [ "$IPV6_ENABLED" = "1" ]; then
        IPV6_SETTINGS=$(cat << 'EOF'

# IPv6 转发
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF
)
        # 替换占位符
        SYSCTL_CONFIG="${SYSCTL_CONFIG//#IPV6_SETTINGS#/$IPV6_SETTINGS}"
    else
        # 移除占位符
        SYSCTL_CONFIG="${SYSCTL_CONFIG//#IPV6_SETTINGS#/}"
    fi
    
    # 写入配置文件
    echo "$SYSCTL_CONFIG" > /etc/sysctl.d/99-zt-gateway.conf
else
    handle_error "找不到 sysctl 配置模板文件: $SYSCTL_TEMPLATE"
fi

# 应用 sysctl 配置
sysctl -p /etc/sysctl.d/99-zt-gateway.conf || handle_error "应用内核参数失败"

# 调整 ZeroTier 接口的 MTU
log "INFO" "调整 $ZT_INTERFACE MTU 为 $ZT_MTU..."
ip link set $ZT_INTERFACE mtu $ZT_MTU || handle_error "调整 MTU 失败"

# 如果启用了 GFW List 模式，初始化相关设置
if [ "$GFWLIST_MODE" = "1" ]; then
    log "INFO" "启用 GFW List 分流模式..."
    init_gfwlist_mode
fi

# 如果启用了 GFW List 模式，安装 ipset 初始化服务
if [ "$GFWLIST_MODE" = "1" ]; then
    log "INFO" "创建 ipset 初始化脚本和服务..."
    
    # 创建 ipset 初始化脚本
    IPSET_INIT_TEMPLATE="$SCRIPT_DIR/templates/ipset-init.sh.template"
    if [ -f "$IPSET_INIT_TEMPLATE" ]; then
        cat "$IPSET_INIT_TEMPLATE" > /usr/local/bin/ipset-init.sh
        chmod +x /usr/local/bin/ipset-init.sh
    else
        handle_error "找不到 ipset 初始化脚本模板: $IPSET_INIT_TEMPLATE"
    fi
    
    # 创建 systemd 服务单元
    IPSET_SERVICE_TEMPLATE="$SCRIPT_DIR/templates/ztgw-ipset.service.template"
    if [ -f "$IPSET_SERVICE_TEMPLATE" ]; then
        cat "$IPSET_SERVICE_TEMPLATE" > /etc/systemd/system/ztgw-ipset.service
        systemctl daemon-reload
        systemctl enable ztgw-ipset.service
        log "INFO" "已启用 ipset 初始化服务"
    else
        handle_error "找不到 ipset 服务模板: $IPSET_SERVICE_TEMPLATE"
    fi
    
    # 立即运行初始化脚本
    /usr/local/bin/ipset-init.sh
fi

# 配置防火墙规则
setup_firewall "$ZT_INTERFACE" "$WAN_INTERFACE" "$ZT_NETWORK" "$IPV6_ENABLED" "$GFWLIST_MODE"

# 创建 MTU 设置脚本，重启后执行
log "INFO" "配置网络接口监控脚本..."
NETWORK_MONITOR_TEMPLATE="$SCRIPT_DIR/templates/network-monitor.sh.template"
if [ -f "$NETWORK_MONITOR_TEMPLATE" ]; then
    cat "$NETWORK_MONITOR_TEMPLATE" > /etc/NetworkManager/dispatcher.d/99-ztmtu.sh
else
    handle_error "找不到网络监控脚本模板: $NETWORK_MONITOR_TEMPLATE"
fi
chmod +x /etc/NetworkManager/dispatcher.d/99-ztmtu.sh

# 启用并重启 iptables 服务
restart_firewall_service

# 配置时间同步
if ! rpm -q chrony &>/dev/null; then
    log "INFO" "安装和配置 chrony 时间同步..."
    yum install -y chrony || handle_error "安装 chrony 失败"
    systemctl enable chronyd
    systemctl start chronyd
    chronyc makestep
fi

# 创建一个增强的监控脚本
log "INFO" "创建状态监控脚本..."
STATUS_SCRIPT_TEMPLATE="$SCRIPT_DIR/templates/status-script.sh.template"
if [ -f "$STATUS_SCRIPT_TEMPLATE" ]; then
    cat "$STATUS_SCRIPT_TEMPLATE" > /usr/local/bin/zt-status
else
    handle_error "找不到状态脚本模板文件: $STATUS_SCRIPT_TEMPLATE"
fi
chmod +x /usr/local/bin/zt-status

# 创建定时检查脚本
log "INFO" "创建定时检查脚本..."
DAILY_CHECK_TEMPLATE="$SCRIPT_DIR/templates/daily-check.sh.template"
if [ -f "$DAILY_CHECK_TEMPLATE" ]; then
    cat "$DAILY_CHECK_TEMPLATE" > /etc/cron.daily/zt-gateway-check
else
    handle_error "找不到定时检查脚本模板文件: $DAILY_CHECK_TEMPLATE"
fi
chmod +x /etc/cron.daily/zt-gateway-check

# 测试网关连通性
log "INFO" "测试网关连通性..."
if ping -c 1 -W 3 -I "$ZT_INTERFACE" 8.8.8.8 >/dev/null 2>&1; then
    log "INFO" "网关连通性测试成功"
else
    log "WARN" "网关连通性测试失败，但配置已完成。请检查网络设置。"
fi

# 完成
log "INFO" "ZeroTier 网关配置完成"
echo -e "${GREEN}ZeroTier 网关配置完成！${NC}"
echo -e "${GREEN}已配置的接口: ZT=$ZT_INTERFACE, WAN=$WAN_INTERFACE${NC}"
echo -e "${GREEN}ZeroTier 网络: $ZT_NETWORK${NC}"

if [ "$GFWLIST_MODE" = "1" ]; then
    echo -e "${YELLOW}GFW List 分流模式已启用！${NC}"
    echo -e "${YELLOW}仅 GFW List 中的网站会通过 ZeroTier 全局路由，其他网站走正常线路。${NC}"
    echo -e "${YELLOW}您可以使用 --update-gfwlist 参数更新 GFW List，使用 --gfwlist-status 查看状态。${NC}"
else
    echo -e "${GREEN}您现在可以通过 ZeroTier 网络访问互联网，并且外部流量可以通过此服务器访问 ZeroTier 网络。${NC}"
fi

echo -e "${YELLOW}配置已通过 iptables-services 设置为开机自启动${NC}"
echo -e "${YELLOW}如需查看状态，请运行: /usr/local/bin/zt-status${NC}"