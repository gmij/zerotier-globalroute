#!/bin/bash
#
# GitHub Copilot 配置验证脚本
# 检查所有必要的文件是否正确创建
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}GitHub Copilot 配置验证${NC}"
echo "================================"

# 检查目录结构
check_directory() {
    local dir="$1"
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} 目录存在: $dir"
        return 0
    else
        echo -e "${RED}✗${NC} 目录缺失: $dir"
        return 1
    fi
}

# 检查文件
check_file() {
    local file="$1"
    local description="$2"
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $description: $file"
        return 0
    else
        echo -e "${RED}✗${NC} $description: $file"
        return 1
    fi
}

# 检查文件内容
check_file_content() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        return 1
    fi
}

echo -e "\n${YELLOW}1. 检查目录结构${NC}"
check_directory ".github"
check_directory ".github/prompts"
check_directory ".vscode"

echo -e "\n${YELLOW}2. 检查主要配置文件${NC}"
check_file ".github/copilot-instructions.md" "仓库自定义指令文件"
check_file ".vscode/settings.json" "VS Code 工作区设置"
check_file ".github/README.md" "配置说明文档"

echo -e "\n${YELLOW}3. 检查提示词文件${NC}"
prompt_files=(
    "Add Network Module.prompt.md:新增网络模块"
    "Shell Script Optimization.prompt.md:脚本优化"
    "Network Troubleshooting.prompt.md:网络故障诊断"
    "Configuration Template.prompt.md:配置模板生成"
    "Security Review.prompt.md:安全审查"
    "Documentation Generator.prompt.md:文档生成"
    "Quick Start Guide.prompt.md:快速开始指南"
)

for item in "${prompt_files[@]}"; do
    file="${item%%:*}"
    desc="${item##*:}"
    check_file ".github/prompts/$file" "$desc"
done

echo -e "\n${YELLOW}4. 检查配置内容${NC}"
if [ -f ".vscode/settings.json" ]; then
    check_file_content ".vscode/settings.json" "chat.promptFiles.*true" "提示词文件功能已启用"
    check_file_content ".vscode/settings.json" "github.copilot.chat.codeGeneration.useInstructionFiles.*true" "自定义指令功能已启用"
fi

if [ -f ".github/copilot-instructions.md" ]; then
    check_file_content ".github/copilot-instructions.md" "ZeroTier.*全局路由网关" "自定义指令包含项目信息"
    check_file_content ".github/copilot-instructions.md" "Shell.*脚本规范" "包含编码规范"
fi

echo -e "\n${YELLOW}5. 检查提示词文件格式${NC}"
for item in "${prompt_files[@]}"; do
    file="${item%%:*}"
    if [ -f ".github/prompts/$file" ]; then
        check_file_content ".github/prompts/$file" "^---" "Front Matter 格式正确: $file"
        check_file_content ".github/prompts/$file" "description:" "包含描述信息: $file"
    fi
done

echo -e "\n${YELLOW}6. 生成统计信息${NC}"
total_prompts=$(ls -1 .github/prompts/*.prompt.md 2>/dev/null | wc -l)
echo -e "${BLUE}总计提示词文件:${NC} $total_prompts 个"

if [ -f ".github/copilot-instructions.md" ]; then
    lines=$(wc -l < ".github/copilot-instructions.md")
    echo -e "${BLUE}自定义指令文件行数:${NC} $lines 行"
fi

echo -e "\n${YELLOW}7. 使用建议${NC}"
echo "1. 重新加载 VS Code 工作区以应用设置"
echo "2. 在 Copilot Chat 中测试提示词文件"
echo "3. 检查 Copilot 回复的引用列表"
echo "4. 根据需要自定义提示词内容"

echo -e "\n${GREEN}配置验证完成！${NC}"
echo "详细使用说明请查看: COPILOT_SETUP.md"
