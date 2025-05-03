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

# 函数：将文件内容转换为base64编码的变量
function file_to_inline() {
  local file="$1"
  local var_name="$2"
  
  if [ ! -f "$file" ]; then
    echo -e "${RED}错误: 文件不存在: $file${NC}" >&2
    exit 1
  fi
  
  echo "# --- 开始文件: $(basename "$file") ---"
  echo "$var_name=\"$(base64 -w 0 "$file")\""
  echo "# --- 结束文件: $(basename "$file") ---"
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

EOL

# 写入颜色定义和辅助函数
cat >> "$OUTPUT_FILE" << 'EOL'
# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 创建临时目录
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 准备工作目录
function prepare_temp_files() {
  mkdir -p "$TMP_DIR/cmd"
  mkdir -p "$TMP_DIR/templates"
}

# 加载base64解码函数
function decode_file() {
  local var_content="$1"
  echo "$var_content" | base64 --decode
}

# 初始化临时文件
prepare_temp_files

EOL

# 添加 cmd 目录中的文件
echo -e "${YELLOW}添加 cmd 目录中的文件...${NC}"
for file in "$SCRIPT_DIR/cmd"/*.sh; do
  filename=$(basename "$file")
  var_name="${filename%.sh}"
  file_to_inline "$file" "$var_name" >> "$OUTPUT_FILE"
  
  cat >> "$OUTPUT_FILE" << EOL
cat > "\$TMP_DIR/cmd/$filename" << 'EOF_WRITE'
\$(decode_file "\$$var_name")
EOF_WRITE
chmod +x "\$TMP_DIR/cmd/$filename"

EOL
done

# 添加 templates 目录中的文件
echo -e "${YELLOW}添加 templates 目录中的文件...${NC}"
for file in "$SCRIPT_DIR/templates"/*; do
  filename=$(basename "$file")
  var_name="${filename//[-.]/}"
  file_to_inline "$file" "$var_name" >> "$OUTPUT_FILE"
  
  cat >> "$OUTPUT_FILE" << EOL
cat > "\$TMP_DIR/templates/$filename" << 'EOF_WRITE'
\$(decode_file "\$$var_name")
EOF_WRITE

EOL
done

# 添加主脚本
echo -e "${YELLOW}添加主脚本...${NC}"
file_to_inline "$SCRIPT_DIR/zerotier-gateway.sh" "main_script" >> "$OUTPUT_FILE"

# 添加执行主脚本的代码
cat >> "$OUTPUT_FILE" << 'EOL'
# 运行主脚本
SCRIPT_PATH="$TMP_DIR/zerotier-gateway.sh"
cat > "$SCRIPT_PATH" << 'EOF_WRITE'
$(decode_file "$main_script")
EOF_WRITE
chmod +x "$SCRIPT_PATH"

# 打印一条提示消息
echo -e "${GREEN}正在运行 ZeroTier 高级网关配置脚本...${NC}"
echo -e "${YELLOW}注意：这是一个打包版本，所有依赖文件已内置${NC}"
echo ""

# 执行主脚本，并传递所有命令行参数
"$SCRIPT_PATH" "$@"

# 脚本结束
exit $?
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