#!/bin/bash
#
# ZeroTier 全局路由网关项目 - Base64 编码构建脚本
# 功能：将所有模块使用 base64 编码整合为一个可执行的bundle脚本
# 版本：3.2 - Base64 编码版
#

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}开始构建 ZeroTier 网关 bundle 脚本 (Base64编码版)...${NC}"

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="zerotier-gateway-bundle.sh"

# 获取基础版本号
BASE_VERSION=$(grep -o "版本：[0-9\.]*" "$SCRIPT_DIR/zerotier-gateway.sh" | awk -F '：' '{print $2}' || echo "3.2")
# 添加日期生成完整版本号
DATE=$(date +"%Y-%m-%d")
VERSION="${BASE_VERSION} (打包于 ${DATE})"

# 函数：将文件内容编码为base64
encode_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}错误: 文件不存在: $file${NC}" >&2
        exit 1
    fi
    base64 -w 0 "$file" 2>/dev/null || base64 "$file" | tr -d '\n'
}

# 必需的文件列表
REQUIRED_FILES=(
    "zerotier-gateway.sh"
    "cmd/utils.sh"
    "cmd/config.sh"
    "cmd/args.sh"
    "cmd/detect.sh"
    "cmd/monitor.sh"
    "cmd/uninstall.sh"
    "cmd/firewall.sh"
    "cmd/gfwlist.sh"
    "cmd/dnslog.sh"
    "config/default.conf"
)

echo "检查项目文件结构..."

# 检查文件是否存在
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
        echo -e "${RED}错误: 缺少必需文件: $file${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $file"
done

echo "项目文件检查完成"

# 创建bundle文件
echo "生成 Base64 编码的 bundle脚本: $OUTPUT_FILE"

# 创建bundle头部
cat > "$OUTPUT_FILE" << 'EOF'
#!/bin/bash
#
# ZeroTier 全局路由网关 - Base64编码打包版
# 功能：配置 CentOS 服务器作为 ZeroTier 网络的网关，支持双向流量
# EOF

echo "# 版本：$VERSION" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
#

# ====================================================================
# 打包脚本 - 包含所有依赖项 (Base64编码)
# 本文件由自动打包工具生成，包含了所有必要的模块和模板
# ====================================================================

set -e

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Bundle标识
BUNDLE_MODE=true
BUNDLE_VERSION="Base64-3.2"

# 获取脚本所在目录的绝对路径
BUNDLE_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(dirname "$BUNDLE_SCRIPT_PATH")"

# 创建临时目录
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo -e "${GREEN}正在运行 ZeroTier 网关配置脚本 (Base64版)...${NC}"
echo -e "${YELLOW}临时目录: $TMP_DIR${NC}"

# 创建目录结构
mkdir -p "$TMP_DIR"/{cmd,config,templates,logs}

# 解码函数
decode_and_create() {
    local base64_content="$1"
    local target_file="$2"
    local target_dir="$(dirname "$target_file")"

    mkdir -p "$target_dir"
    echo "$base64_content" | base64 --decode > "$target_file" 2>/dev/null || \
    echo "$base64_content" | base64 -d > "$target_file" 2>/dev/null || {
        echo -e "${RED}错误: 无法解码文件 $target_file${NC}"
        return 1
    }

    # 如果是shell脚本，设置执行权限
    if [[ "$target_file" == *.sh ]]; then
        chmod +x "$target_file"
    fi

    echo -e "${GREEN}已解码: $target_file${NC}"
}

echo -e "${BLUE}开始解码文件...${NC}"

EOF
}

# 开始添加 Base64 编码的文件内容
echo -e "${YELLOW}添加 cmd 目录中的文件...${NC}"
for file in "${REQUIRED_FILES[@]}"; do
    if [[ "$file" == cmd/*.sh ]]; then
        filename=$(basename "$file")
        base64_content=$(encode_file "$SCRIPT_DIR/$file")

        cat >> "$OUTPUT_FILE" << EOL
# 解码 $filename
decode_and_create "$base64_content" "\$TMP_DIR/$file"

EOL
        echo -e "${GREEN}已编码: $file${NC}"
    fi
done

# 添加配置文件
echo -e "${YELLOW}添加配置文件...${NC}"
if [[ -f "$SCRIPT_DIR/config/default.conf" ]]; then
    base64_content=$(encode_file "$SCRIPT_DIR/config/default.conf")
    cat >> "$OUTPUT_FILE" << EOL
# 解码 default.conf
decode_and_create "$base64_content" "\$TMP_DIR/config/default.conf"

EOL
    echo -e "${GREEN}已编码: config/default.conf${NC}"
fi

# 添加模板文件
echo -e "${YELLOW}添加模板文件...${NC}"
if [[ -d "$SCRIPT_DIR/templates" ]]; then
    find "$SCRIPT_DIR/templates" -type f -name "*.template" | while read -r template_file; do
        relative_path="${template_file#$SCRIPT_DIR/}"
        filename=$(basename "$template_file")
        base64_content=$(encode_file "$template_file")

        cat >> "$OUTPUT_FILE" << EOL
# 解码 $filename
decode_and_create "$base64_content" "\$TMP_DIR/$relative_path"

EOL
        echo -e "${GREEN}已编码: $relative_path${NC}"
    done
fi

# 添加主脚本
echo -e "${YELLOW}添加主脚本...${NC}"
main_script_base64=$(encode_file "$SCRIPT_DIR/zerotier-gateway.sh")

cat >> "$OUTPUT_FILE" << EOL
# 解码主脚本
decode_and_create "$main_script_base64" "\$TMP_DIR/zerotier-gateway.sh"

# 设置SCRIPT_DIR为临时目录，这样主脚本可以找到其他模块
export SCRIPT_DIR="\$TMP_DIR"
export BUNDLE_MODE=true

echo -e "\${GREEN}所有文件解码完成！\${NC}"
echo -e "\${BLUE}开始执行主脚本...\${NC}"

# 执行主脚本
cd "\$TMP_DIR"
bash "./zerotier-gateway.sh" "\$@"
EOL

# 设置执行权限
chmod +x "$OUTPUT_FILE" 2>/dev/null || true

# 获取文件信息
if command -v du >/dev/null 2>&1; then
    BUNDLE_SIZE=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "未知")
else
    BUNDLE_SIZE=$(ls -lh "$OUTPUT_FILE" 2>/dev/null | awk '{print $5}' || echo "未知")
fi

echo -e "${GREEN}Base64编码Bundle脚本构建完成！${NC}"
echo -e "输出文件: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "文件大小: ${YELLOW}$BUNDLE_SIZE${NC}"
echo -e "版本信息: ${YELLOW}$VERSION${NC}"

# 验证bundle文件
if bash -n "$OUTPUT_FILE" 2>/dev/null; then
    echo -e "${GREEN}Bundle脚本语法检查通过${NC}"
else
    echo -e "${YELLOW}警告: Bundle脚本语法检查失败，但文件已生成${NC}"
fi

echo -e "${GREEN}构建过程完成！${NC}"
echo ""
echo -e "${GREEN}使用方法：${NC}"
echo -e "  ${BLUE}chmod +x $OUTPUT_FILE${NC}"
echo -e "  ${BLUE}./$OUTPUT_FILE [参数]${NC}"
echo ""

# 显示生成的文件
if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${GREEN}✓ 文件已成功生成: $OUTPUT_FILE${NC}"
    ls -la "$OUTPUT_FILE" 2>/dev/null || dir "$OUTPUT_FILE" 2>/dev/null || echo "文件确实存在"
else
    echo -e "${RED}✗ 文件生成失败${NC}"
    exit 1
fi
