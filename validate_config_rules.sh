#!/bin/bash
#
# GitHub Copilot 配置文件管理规则验证脚本
# 检查项目是否遵循集中化配置文件管理和软链接规则
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}GitHub Copilot 配置文件管理规则验证${NC}"
echo "================================================"

# 获取脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 检查计数器
total_checks=0
passed_checks=0
failed_checks=0

# 检查函数
check_rule() {
    local description="$1"
    local test_command="$2"

    total_checks=$((total_checks + 1))
    echo -n "检查: $description ... "

    if eval "$test_command"; then
        echo -e "${GREEN}✓${NC}"
        passed_checks=$((passed_checks + 1))
    else
        echo -e "${RED}✗${NC}"
        failed_checks=$((failed_checks + 1))
    fi
}

echo "1. GitHub Copilot 配置验证"
echo "----------------------------"

# 检查主要配置文件
check_rule "自定义指令文件存在" "[ -f '$SCRIPT_DIR/.github/copilot-instructions.md' ]"
check_rule "VS Code 设置文件存在" "[ -f '$SCRIPT_DIR/.vscode/settings.json' ]"
check_rule "配置管理提示文件存在" "[ -f '$SCRIPT_DIR/.github/prompts/Configuration Management.prompt.md' ]"

# 检查自定义指令中的新规则
if [ -f "$SCRIPT_DIR/.github/copilot-instructions.md" ]; then
    check_rule "包含软链接管理原则" "grep -q '软链接管理原则' '$SCRIPT_DIR/.github/copilot-instructions.md'"
    check_rule "包含配置文件集中管理规则" "grep -q 'config/' '$SCRIPT_DIR/.github/copilot-instructions.md'"
    check_rule "包含项目目录配置路径" "grep -q 'SCRIPT_DIR/config' '$SCRIPT_DIR/.github/copilot-instructions.md'"
    check_rule "包含软链接创建流程" "grep -q 'ln -sf' '$SCRIPT_DIR/.github/copilot-instructions.md'"
fi

echo ""
echo "2. 项目结构验证"
echo "----------------------------"

# 检查目录结构
check_rule "config 目录存在" "[ -d '$SCRIPT_DIR/config' ]"
check_rule "templates 目录存在" "[ -d '$SCRIPT_DIR/templates' ]"
check_rule "cmd 目录存在" "[ -d '$SCRIPT_DIR/cmd' ]"
check_rule "logs 目录存在或可创建" "[ -d '$SCRIPT_DIR/logs' ] || mkdir -p '$SCRIPT_DIR/logs'"

echo ""
echo "3. 现有代码软链接使用检查"
echo "----------------------------"

# 检查现有脚本中是否使用了软链接模式
if [ -f "$SCRIPT_DIR/cmd/gfwlist.sh" ]; then
    check_rule "GFW List 脚本使用软链接" "grep -q 'ln -sf.*SCRIPT.*SYSTEM' '$SCRIPT_DIR/cmd/gfwlist.sh'"
    check_rule "GFW List 脚本有配置集中化" "grep -q 'SCRIPT_CONFIG_DIR' '$SCRIPT_DIR/cmd/gfwlist.sh'"
fi

if [ -f "$SCRIPT_DIR/zerotier-gateway.sh" ]; then
    check_rule "主脚本定义了 SCRIPT_DIR" "grep -q 'SCRIPT_DIR.*cd.*dirname' '$SCRIPT_DIR/zerotier-gateway.sh'"
fi

echo ""
echo "4. 提示文件配置管理规则检查"
echo "----------------------------"

# 检查提示文件是否包含新的配置管理规则
if [ -f "$SCRIPT_DIR/.github/prompts/Add Network Module.prompt.md" ]; then
    check_rule "网络模块提示包含配置管理规则" "grep -q 'SCRIPT_DIR/config' '$SCRIPT_DIR/.github/prompts/Add Network Module.prompt.md'"
    check_rule "网络模块提示包含软链接示例" "grep -q 'ln -sf' '$SCRIPT_DIR/.github/prompts/Add Network Module.prompt.md'"
fi

if [ -f "$SCRIPT_DIR/.github/prompts/Configuration Template.prompt.md" ]; then
    check_rule "配置模板提示包含集中管理" "grep -q 'project_config' '$SCRIPT_DIR/.github/prompts/Configuration Template.prompt.md'"
    check_rule "配置模板提示包含软链接处理" "grep -q 'system_config' '$SCRIPT_DIR/.github/prompts/Configuration Template.prompt.md'"
fi

echo ""
echo "5. 配置文件管理最佳实践检查"
echo "----------------------------"

# 检查是否有配置文件直接写入系统目录的情况（应该避免）
if find "$SCRIPT_DIR" -name "*.sh" -type f -exec grep -l ">/etc/" {} \; 2>/dev/null | head -1 >/dev/null; then
    echo -e "${YELLOW}建议: 发现直接写入 /etc/ 目录的代码，建议改为先写入项目目录再软链接${NC}"
    echo "文件列表:"
    find "$SCRIPT_DIR" -name "*.sh" -type f -exec grep -l ">/etc/" {} \; 2>/dev/null | head -5
fi

# 检查是否有硬编码的配置路径
if find "$SCRIPT_DIR" -name "*.sh" -type f -exec grep -l "/etc/zt-gateway" {} \; 2>/dev/null | head -1 >/dev/null; then
    config_files=$(find "$SCRIPT_DIR" -name "*.sh" -type f -exec grep -l "/etc/zt-gateway" {} \; 2>/dev/null | wc -l)
    check_rule "使用了系统配置路径（可能需要软链接支持）" "[ $config_files -gt 0 ]"
fi

echo ""
echo "6. 建议改进项"
echo "----------------------------"

# 检查项目配置文件使用情况
if [ ! -f "$SCRIPT_DIR/config/.keep" ] && [ -d "$SCRIPT_DIR/config" ]; then
    echo -e "${YELLOW}建议: 在 config/ 目录创建 .keep 文件以确保目录被 Git 跟踪${NC}"
fi

# 检查是否有软链接创建的统一函数
if ! grep -q "create.*link\|link.*create" "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR/cmd"/*.sh 2>/dev/null; then
    echo -e "${YELLOW}建议: 创建统一的软链接创建函数以减少重复代码${NC}"
fi

echo ""
echo "================================================"
echo -e "${BLUE}验证结果摘要${NC}"
echo "================================================"
echo -e "总检查项: ${BLUE}$total_checks${NC}"
echo -e "通过检查: ${GREEN}$passed_checks${NC}"
echo -e "失败检查: ${RED}$failed_checks${NC}"

if [ $failed_checks -eq 0 ]; then
    echo -e "${GREEN}✓ 配置文件管理规则验证通过！${NC}"
    echo ""
    echo "您的项目已正确配置了 GitHub Copilot 自定义指令，"
    echo "并遵循了配置文件集中化管理和软链接部署的最佳实践。"
else
    echo -e "${YELLOW}⚠ 发现 $failed_checks 个需要改进的项目${NC}"
    echo ""
    echo "建议参考以下文档完善配置："
    echo "- COPILOT_SETUP.md - GitHub Copilot 设置指南"
    echo "- .github/prompts/Configuration Management.prompt.md - 配置管理规则"
fi

echo ""
echo "下一步："
echo "1. 重启 VS Code 以应用新配置"
echo "2. 测试 Copilot 是否遵循新的配置管理规则"
echo "3. 在新代码中使用软链接和集中化配置管理"

exit $failed_checks
