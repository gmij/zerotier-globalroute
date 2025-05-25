#!/bin/bash
#
# ZeroTier 网关工具函数库
# 统一的工具函数和系统检查
#

# 显示彩色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志配置
LOG_FILE="${SCRIPT_DIR}/logs/zt-gateway.log"
ERROR_LOG_FILE="${SCRIPT_DIR}/logs/zt-gateway-error.log"

# 增强的日志记录函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"

    # 确保日志目录存在
    mkdir -p "${SCRIPT_DIR}/logs" 2>/dev/null

    # 写入主日志文件
    echo "$log_entry" >> "$LOG_FILE"

    # 错误和警告额外写入错误日志
    if [ "$level" = "ERROR" ] || [ "$level" = "WARN" ]; then
        echo "$log_entry" >> "$ERROR_LOG_FILE"
    fi

    # 控制台输出
    case "$level" in
        INFO) echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG)
            [ "$DEBUG_MODE" = "1" ] && echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        *)
            echo -e "${CYAN}[$level]${NC} $message"
            ;;
    esac
}

# 增强的错误处理函数
handle_error() {
    local error_msg="$1"
    local exit_code="${2:-1}"
    local show_help="${3:-0}"

    log "ERROR" "$error_msg"
    echo -e "${RED}错误: $error_msg${NC}" >&2

    # 在调试模式下显示更多信息
    if [ "$DEBUG_MODE" = "1" ]; then
        echo -e "${YELLOW}调试信息:${NC}" >&2
        echo -e "  脚本: ${BASH_SOURCE[1]}" >&2
        echo -e "  行号: ${BASH_LINENO[0]}" >&2
        echo -e "  函数: ${FUNCNAME[1]}" >&2

        # 显示最近的日志条目
        if [ -f "$LOG_FILE" ]; then
            echo -e "${YELLOW}最近的日志条目:${NC}" >&2
            tail -n 5 "$LOG_FILE" >&2
        fi
    fi

    # 如果指定，显示帮助信息
    if [ "$show_help" = "1" ]; then
        echo -e "${YELLOW}使用 --help 查看帮助信息${NC}" >&2
    fi

    # 清理临时文件（如果有）
    cleanup_on_error

    exit "$exit_code"
}

# 错误清理函数
cleanup_on_error() {
    # 清理可能的临时文件和状态
    local temp_files=("/tmp/zt-gateway-*" "/tmp/gfwlist-*")

    for pattern in "${temp_files[@]}"; do
        rm -f $pattern 2>/dev/null
    done

    log "DEBUG" "错误清理完成"
}

# 系统要求检查
check_system_requirements() {
    log "INFO" "检查系统要求..."

    local missing_deps=()
    local required_commands=("iptables" "ip" "curl" "systemctl")

    # 检查基本命令
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # 检查系统版本
    if [ -f /etc/centos-release ]; then
        local centos_version=$(cat /etc/centos-release | grep -oP '(?<=release )\d+')
        if [ "$centos_version" -lt 7 ]; then
            handle_error "需要 CentOS 7 或更高版本"
        fi
        log "INFO" "检测到 CentOS $centos_version"
    elif [ -f /etc/redhat-release ]; then
        log "INFO" "检测到 Red Hat 系列系统"
    else
        log "WARN" "未检测到 CentOS 系统，可能存在兼容性问题"
    fi

    # 报告缺失的依赖
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "ERROR" "缺少必需的命令: ${missing_deps[*]}"
        echo -e "${YELLOW}请安装缺失的依赖包后重试${NC}"
        exit 1
    fi

    log "SUCCESS" "系统要求检查通过"
}

