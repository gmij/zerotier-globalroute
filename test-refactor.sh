#!/bin/bash
#
# ZeroTier 网关重构测试脚本
#

# 设置脚本目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 测试结果
TEST_PASS=0
TEST_FAIL=0

# 测试函数
test_case() {
    local name="$1"
    local command="$2"

    echo -n "测试 $name ... "

    if eval "$command" >/dev/null 2>&1; then
        echo "通过"
        ((TEST_PASS++))
    else
        echo "失败"
        ((TEST_FAIL++))
    fi
}

echo "=== ZeroTier 网关重构测试 ==="
echo

# 测试配置文件
echo "1. 配置文件测试"
test_case "默认配置文件" "[ -f '$SCRIPT_DIR/config/default.conf' ]"
test_case "配置文件语法" "bash -n '$SCRIPT_DIR/config/default.conf'"

# 测试模块文件
echo -e "\n2. 模块文件测试"
for module in args config utils detect firewall gfwlist dnslog monitor uninstall; do
    test_case "$module 模块语法" "bash -n '$SCRIPT_DIR/cmd/$module.sh'"
done

# 测试主脚本
echo -e "\n3. 主脚本测试"
test_case "主脚本语法" "bash -n '$SCRIPT_DIR/zerotier-gateway.sh'"

# 测试模板文件
echo -e "\n4. 模板文件测试"
for template in templates/*.template; do
    if [ -f "$template" ]; then
        name=$(basename "$template" .template)
        test_case "$name 模板" "[ -f '$template' ]"
    fi
done

# 测试配置加载功能
echo -e "\n5. 功能测试"
test_case "配置加载" "source '$SCRIPT_DIR/cmd/config.sh' && load_config '$SCRIPT_DIR/config/default.conf'"
test_case "工具函数" "source '$SCRIPT_DIR/cmd/utils.sh' && declare -f log >/dev/null"
test_case "参数解析" "source '$SCRIPT_DIR/cmd/args.sh' && declare -f parse_arguments >/dev/null"

# 显示测试结果
echo -e "\n=== 测试结果 ==="
echo "通过: $TEST_PASS"
echo "失败: $TEST_FAIL"
echo "总计: $((TEST_PASS + TEST_FAIL))"

if [ $TEST_FAIL -eq 0 ]; then
    echo -e "\n✅ 所有测试通过！重构成功。"
    exit 0
else
    echo -e "\n❌ 有 $TEST_FAIL 个测试失败，请检查代码。"
    exit 1
fi
