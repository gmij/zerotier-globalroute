#!/bin/bash
#
# ZeroTier 全局路由网关项目 - 简化构建脚本
# 功能：将所有模块整合为一个可执行的bundle脚本
# 版本：3.1 - 简化版
#

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}开始构建 ZeroTier 网关 bundle 脚本...${NC}"

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="zerotier-gateway-bundle.sh"

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
echo "生成bundle脚本: $OUTPUT_FILE"

# 创建bundle头部
cat > "$OUTPUT_FILE" << 'EOF'
#!/bin/bash
#
# ZeroTier 全局路由网关 - 单文件打包版
# 自动生成的bundle脚本，包含所有必要的模块和配置
# 版本：3.1 (Bundle版)
#

set -e

# Bundle标识
BUNDLE_MODE=true
BUNDLE_VERSION="3.1"

# 创建临时目录
BUNDLE_TEMP_DIR=$(mktemp -d)
SCRIPT_DIR="$BUNDLE_TEMP_DIR"

# 清理函数
cleanup_bundle() {
    rm -rf "$BUNDLE_TEMP_DIR" 2>/dev/null || true
}
trap cleanup_bundle EXIT

# 创建目录结构
mkdir -p "$BUNDLE_TEMP_DIR"/{cmd,config,templates,logs}

# 嵌入函数
embed_script() {
    local src_file="$1"
    local dest_name="$2"

    echo "嵌入文件: $src_file"

    # 使用不同的分隔符来避免冲突
    local delimiter="SCRIPT_$(echo "$dest_name" | tr '/' '_' | tr '.' '_')_END"

    cat >> "$OUTPUT_FILE" << EOF

# ===== $dest_name =====
cat > "\$SCRIPT_DIR/$dest_name" << '$delimiter'
EOF

    # 检查是否是绝对路径，如果是则直接使用，否则加上 SCRIPT_DIR
    if [[ "$src_file" = /* ]]; then
        cat "$src_file" >> "$OUTPUT_FILE"
    else
        cat "$SCRIPT_DIR/$src_file" >> "$OUTPUT_FILE"
    fi

    cat >> "$OUTPUT_FILE" << EOF
$delimiter

EOF
}

# 嵌入所有模块
embed_script "cmd/utils.sh" "cmd/utils.sh"
embed_script "cmd/config.sh" "cmd/config.sh"
embed_script "cmd/args.sh" "cmd/args.sh"
embed_script "cmd/detect.sh" "cmd/detect.sh"
embed_script "cmd/monitor.sh" "cmd/monitor.sh"
embed_script "cmd/uninstall.sh" "cmd/uninstall.sh"
embed_script "cmd/firewall.sh" "cmd/firewall.sh"
embed_script "cmd/gfwlist.sh" "cmd/gfwlist.sh"
embed_script "cmd/dnslog.sh" "cmd/dnslog.sh"
embed_script "config/default.conf" "config/default.conf"

# 嵌入模板文件（如果存在）
if [[ -d "$SCRIPT_DIR/templates" ]]; then
    find "$SCRIPT_DIR/templates" -type f -name "*.template" | while read -r template_file; do
        # 确保 template_file 是完整路径
        if [[ -f "$template_file" ]]; then
            # 获取相对路径，确保正确移除前缀
            relative_path="${template_file#$SCRIPT_DIR/}"
            # 使用完整路径作为源文件，相对路径作为目标路径
            embed_script "$template_file" "$relative_path"
        fi
    done
fi

# 添加主脚本内容（去除source语句）
echo "处理主脚本..."

cat >> "$OUTPUT_FILE" << 'EOF'

# ===== 主脚本 =====
EOF

# 去除source语句和shebang，添加主脚本内容
grep -v '^source.*\.sh' "$SCRIPT_DIR/zerotier-gateway.sh" | tail -n +2 >> "$OUTPUT_FILE"

# 添加bundle启动代码
cat >> "$OUTPUT_FILE" << 'EOF'

# ===== Bundle 启动 =====
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 设置文件权限
    chmod +x "$SCRIPT_DIR/cmd"/*.sh 2>/dev/null || true

    # 启动主函数
    main "$@"
fi
EOF

# 设置执行权限
chmod +x "$OUTPUT_FILE" 2>/dev/null || true

# 获取文件信息
if command -v du >/dev/null 2>&1; then
    BUNDLE_SIZE=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "未知")
else
    BUNDLE_SIZE=$(ls -lh "$OUTPUT_FILE" 2>/dev/null | awk '{print $5}' || echo "未知")
fi

echo -e "${GREEN}Bundle脚本构建完成！${NC}"
echo -e "输出文件: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "文件大小: ${YELLOW}$BUNDLE_SIZE${NC}"

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
