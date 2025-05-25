#!/bin/bash
#
# ZeroTier 网关 DNS 日志处理模块 (基于 dnsmasq 日志)
#

# DNS日志文件路径
DNS_LOG_FILE="${SCRIPT_DIR}/logs/zt-dns-queries.log"
DNSMASQ_LOG_FILE="${SCRIPT_DIR}/logs/dnsmasq.log"
DNS_LOG_MAX_SIZE=10485760 # 10MB
DNS_LOG_MAX_DAYS=7 # 保留7天日志

# 初始化DNS日志功能
init_dns_logging() {
    log "INFO" "初始化基于dnsmasq的DNS日志功能..."
    
    # 确保logs目录存在
    mkdir -p "${SCRIPT_DIR}/logs"
    
    # 创建空日志文件（如果不存在）
    if [ ! -f "$DNS_LOG_FILE" ]; then
        touch "$DNS_LOG_FILE"
        chmod 644 "$DNS_LOG_FILE"
    fi
    
    # 创建dnsmasq日志文件（如果不存在）
    if [ ! -f "$DNSMASQ_LOG_FILE" ]; then
        touch "$DNSMASQ_LOG_FILE"
        chmod 644 "$DNSMASQ_LOG_FILE"
    fi
    
    # 添加自动轮转日志的cron任务
    if ! crontab -l | grep -q "zt-dns-queries"; then
        # 每天轮转日志文件并删除旧日志
        (crontab -l 2>/dev/null; echo "0 0 * * * if [ -f \"${SCRIPT_DIR}/logs/zt-dns-queries.log\" ] && [ \$(stat -c%s \"${SCRIPT_DIR}/logs/zt-dns-queries.log\") -gt 1048576 ]; then mv \"${SCRIPT_DIR}/logs/zt-dns-queries.log\" \"${SCRIPT_DIR}/logs/zt-dns-queries.log.\$(date +\\%Y\\%m\\%d)\"; fi") | crontab -
        (crontab -l 2>/dev/null; echo "0 0 * * * if [ -f \"${SCRIPT_DIR}/logs/dnsmasq.log\" ] && [ \$(stat -c%s \"${SCRIPT_DIR}/logs/dnsmasq.log\") -gt 1048576 ]; then mv \"${SCRIPT_DIR}/logs/dnsmasq.log\" \"${SCRIPT_DIR}/logs/dnsmasq.log.\$(date +\\%Y\\%m\\%d)\"; fi") | crontab -
        (crontab -l 2>/dev/null; echo "10 0 * * * /bin/find ${SCRIPT_DIR}/logs/ -name 'zt-dns-queries.log.*' -mtime +$DNS_LOG_MAX_DAYS -delete") | crontab -
        (crontab -l 2>/dev/null; echo "10 0 * * * /bin/find ${SCRIPT_DIR}/logs/ -name 'dnsmasq.log.*' -mtime +$DNS_LOG_MAX_DAYS -delete") | crontab -
        log "INFO" "已设置每日日志轮转和清理任务"
    fi
    
    # 创建一个脚本来处理dnsmasq日志并转换到我们的格式
    local dns_processor_script="/usr/local/bin/zt-dns-processor.sh"
    cat > "$dns_processor_script" << 'EOF'
#!/bin/bash

DNSMASQ_LOG="$1"
DNS_LOG_FILE="$2"
SCRIPT_DIR="$3"

if [ -z "$DNSMASQ_LOG" ] || [ -z "$DNS_LOG_FILE" ] || [ -z "$SCRIPT_DIR" ]; then
    echo "用法: $0 <dnsmasq日志文件> <输出日志文件> <脚本目录>"
    exit 1
fi

# 记录启动信息到syslog
echo "ZT DNS Processor 已启动，监控日志: $DNSMASQ_LOG -> $DNS_LOG_FILE" | logger -t zt-dns-processor

# 检测环境并确保logs目录存在
mkdir -p "$SCRIPT_DIR/logs"
touch "$DNS_LOG_FILE"

# 确保检查dnsmasq进程和日志是否存在
check_and_restart_dnsmasq() {
    if ! systemctl is-active --quiet dnsmasq; then
        echo "dnsmasq服务未运行，正在尝试重启..." | logger -t zt-dns-processor
        systemctl restart dnsmasq
        sleep 2
    fi
    
    # 如果日志文件不存在，创建它
    if [ ! -f "$DNSMASQ_LOG" ]; then
        echo "dnsmasq日志文件不存在，创建新的日志文件" | logger -t zt-dns-processor
        touch "$DNSMASQ_LOG"
        chmod 644 "$DNSMASQ_LOG"
        
        # 如果还需要配置dnsmasq启用日志
        if ! grep -q "log-queries" /etc/dnsmasq.d/zt-gfwlist.conf; then
            echo "添加dnsmasq日志配置..." | logger -t zt-dns-processor
            echo "log-queries=extra" >> /etc/dnsmasq.d/zt-gfwlist.conf
            echo "log-facility=$DNSMASQ_LOG" >> /etc/dnsmasq.d/zt-gfwlist.conf
            echo "log-async=50" >> /etc/dnsmasq.d/zt-gfwlist.conf
            systemctl restart dnsmasq
        fi
    fi
}

# 启动前检查dnsmasq状态
check_and_restart_dnsmasq

# 使用tail -F监控dnsmasq日志文件 (-F会在文件被轮转后重新打开)
tail -F "$DNSMASQ_LOG" 2>/dev/null | while read -r line; do
    # 过滤只处理DNS查询记录 (考虑各种可能的日志格式)
    if echo "$line" | grep -q "query\|forwarded\|cached\|reply"; then
        # 提取时间戳 (支持多种dnsmasq日志格式)
        # 尝试从行开始提取标准时间戳 (May 11 12:34:56)
        if [[ "$line" =~ ^[A-Z][a-z]{2}\ +[0-9]+\ +[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
            timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            formatted_time=$(date -d "$(date +%Y) $timestamp" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
        # 尝试从行开始提取带年份的时间戳 (2023-05-11 12:34:56)
        elif [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ +[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
            formatted_time=$(echo "$line" | awk '{print $1, $2}')
        # 如果都失败，使用当前时间
        else
            formatted_time=$(date +"%Y-%m-%d %H:%M:%S")
        fi
        
        # 提取DNS查询信息 - 支持多种dnsmasq日志格式
        domain=""
        query_type=""
        source_ip=""
        
        # 尝试匹配不同的查询日志格式
        if [[ "$line" =~ query\[[A-Z]* ]]; then
            # 标准查询格式: "query[A] example.com from 192.168.1.100"
            domain=$(echo "$line" | sed -n 's/.*query\[[A-Z]*\] \([^ ]*\).*/\1/p' | sed 's/\.$//')
            query_type=$(echo "$line" | sed -n 's/.*query\[\([A-Z]*\)\].*/\1/p')
            source_ip=$(echo "$line" | grep -o -E 'from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | cut -d' ' -f2)
        elif [[ "$line" =~ "query:" ]]; then
            # 替代格式: "query: example.com IN A from 192.168.1.100"
            domain=$(echo "$line" | awk '{print $2}' | sed 's/\.$//')
            query_type=$(echo "$line" | awk '{print $4}')
            source_ip=$(echo "$line" | grep -o -E 'from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
        elif [[ "$line" =~ "forwarded" ]]; then
            # 转发记录: "forwarded example.com to 8.8.8.8"
            domain=$(echo "$line" | awk '{print $2}' | sed 's/\.$//')
            query_type="解析"  # 无法确定具体类型
            source_ip="unknown"  # 转发记录通常无源IP
        fi
        
        # 调试日志
        if [ -n "$domain" ] && [ "$domain" != "" ]; then
            echo "解析到DNS查询: $domain ($query_type) 来自 $source_ip" | logger -t zt-dns-processor
            
            # 确定该域名是否需要转发
            forwarded=0
            forwarded_text="未转发"
            
            # 检查是否是自定义域名列表中的域名
            if [ -f "$SCRIPT_DIR/config/custom_domains.txt" ] && grep -q "^$domain$" "$SCRIPT_DIR/config/custom_domains.txt" 2>/dev/null; then
                forwarded=1
                forwarded_text="已转发(自定义域名)"
            # 然后检查是否在GFW列表中
            elif [ -f "$SCRIPT_DIR/config/gfwlist_domains.txt" ] && grep -q "^$domain$" "$SCRIPT_DIR/config/gfwlist_domains.txt" 2>/dev/null; then
                forwarded=1
                forwarded_text="已转发(GFW列表)"
            # 检查域名是否是通配符匹配
            elif [ -f "$SCRIPT_DIR/config/custom_domains.txt" ]; then
                # 提取根域名和父域名
                root_domain=$(echo "$domain" | awk -F. '{if (NF>1) {print $(NF-1)"."$NF} else {print $NF}}')
                parent_domain=$(echo "$domain" | sed -E 's/^[^.]*\.//' 2>/dev/null)
                
                # 检查通配符匹配
                if [ -n "$root_domain" ] && grep -q "\*\.$root_domain" "$SCRIPT_DIR/config/custom_domains.txt" 2>/dev/null; then
                    forwarded=1
                    forwarded_text="已转发(通配符匹配)"
                elif [ -n "$parent_domain" ] && grep -q "\*\.$parent_domain" "$SCRIPT_DIR/config/custom_domains.txt" 2>/dev/null; then
                    forwarded=1
                    forwarded_text="已转发(通配符匹配)"
                fi
            # 最后检查通过IP判断
            elif command -v ipset &>/dev/null && ipset list gfwlist &>/dev/null 2>/dev/null; then
                # 尝试解析域名获取IP
                ip=$(dig +short "$domain" 2>/dev/null | head -1)
                if [ -n "$ip" ] && ipset test gfwlist "$ip" 2>/dev/null; then
                    forwarded=1
                    forwarded_text="已转发(IP匹配)"
                fi
            fi
            
            # 记录查询
            if [ -n "$source_ip" ] && [ "$source_ip" != "unknown" ]; then
                echo "[$formatted_time] $source_ip $domain $query_type $forwarded_text" >> "$DNS_LOG_FILE"
            else
                echo "[$formatted_time] - $domain $query_type $forwarded_text" >> "$DNS_LOG_FILE"
            fi
        fi
    fi
done
EOF

    chmod +x "$dns_processor_script"
    
    # 创建systemd服务
    local service_file="/etc/systemd/system/zt-dns-processor.service"
    cat > "$service_file" << EOF
[Unit]
Description=ZeroTier DNS查询日志处理服务
After=network.target zerotier-one.service dnsmasq.service

[Service]
Type=simple
ExecStart=/usr/local/bin/zt-dns-processor.sh $DNSMASQ_LOG_FILE $DNS_LOG_FILE $SCRIPT_DIR
Restart=always
RestartSec=5
Nice=10
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
MemoryLimit=50M
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 检查dnsmasq日志配置
    if ! grep -q "log-queries" /etc/dnsmasq.d/zt-gfwlist.conf 2>/dev/null; then
        log "INFO" "添加dnsmasq日志配置..."
        echo "log-queries=extra" >> /etc/dnsmasq.d/zt-gfwlist.conf
        echo "log-facility=$DNSMASQ_LOG_FILE" >> /etc/dnsmasq.d/zt-gfwlist.conf
        echo "log-async=50" >> /etc/dnsmasq.d/zt-gfwlist.conf
    fi
    
    # 确保日志目录权限正确
    chown -R dnsmasq:dnsmasq "${SCRIPT_DIR}/logs" 2>/dev/null || {
        log "INFO" "尝试使用sudo设置日志目录权限"
        sudo chown -R dnsmasq:dnsmasq "${SCRIPT_DIR}/logs" 2>/dev/null || {
            log "INFO" "无法设置日志目录权限，尝试设置为所有用户可写"
            chmod 777 "${SCRIPT_DIR}/logs"
        }
    }
    
    # 确保dnsmasq使用我们的配置
    log "INFO" "重启dnsmasq服务..."
    systemctl restart dnsmasq
    
    # 启用并启动日志处理服务
    log "INFO" "启动DNS日志处理服务..."
    systemctl daemon-reload
    systemctl enable zt-dns-processor
    systemctl restart zt-dns-processor
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet zt-dns-processor; then
        log "INFO" "DNS日志处理服务已成功启动"
    else
        log "WARN" "DNS日志处理服务启动失败，尝试排查问题..."
        log "INFO" "请检查日志: journalctl -u zt-dns-processor"
    fi
    
    # 停止并禁用旧的DNS日志服务（如果存在）
    if systemctl is-active --quiet zt-dns-logger; then
        log "INFO" "停用旧的DNS日志服务..."
        systemctl stop zt-dns-logger
        systemctl disable zt-dns-logger
    fi
    
    # 添加一条示例记录到日志文件，确认一切正常
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 系统 example.com A 测试记录" >> "$DNS_LOG_FILE"
    
    log "INFO" "基于dnsmasq的DNS日志功能已初始化"
    return 0
}

# 显示DNS日志
show_dns_logs() {
    local count=${1:-50}
    local domain_filter=$2
    local forward_filter=$3
    
    echo -e "${GREEN}===== ZeroTier 网关 DNS 查询日志 =====${NC}"
    
    if [ ! -f "$DNS_LOG_FILE" ]; then
        echo -e "${YELLOW}未找到DNS日志文件，请确保DNS日志功能已启用${NC}"
        return 1
    fi
    
    # 检查是否需要重启日志服务
    if ! systemctl is-active --quiet zt-dns-processor; then
        echo -e "${YELLOW}DNS日志处理服务未运行，尝试重启服务...${NC}"
        systemctl restart zt-dns-processor
        
        # 检查dnsmasq服务状态
        if ! systemctl is-active --quiet dnsmasq; then
            echo -e "${RED}dnsmasq服务未运行，这可能导致DNS日志无法正常工作${NC}"
            echo -e "${YELLOW}正在尝试启动dnsmasq服务...${NC}"
            systemctl restart dnsmasq
        fi
        
        # 如果没有看到"已转发"的记录，提示用户可能需要重启服务
        if ! grep -q "已转发" "$DNS_LOG_FILE"; then
            echo -e "${YELLOW}提示: 如果您看不到\"已转发\"的记录，可能需要重启网关服务。${NC}"
            echo -e "${YELLOW}请运行: ./zerotier-gateway.sh --restart${NC}"
        fi
    fi
    
    echo -e "${YELLOW}最近 $count 条DNS查询:${NC}"
    
    if [ -n "$domain_filter" ] && [ -n "$forward_filter" ]; then
        grep "$domain_filter" "$DNS_LOG_FILE" | grep "$forward_filter" | tail -n "$count"
    elif [ -n "$domain_filter" ]; then
        grep "$domain_filter" "$DNS_LOG_FILE" | tail -n "$count"
    elif [ -n "$forward_filter" ]; then
        grep "$forward_filter" "$DNS_LOG_FILE" | tail -n "$count"
    else
        tail -n "$count" "$DNS_LOG_FILE"
    fi
    
    echo ""
    echo -e "${YELLOW}查询统计:${NC}"
    
    total_queries=$(wc -l < "$DNS_LOG_FILE")
    forwarded_queries=$(grep "已转发" "$DNS_LOG_FILE" | wc -l)
    not_forwarded=$(grep "未转发" "$DNS_LOG_FILE" | wc -l)
    
    echo "总查询次数: $total_queries"
    
    # 避免除以零的错误
    if [ "$total_queries" -gt 0 ]; then
        forwarded_percent=$(awk -v f=$forwarded_queries -v t=$total_queries 'BEGIN{printf "%.1f%%", f/t*100}')
        not_forwarded_percent=$(awk -v n=$not_forwarded -v t=$total_queries 'BEGIN{printf "%.1f%%", n/t*100}')
        echo "已转发查询: $forwarded_queries ($forwarded_percent)"
        echo "未转发查询: $not_forwarded ($not_forwarded_percent)"
    else
        echo "已转发查询: $forwarded_queries (0.0%)"
        echo "未转发查询: $not_forwarded (0.0%)"
    fi
    
    # 显示转发类型统计
    echo -e "\n${YELLOW}转发类型统计:${NC}"
    grep "已转发" "$DNS_LOG_FILE" | grep -o "(.*)" | sort | uniq -c | sort -rn
    
    # 显示TOP10域名
    echo -e "\n${YELLOW}TOP 10 查询域名:${NC}"
    awk '{print $3}' "$DNS_LOG_FILE" | sort | uniq -c | sort -rn | head -10
    
    # 显示TOP10已转发域名
    echo -e "\n${YELLOW}TOP 10 已转发域名:${NC}"
    grep "已转发" "$DNS_LOG_FILE" | awk '{print $3}' | sort | uniq -c | sort -rn | head -10
    
    # 显示TOP10源IP
    echo -e "\n${YELLOW}TOP 10 查询源IP:${NC}"
    awk '{print $2}' "$DNS_LOG_FILE" | sort | uniq -c | sort -rn | head -10
    
    echo -e "\n${YELLOW}日志文件:${NC} $DNS_LOG_FILE"
    echo -e "${YELLOW}dnsmasq原始日志:${NC} $DNSMASQ_LOG_FILE"
    echo -e "使用 '--dns-log-count <数量>' 选项可查看更多记录"
    echo -e "使用 '--dns-log-domain <域名>' 选项可按域名筛选"
    echo -e "使用 '--dns-log-status <已转发|未转发>' 选项可按状态筛选"
    echo -e "使用 '--reset-dns-log' 选项可重置日志"
    
    return 0
}

# 重置DNS日志
reset_dns_logs() {
    log "INFO" "重置DNS日志..."
    
    if [ -f "$DNS_LOG_FILE" ]; then
        # 备份旧日志
        local timestamp=$(date +"%Y%m%d-%H%M%S")
        mv "$DNS_LOG_FILE" "${DNS_LOG_FILE}.${timestamp}"
        log "INFO" "已备份旧日志到 ${DNS_LOG_FILE}.${timestamp}"
    fi
    
    # 创建新的空日志文件
    touch "$DNS_LOG_FILE"
    chmod 644 "$DNS_LOG_FILE"
    
    if [ -f "$DNSMASQ_LOG_FILE" ]; then
        # 备份旧的dnsmasq日志
        local timestamp=$(date +"%Y%m%d-%H%M%S")
        mv "$DNSMASQ_LOG_FILE" "${DNSMASQ_LOG_FILE}.${timestamp}"
        log "INFO" "已备份旧的dnsmasq日志到 ${DNSMASQ_LOG_FILE}.${timestamp}"
        
        # 创建新的空dnsmasq日志文件
        touch "$DNSMASQ_LOG_FILE"
        chmod 644 "$DNSMASQ_LOG_FILE"
        
        # 重启dnsmasq，以便它使用新的日志文件
        systemctl restart dnsmasq
        
        # 重启日志处理服务
        systemctl restart zt-dns-processor
    fi
    
    log "INFO" "DNS日志已重置"
    return 0
}
