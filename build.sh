#!/bin/bash
#
# ZeroTier 高级网关打包工具
# 功能：将项目中的所有文件打包为单个可执行sh脚本
# 版本：2.0
#

set -e  # 出错时退出

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_FILE="$SCRIPT_DIR/zerotier-gateway-bundle.sh"

# 获取版本信息
if [ -f "$SCRIPT_DIR/config/default.conf" ]; then
    BASE_VERSION=$(grep "CONFIG_VERSION=" "$SCRIPT_DIR/config/default.conf" | cut -d'"' -f2)
else
    BASE_VERSION="2.0.0"
fi

# 添加日期生成完整版本号
DATE=$(date +"%Y-%m-%d")
BUILD_TIME=$(date +"%Y-%m-%d %H:%M:%S")
VERSION="${BASE_VERSION} (构建于 ${BUILD_TIME})"

echo -e "${GREEN}开始打包 ZeroTier Gateway 脚本...${NC}"
echo -e "${BLUE}版本: $VERSION${NC}"

# 创建临时目录用于处理文件
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 函数：将文件内容编码为base64
encode_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}错误: 文件不存在: $file${NC}" >&2
        exit 1
    fi
    base64 -w 0 "$file" 2>/dev/null || base64 "$file"
}

# 函数：检查必需文件
check_required_files() {
    local required_files=(
        "zerotier-gateway.sh"
        "config/default.conf"
        "cmd/args.sh"
        "cmd/config.sh"
        "cmd/utils.sh"
        "cmd/detect.sh"
        "cmd/firewall.sh"
        "cmd/gfwlist.sh"
        "cmd/dnslog.sh"
        "cmd/monitor.sh"
        "cmd/uninstall.sh"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$file" ]; then
            echo -e "${RED}错误: 必需文件不存在: $file${NC}" >&2
            exit 1
        fi
    EOL

# 替换版本信息
sed -i "s/VERSION_PLACEHOLDER/$VERSION/g" "$OUTPUT_FILE"
sed -i "s/BUILD_TIME_PLACEHOLDER/$BUILD_TIME/g" "$OUTPUT_FILE"

echo -e "${YELLOW}正在打包模块文件...${NC}"

# 添加解包和初始化函数
cat >> "$OUTPUT_FILE" << 'EOL'

# 设置脚本目录变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 解包函数 - 解压内嵌的文件到临时目录
extract_bundled_files() {
    local work_dir="$1"

    echo "正在解包内嵌文件到 $work_dir ..."

    # 创建目录结构
    mkdir -p "$work_dir"/{cmd,config,templates,scripts,logs}

    # 解包各个文件
EOL

# 打包配置文件
echo -e "${BLUE}  打包配置文件...${NC}"
cat >> "$OUTPUT_FILE" << EOL

    # 解包默认配置文件
    echo "$(encode_file "$SCRIPT_DIR/config/default.conf")" | base64 -d > "\$work_dir/config/default.conf"
EOL

# 打包模块文件
echo -e "${BLUE}  打包模块文件...${NC}"
for module in args config utils detect firewall gfwlist dnslog monitor uninstall; do
    if [ -f "$SCRIPT_DIR/cmd/$module.sh" ]; then
        echo "    - $module.sh"
        cat >> "$OUTPUT_FILE" << EOL

    # 解包 $module 模块
    echo "$(encode_file "$SCRIPT_DIR/cmd/$module.sh")" | base64 -d > "\$work_dir/cmd/$module.sh"
EOL
    fi
done

# 打包模板文件
echo -e "${BLUE}  打包模板文件...${NC}"
if [ -d "$SCRIPT_DIR/templates" ]; then
    for template in "$SCRIPT_DIR/templates"/*.template; do
        if [ -f "$template" ]; then
            template_name=$(basename "$template")
            echo "    - $template_name"
            cat >> "$OUTPUT_FILE" << EOL

    # 解包模板文件: $template_name
    echo "$(encode_file "$template")" | base64 -d > "\$work_dir/templates/$template_name"
EOL
        fi
    done
fi

# 完成解包函数
cat >> "$OUTPUT_FILE" << 'EOL'

    echo "文件解包完成"
}

# 清理函数
cleanup_bundled_files() {
    local work_dir="$1"
    if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
        rm -rf "$work_dir"
    fi
}

# 主执行函数
main() {
    # 创建临时工作目录
    local BUNDLE_WORK_DIR=$(mktemp -d)

    # 设置清理陷阱
    trap "cleanup_bundled_files '$BUNDLE_WORK_DIR'" EXIT

    # 解包文件
    extract_bundled_files "$BUNDLE_WORK_DIR"

    # 设置环境变量
    export SCRIPT_DIR="$BUNDLE_WORK_DIR"
    export CONFIG_FILE="$BUNDLE_WORK_DIR/config/default.conf"

    # 加载所有模块
    for module in args config utils detect firewall gfwlist dnslog monitor uninstall; do
        module_path="$BUNDLE_WORK_DIR/cmd/$module.sh"
        if [ -f "$module_path" ]; then
            source "$module_path"
        fi
    done
EOL

# 添加主脚本内容（去除shebang和模块加载部分）
echo -e "${BLUE}  集成主脚本逻辑...${NC}"
cat >> "$OUTPUT_FILE" << 'EOL'

    # 以下是主脚本的核心逻辑
EOL

# 提取主脚本的核心部分（跳过开头的加载部分）
tail -n +20 "$SCRIPT_DIR/zerotier-gateway.sh" | sed '/^source.*cmd\//d' >> "$OUTPUT_FILE"

# 添加执行入口
cat >> "$OUTPUT_FILE" << 'EOL'
}

# 执行主函数
main "$@"
EOL

echo -e "${GREEN}✓ 打包完成！${NC}"
echo -e "${BLUE}输出文件: $OUTPUT_FILE${NC}"
echo -e "${BLUE}文件大小: $(du -h "$OUTPUT_FILE" | cut -f1)${NC}"
echo
echo -e "${YELLOW}使用方法:${NC}"
echo -e "  chmod +x $OUTPUT_FILE"
echo -e "  sudo $OUTPUT_FILE [选项]"
echo
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
  mkdir -p "\$ZT_SCRIPT_DIR/cmd" "\$ZT_SCRIPT_DIR/templates" "\$ZT_SCRIPT_DIR/bin" "\$ZT_SCRIPT_DIR/scripts" "\$ZT_SCRIPT_DIR/logs" || {
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
