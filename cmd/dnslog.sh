#!/bin/bash
#
# ZeroTier 网关 DNS 日志处理模块
#

# DNS日志文件路径
DNS_LOG_FILE="${SCRIPT_DIR}/logs/zt-dns-queries.log"
DNS_LOG_MAX_SIZE=10485760 # 10MB
DNS_LOG_MAX_DAYS=7 # 保留7天日志

# 初始化DNS日志功能
init_dns_logging() {
    log "INFO" "初始化DNS日志功能..."
    
    # 确保logs目录存在
    mkdir -p "${SCRIPT_DIR}/logs"
    
    # 创建空日志文件（如果不存在）
    if [ ! -f "$DNS_LOG_FILE" ]; then
        touch "$DNS_LOG_FILE"
        chmod 644 "$DNS_LOG_FILE"
    fi
    
    # 添加自动轮转日志的cron任务
    if ! crontab -l | grep -q "zt-dns-queries"; then
        (crontab -l 2>/dev/null; echo "0 0 * * * /bin/find ${SCRIPT_DIR}/logs/ -name 'zt-dns-queries.log.*' -mtime +$DNS_LOG_MAX_DAYS -delete") | crontab -
        log "INFO" "已设置DNS日志轮转任务"
    fi
    
    log "INFO" "DNS日志功能已初始化"
    return 0
}

# 记录DNS查询
log_dns_query() {
    local query_time="$1"
    local source_ip="$2"
    local domain="$3"
    local query_type="$4"
    local forwarded="$5" # 1=已转发, 0=未转发
    
    local forwarded_text
    if [ "$forwarded" = "1" ]; then
        forwarded_text="已转发"
    else
        forwarded_text="未转发"
    fi
    
    echo "[$query_time] $source_ip $domain $query_type $forwarded_text" >> "$DNS_LOG_FILE"
    
    # 检查日志大小并轮转
    if [ -f "$DNS_LOG_FILE" ]; then
        local log_size=$(stat -c%s "$DNS_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$log_size" -gt "$DNS_LOG_MAX_SIZE" ]; then
            log "INFO" "DNS日志文件达到最大大小，进行轮转..."
            local timestamp=$(date +"%Y%m%d-%H%M%S")
            mv "$DNS_LOG_FILE" "${DNS_LOG_FILE}.${timestamp}"
            touch "$DNS_LOG_FILE"
            chmod 644 "$DNS_LOG_FILE"
        fi
    fi
}

# 设置DNS日志记录
setup_dns_logging() {
    log "INFO" "设置DNS日志记录..."
    
    # 确保已安装必要工具
    if ! command -v tcpdump &>/dev/null; then
        log "INFO" "安装 tcpdump..."
        yum install -y tcpdump || {
            log "ERROR" "安装 tcpdump 失败"
            return 1
        }
    fi
    
    # 创建DNS日志记录脚本
    local dns_capture_script="/usr/local/bin/zt-dns-capture.sh"
    cat > "$dns_capture_script" << 'EOF'
#!/bin/bash

ZT_INTERFACE="$1"
DNS_LOG_FILE="$2"
SCRIPT_DIR="$3"

if [ -z "$ZT_INTERFACE" ] || [ -z "$DNS_LOG_FILE" ] || [ -z "$SCRIPT_DIR" ]; then
    echo "用法: $0 <ZeroTier接口> <日志文件路径> <脚本目录>"
    exit 1
fi

# 检测环境并确保logs目录存在
mkdir -p "$SCRIPT_DIR/logs"
touch "$DNS_LOG_FILE"

# 使用tcpdump捕获DNS查询
tcpdump -i "$ZT_INTERFACE" -l -nn 'udp port 53 or tcp port 53' 2>/dev/null | while read -r line; do
    # 提取时间戳
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # 尝试提取DNS查询信息
    if echo "$line" | grep -q "A?" || echo "$line" | grep -q "AAAA?"; then
        # 提取源IP
        source_ip=$(echo "$line" | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -z "$source_ip" ]; then
            source_ip=$(echo "$line" | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
        
        # 提取域名和查询类型
        domain_info=$(echo "$line" | grep -o -E 'A\? [^ ]+|AAAA\? [^ ]+' | head -1)
        if [ -n "$domain_info" ]; then
            query_type=$(echo "$domain_info" | cut -d' ' -f1 | sed 's/?//')
            domain=$(echo "$domain_info" | cut -d' ' -f2 | sed 's/\.$//')
            
            # 检查该域名是否需要转发
            forwarded=0
            forwarded_text="未转发"
            
            # 首先检查是否是自定义域名列表中的域名
            if [ -f "$SCRIPT_DIR/config/custom_domains.txt" ] && grep -q "$domain" "$SCRIPT_DIR/config/custom_domains.txt"; then
                forwarded=1
                forwarded_text="已转发(自定义域名)"
            # 然后检查是否在GFW列表中
            elif [ -f "$SCRIPT_DIR/config/gfwlist_domains.txt" ] && grep -q "$domain" "$SCRIPT_DIR/config/gfwlist_domains.txt"; then
                forwarded=1
                forwarded_text="已转发(GFW列表)"
            # 最后检查通过IP判断
            elif command -v ipset &>/dev/null && ipset list gfwlist &>/dev/null; then
                # 尝试解析域名获取IP
                ip=$(dig +short "$domain" 2>/dev/null | head -1)
                if [ -n "$ip" ] && ipset test gfwlist "$ip" 2>/dev/null; then
                    forwarded=1
                    forwarded_text="已转发(IP匹配)"
                fi
            fi
            
            # 检查域名是否是通配符匹配
            if [ "$forwarded" = "0" ] && [ -f "$SCRIPT_DIR/config/custom_domains.txt" ]; then
                # 提取根域名
                root_domain=$(echo "$domain" | awk -F. '{if (NF>1) {print $(NF-1)"."$NF} else {print $NF}}')
                parent_domain=$(echo "$domain" | sed "s/^[^.]*\.//")
                
                # 检查通配符匹配
                if grep -q "\*\.$root_domain" "$SCRIPT_DIR/config/custom_domains.txt" || 
                   grep -q "\*\.$parent_domain" "$SCRIPT_DIR/config/custom_domains.txt"; then
                    forwarded=1
                    forwarded_text="已转发(通配符匹配)"
                fi
            fi
            
            # 记录查询
            echo "[$timestamp] $source_ip $domain $query_type $forwarded_text" >> "$DNS_LOG_FILE"
        fi
    fi
done
EOF

    chmod +x "$dns_capture_script"
    
    # 创建systemd服务
    local service_file="/etc/systemd/system/zt-dns-logger.service"
    cat > "$service_file" << EOF
[Unit]
Description=ZeroTier DNS查询日志服务
After=network.target zerotier-one.service

[Service]
Type=simple
ExecStart=/usr/local/bin/zt-dns-capture.sh $ZT_INTERFACE $DNS_LOG_FILE $SCRIPT_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable zt-dns-logger
    systemctl restart zt-dns-logger
    
    log "INFO" "DNS日志记录已设置"
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
    echo "已转发查询: $forwarded_queries ($(awk -v f=$forwarded_queries -v t=$total_queries 'BEGIN{printf "%.1f%%", f/t*100}'))"
    echo "未转发查询: $not_forwarded ($(awk -v n=$not_forwarded -v t=$total_queries 'BEGIN{printf "%.1f%%", n/t*100}'))"
    
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
    
    log "INFO" "DNS日志已重置"
    return 0
}