# 网络连接检查
check_network_connectivity() {
    log "INFO" "检查网络连接..."

    local test_hosts=("8.8.8.8" "1.1.1.1" "223.5.5.5")
    local success_count=0

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" &>/dev/null; then
            ((success_count++))
            log "DEBUG" "连接到 $host 成功"
        else
            log "DEBUG" "连接到 $host 失败"
        fi
    done

    if [ "$success_count" -eq 0 ]; then
        log "ERROR" "网络连接检查失败，请检查网络设置"
        return 1
    elif [ "$success_count" -lt 2 ]; then
        log "WARN" "网络连接不稳定，可能影响某些功能"
    else
        log "SUCCESS" "网络连接正常"
    fi

    return 0
}

# 权限检查
check_permissions() {
    log "DEBUG" "检查运行权限..."

    # 检查是否为root
    if [ "$EUID" -ne 0 ]; then
        handle_error "需要 root 权限运行此脚本"
    fi

    # 检查重要目录的写权限
    local important_dirs=("/etc" "/etc/systemd/system" "/etc/sysctl.d")

    for dir in "${important_dirs[@]}"; do
        if [ ! -w "$dir" ]; then
            log "WARN" "目录 $dir 可能没有写权限"
        fi
    done

    log "DEBUG" "权限检查完成"
}

# 服务状态检查
check_service_status() {
    local service_name="$1"
    local required="${2:-0}"  # 是否必需

    if systemctl is-active --quiet "$service_name"; then
        log "DEBUG" "服务 $service_name 正在运行"
        return 0
    elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log "WARN" "服务 $service_name 已启用但未运行"
        return 1
    else
        if [ "$required" = "1" ]; then
            log "ERROR" "必需的服务 $service_name 未安装或未启用"
            return 2
        else
            log "DEBUG" "可选服务 $service_name 未安装"
            return 1
        fi
    fi
}

# 磁盘空间检查
check_disk_space() {
    local min_space_mb="${1:-100}"  # 最小空间要求（MB）

    local available_space=$(df "${SCRIPT_DIR}" | tail -1 | awk '{print $4}')
    available_space=$((available_space / 1024))  # 转换为MB

    if [ "$available_space" -lt "$min_space_mb" ]; then
        log "WARN" "磁盘空间不足：可用 ${available_space}MB，建议至少 ${min_space_mb}MB"
        return 1
    fi

    log "DEBUG" "磁盘空间充足：可用 ${available_space}MB"
    return 0
}

# 完整的系统环境检查
check_system_environment() {
    log "INFO" "开始系统环境检查..."

    # 这些检查不能失败，否则脚本无法继续
    check_permissions
    check_system_requirements
    check_network_connectivity
    check_disk_space 50

    # 检查关键服务（使用更宽松的错误处理）
    log "DEBUG" "检查 ZeroTier 服务状态..."
    if ! systemctl is-active --quiet zerotier-one; then
        if systemctl is-enabled --quiet zerotier-one 2>/dev/null; then
            log "WARN" "ZeroTier 服务已安装但未运行，尝试启动..."
            if systemctl start zerotier-one 2>/dev/null; then
                log "INFO" "ZeroTier 服务启动成功"
            else
                handle_error "无法启动 ZeroTier 服务，请检查安装状态"
            fi
        else
            handle_error "ZeroTier 服务未安装，请先安装 ZeroTier 客户端"
        fi
    else
        log "DEBUG" "ZeroTier 服务运行正常"
    fi

    # 检查可选服务（不会导致脚本退出）
    check_service_status "iptables" 0 || true
    check_service_status "dnsmasq" 0 || true

    log "SUCCESS" "系统环境检查完成"
}

# 准备目录结构（重构版本）
prepare_dirs() {
    log "DEBUG" "准备目录结构..."

    # 使用配置管理系统初始化
    init_config_system

    # 创建额外目录
    mkdir -p "${SCRIPT_DIR}/backups" || log "WARN" "无法创建备份目录"
    mkdir -p "${SCRIPT_DIR}/tmp" || log "WARN" "无法创建临时目录"

    # 设置日志文件权限
    touch "$LOG_FILE" && chmod 644 "$LOG_FILE"
    touch "$ERROR_LOG_FILE" && chmod 644 "$ERROR_LOG_FILE"

    log "DEBUG" "目录结构准备完成"
}
