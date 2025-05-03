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
# 获取基础版本号
BASE_VERSION=$(grep -o "版本：[0-9\.]*" "$SCRIPT_DIR/zerotier-gateway.sh" | awk -F '：' '{print $2}')
# 添加日期生成完整版本号
DATE=$(date +"%Y-%m-%d")
VERSION="${BASE_VERSION} (打包于 ${DATE})"

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
# 版本：$VERSION
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

# 获取脚本所在目录的绝对路径
ZT_SCRIPT_PATH="\$(readlink -f "\$0")"
ZT_SCRIPT_DIR="\$(dirname "\$ZT_SCRIPT_PATH")"

# 创建临时目录并设置清理
TMP_DIR=\$(mktemp -d)
trap 'rm -rf "\$TMP_DIR"' EXIT

# 准备目录结构
mkdir -p "\$TMP_DIR/cmd"
mkdir -p "\$TMP_DIR/templates"

# 辅助函数
create_symlink() {
  local source_file="\$1"
  local target_link="\$2"
  local target_dir=\$(dirname "\$target_link")
  
  # 尝试创建目标目录
  if [ ! -d "\$target_dir" ]; then
    echo -e "\${YELLOW}目录不存在，尝试创建: \$target_dir\${NC}"
    mkdir -p "\$target_dir" 2>/dev/null || sudo mkdir -p "\$target_dir" 2>/dev/null || {
      echo -e "\${RED}无法创建目录: \$target_dir\${NC}"
      return 1
    }
  fi
  
  # 尝试创建软链接
  ln -sf "\$source_file" "\$target_link" 2>/dev/null || sudo ln -sf "\$source_file" "\$target_link" 2>/dev/null || {
    echo -e "\${YELLOW}无法创建软链接: \$target_link -> \$source_file\${NC}"
    echo -e "\${YELLOW}您可能需要手动执行: sudo ln -sf \$source_file \$target_link\${NC}"
    return 1
  }
  
  echo -e "\${GREEN}已创建软链接: \$target_link -> \$source_file\${NC}"
  return 0
}

# 创建目录结构
setup_install_dirs() {
  echo -e "\${BLUE}创建安装目录结构...\${NC}"
  
  # 创建子目录
  mkdir -p "\$ZT_SCRIPT_DIR/cmd" "\$ZT_SCRIPT_DIR/templates" "\$ZT_SCRIPT_DIR/bin" "\$ZT_SCRIPT_DIR/scripts" || {
    echo -e "\${RED}无法创建安装子目录\${NC}"
    return 1
  }
  
  echo -e "\${GREEN}安装目录已准备就绪: \$ZT_SCRIPT_DIR\${NC}"
  return 0
}

# 开始提取文件
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

# 设置安装目录
setup_install_dirs

# 复制脚本到安装目录
echo -e "\${BLUE}复制文件到安装目录...\${NC}"

# 复制主脚本
cp -f "\$TMP_DIR/zerotier-gateway.sh" "\$ZT_SCRIPT_DIR/zerotier-gateway.sh" || echo -e "\${RED}无法复制主脚本\${NC}"
chmod +x "\$ZT_SCRIPT_DIR/zerotier-gateway.sh" 2>/dev/null

