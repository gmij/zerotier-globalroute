#!/bin/bash
#
# ZeroTier 网关工具函数库
#

# 显示彩色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志配置
LOG_FILE="${SCRIPT_DIR}/logs/zt-gateway.log"
CONFIG_DIR="/etc/zt-gateway"
CONFIG_FILE="$CONFIG_DIR/config"

# 记录日志
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        INFO) echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) [ "$DEBUG_MODE" = "1" ] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# 错误处理函数
handle_error() {
    log "ERROR" "$1"
    echo -e "${RED}错误: $1${NC}"
    exit 1
}

# 准备目录结构
prepare_dirs() {
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    # 创建logs目录
    mkdir -p "${SCRIPT_DIR}/logs"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}