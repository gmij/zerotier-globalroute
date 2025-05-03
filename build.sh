#!/bin/bash
#
# ZeroTier 高级网关打包工具
# 功能：将项目中的所有文件打包为单个可执行sh脚本
# 版本：1.0
#

set -e  # 出错时退出

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="$SCRIPT_DIR/zerotier-gateway-bundle.sh"
VERSION=$(grep -o "版本：[0-9\.]*" "$SCRIPT_DIR/zerotier-gateway.sh" | awk -F '：' '{print $2}')
DATE=$(date +"%Y-%m-%d")

echo -e "${GREEN}开始打包 ZeroTier Gateway 脚本 (版本 $VERSION)...${NC}"

# 创建临时目录用于处理文件
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 函数：将文件内容编码为base64
function encode_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo -e "${RED}错误: 文件不存在: $file${NC}" >&2
    exit 1
  fi
  base64 -w 0 "$file"
}

# 开始创建输出文件
cat > "$OUTPUT_FILE" << EOL
#!/bin/bash
#
# ZeroTier 高级网关配置脚本 - 打包版
# 功能：配置 CentOS 服务器作为 ZeroTier 网络的网关，支持双向流量及 HTTPS
# 版本：$VERSION (打包于 $DATE)
#

# ====================================================================
# 打包脚本 - 包含所有依赖项
# 本文件由自动打包工具生成，包含了所有必要的模块和模板
# ====================================================================

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 创建临时目录并设置清理
TMP_DIR=\$(mktemp -d)
trap 'rm -rf "\$TMP_DIR"' EXIT

# 准备目录结构
mkdir -p "\$TMP_DIR/cmd"
mkdir -p "\$TMP_DIR/templates"

# 开始提取文件 - 直接写入文件而不使用decode_file函数
EOL

# 添加 cmd 目录中的文件
echo -e "${YELLOW}添加 cmd 目录中的文件...${NC}"
for file in "$SCRIPT_DIR/cmd"/*.sh; do
  filename=$(basename "$file")
  base64_content=$(encode_file "$file")
  
  cat >> "$OUTPUT_FILE" << EOL
# 提取 $filename
echo "$base64_content" | base64 --decode > "\$TMP_DIR/cmd/$filename"
chmod +x "\$TMP_DIR/cmd/$filename"

EOL
done

# 添加 templates 目录中的文件
echo -e "${YELLOW}添加 templates 目录中的文件...${NC}"
for file in "$SCRIPT_DIR/templates"/*; do
  filename=$(basename "$file")
  base64_content=$(encode_file "$file")
  
  cat >> "$OUTPUT_FILE" << EOL
# 提取 $filename
echo "$base64_content" | base64 --decode > "\$TMP_DIR/templates/$filename"

EOL
done

# 添加主脚本
echo -e "${YELLOW}添加主脚本...${NC}"
main_script_base64=$(encode_file "$SCRIPT_DIR/zerotier-gateway.sh")

cat >> "$OUTPUT_FILE" << EOL
# 提取主脚本
echo "$main_script_base64" | base64 --decode > "\$TMP_DIR/zerotier-gateway.sh"
chmod +x "\$TMP_DIR/zerotier-gateway.sh"

# 打印一条提示消息
echo -e "\${GREEN}正在运行 ZeroTier 高级网关配置脚本...\${NC}"
echo -e "\${YELLOW}注意：这是一个打包版本，所有依赖文件已内置\${NC}"
echo ""

# 执行主脚本，并传递所有命令行参数
"\$TMP_DIR/zerotier-gateway.sh" "\$@"

# 脚本结束
exit \$?
EOL

# 设置可执行权限
chmod +x "$OUTPUT_FILE"

echo -e "${GREEN}打包完成!${NC}"
echo "已生成打包文件: $OUTPUT_FILE"
echo ""
echo -e "${YELLOW}使用方法:${NC}"
echo "$ ./zerotier-gateway-bundle.sh [选项]"
echo ""
echo -e "${GREEN}打包信息:${NC}"
echo "版本: $VERSION"
echo "日期: $DATE"
echo "文件大小: $(du -h "$OUTPUT_FILE" | cut -f1)"