# 复制命令脚本
for file in "\$TMP_DIR/cmd"/*.sh; do
  filename=\$(basename "\$file")
  cp -f "\$file" "\$ZT_SCRIPT_DIR/cmd/" || echo -e "\${RED}无法复制: \$filename\${NC}"
  chmod +x "\$ZT_SCRIPT_DIR/cmd/\$filename" 2>/dev/null
done

# 复制模板
for file in "\$TMP_DIR/templates"/*; do
  filename=\$(basename "\$file")
  cp -f "\$file" "\$ZT_SCRIPT_DIR/templates/" || echo -e "\${RED}无法复制: \$filename\${NC}"
done

# 创建配置目录
mkdir -p "\$ZT_SCRIPT_DIR/config" 2>/dev/null || true
touch "\$ZT_SCRIPT_DIR/config/.keep" 2>/dev/null || true

# 打印一条提示消息
echo -e "\${GREEN}正在运行 ZeroTier 高级网关配置脚本...\${NC}"
echo -e "\${YELLOW}注意：这是一个便携式安装版本，所有文件统一存放在: \$ZT_SCRIPT_DIR\${NC}"
echo ""

# 从安装目录执行主脚本
cd "\$ZT_SCRIPT_DIR"
"\$ZT_SCRIPT_DIR/zerotier-gateway.sh" "\$@"
exit_code=\$?

# 打包脚本创建的软链接处理
echo ""
echo -e "\${BLUE}正在创建系统软链接...\${NC}"

# 创建脚本链接目录
mkdir -p "\$ZT_SCRIPT_DIR/bin" 2>/dev/null || true

# 创建状态脚本
if [ -f "\$ZT_SCRIPT_DIR/templates/status-script.sh.template" ]; then
  cp -f "\$ZT_SCRIPT_DIR/templates/status-script.sh.template" "\$ZT_SCRIPT_DIR/bin/zt-status" || echo -e "\${RED}无法创建状态脚本\${NC}"
  chmod +x "\$ZT_SCRIPT_DIR/bin/zt-status" 2>/dev/null
  create_symlink "\$ZT_SCRIPT_DIR/bin/zt-status" "/usr/local/bin/zt-status"
fi

# 创建网络接口监控脚本链接
if [ -f "\$ZT_SCRIPT_DIR/templates/network-monitor.sh.template" ]; then
  cp -f "\$ZT_SCRIPT_DIR/templates/network-monitor.sh.template" "\$ZT_SCRIPT_DIR/scripts/99-ztmtu.sh" || echo -e "\${RED}无法创建网络监控脚本\${NC}"
  chmod +x "\$ZT_SCRIPT_DIR/scripts/99-ztmtu.sh" 2>/dev/null
  create_symlink "\$ZT_SCRIPT_DIR/scripts/99-ztmtu.sh" "/etc/NetworkManager/dispatcher.d/99-ztmtu.sh"
fi

# 创建定时检查脚本链接
if [ -f "\$ZT_SCRIPT_DIR/templates/daily-check.sh.template" ]; then
  cp -f "\$ZT_SCRIPT_DIR/templates/daily-check.sh.template" "\$ZT_SCRIPT_DIR/scripts/zt-gateway-check" || echo -e "\${RED}无法创建定时检查脚本\${NC}"
  chmod +x "\$ZT_SCRIPT_DIR/scripts/zt-gateway-check" 2>/dev/null
  create_symlink "\$ZT_SCRIPT_DIR/scripts/zt-gateway-check" "/etc/cron.daily/zt-gateway-check"
fi

# 打印安装摘要
echo ""
echo -e "\${GREEN}===== ZeroTier 网关安装摘要 =====\${NC}"
echo -e "\${YELLOW}安装目录:\${NC} \$ZT_SCRIPT_DIR"
echo -e "\${YELLOW}主程序:\${NC} \$ZT_SCRIPT_DIR/zerotier-gateway.sh"
echo -e "\${YELLOW}配置文件:\${NC} \$ZT_SCRIPT_DIR/config (如已创建)"

# 打印帮助信息
echo ""
echo -e "\${GREEN}===== 使用说明 =====\${NC}"
echo -e "1. 运行配置脚本: \${YELLOW}\$ZT_SCRIPT_DIR/zerotier-gateway.sh\${NC}"
echo -e "2. 查看流量统计: \${YELLOW}\$ZT_SCRIPT_DIR/zerotier-gateway.sh --stats\${NC}"
echo -e "3. 测试网关连通性: \${YELLOW}\$ZT_SCRIPT_DIR/zerotier-gateway.sh --test\${NC}"
echo -e "4. 卸载网关: \${YELLOW}\$ZT_SCRIPT_DIR/zerotier-gateway.sh --uninstall\${NC}"
echo -e "5. 迁移说明: 只需复制整个 \${YELLOW}\$ZT_SCRIPT_DIR\${NC} 目录到新位置即可"

# 脚本结束
exit \$exit_code
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