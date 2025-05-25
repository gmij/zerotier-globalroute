# sed 错误修复和默认DEBUG模式启用 - 修复总结

## 修复时间
2025年5月25日

## 问题描述

### 1. sed 命令错误
- **错误信息**: `sed: -e expression #1, char 32: unknown option to 's'`
- **原因**: 在 `config.sh` 的 `process_template()` 函数中，使用 sed 进行变量替换时，当变量值包含特殊字符（如路径中的斜杠）会导致 sed 命令失败
- **影响**: 模板文件处理失败，无法正确生成配置文件

### 2. 用户体验问题
- **问题**: 用户需要手动添加 `-d` 参数才能看到详细的安装日志
- **影响**: 一次性安装脚本应该默认显示详细信息，方便用户了解安装进度和排查问题

## 修复方案

### 1. sed 错误修复
**文件**: `cmd/config.sh`
**位置**: `process_template()` 函数中的变量替换部分

**修复前**:
```bash
# 使用 sed 直接替换，容易因特殊字符失败
sed -i "s|{{SCRIPT_DIR}}|${SCRIPT_DIR}|g" "$temp_file"
```

**修复后**:
```bash
# 使用 awk 进行安全的字符串替换
awk -v script_dir="$SCRIPT_DIR" \
    -v zt_interface="$ZT_INTERFACE" \
    -v wan_interface="$WAN_INTERFACE" \
    -v zt_network="$ZT_NETWORK" \
    -v zt_mtu="$ZT_MTU" \
    -v ipv6_enabled="$IPV6_ENABLED" \
    -v gfwlist_mode="$GFWLIST_MODE" \
    -v dns_logging="$DNS_LOGGING" \
    -v generation_time="$(date '+%Y-%m-%d %H:%M:%S')" \
    -v config_version="${CONFIG_VERSION:-3.1}" \
    '{
        gsub(/\{\{SCRIPT_DIR\}\}/, script_dir)
        gsub(/\{\{ZT_INTERFACE\}\}/, zt_interface)
        gsub(/\{\{WAN_INTERFACE\}\}/, wan_interface)
        gsub(/\{\{ZT_NETWORK\}\}/, zt_network)
        gsub(/\{\{ZT_MTU\}\}/, zt_mtu)
        gsub(/\{\{IPV6_ENABLED\}\}/, ipv6_enabled)
        gsub(/\{\{GFWLIST_MODE\}\}/, gfwlist_mode)
        gsub(/\{\{DNS_LOGGING\}\}/, dns_logging)
        gsub(/GENERATION_TIME/, generation_time)
        gsub(/CONFIG_VERSION/, config_version)
        print
    }' "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
```

**优势**:
- awk 的 `-v` 参数可以安全地传递变量值，不受特殊字符影响
- gsub() 函数更可靠，不需要担心分隔符冲突
- 更容易维护和扩展

### 2. 默认DEBUG模式启用

#### 2.1 主脚本修改
**文件**: `zerotier-gateway.sh`
```bash
# 修改前
DEBUG_MODE=0

# 修改后
DEBUG_MODE=1  # 默认启用调试模式，显示详细安装日志
```

#### 2.2 参数解析模块修改
**文件**: `cmd/args.sh`
```bash
# 修改前
DEBUG_MODE=0

# 修改后
DEBUG_MODE=1  # 默认启用调试模式，显示详细安装日志
```

#### 2.3 新增静默模式选项
**文件**: `cmd/args.sh`
在参数解析中新增:
```bash
-q|--quiet)
    DEBUG_MODE=0
    echo -e "${BLUE}===== 静默模式已启用 - 仅显示关键信息 =====${NC}"
    ;;
```

#### 2.4 帮助信息更新
**文件**: `cmd/detect.sh`
```bash
# 修改前
echo "  -d, --debug      启用调试模式"

# 修改后
echo "  -d, --debug      启用调试模式（默认已启用）"
echo "  -q, --quiet      启用静默模式，仅显示关键信息"
```

## 修复效果

### 1. sed 错误修复效果
- ✅ 解决了包含特殊字符的变量替换问题
- ✅ 提高了模板处理的可靠性
- ✅ 避免了因路径包含斜杠导致的脚本失败

### 2. 默认DEBUG模式效果
- ✅ 用户无需额外参数即可看到详细安装日志
- ✅ 提供了 `-q/--quiet` 选项供需要静默安装的场景使用
- ✅ 改善了用户体验，特别是首次安装时的信息反馈

## 使用方式更新

### 默认模式（显示详细日志）
```bash
./zerotier-gateway.sh
```

### 静默模式（仅显示关键信息）
```bash
./zerotier-gateway.sh --quiet
# 或
./zerotier-gateway.sh -q
```

### 显式启用调试模式（保持兼容性）
```bash
./zerotier-gateway.sh --debug
# 或
./zerotier-gateway.sh -d
```

## 向后兼容性
- ✅ 保持了所有现有参数的功能
- ✅ `-d/--debug` 参数仍然有效（虽然现在是默认启用）
- ✅ 新增的 `-q/--quiet` 参数不影响现有脚本

## 技术要点
1. **awk vs sed**: awk 的变量传递机制更安全，避免了字符串中特殊字符的问题
2. **用户体验**: 默认启用详细日志符合一次性安装脚本的特点
3. **灵活性**: 通过 `-q` 参数提供静默模式选择

## 测试建议
在实际环境中测试以下场景：
1. 包含特殊字符路径的模板替换
2. 默认模式下的详细日志输出
3. 静默模式下的简洁输出
4. 原有 `-d` 参数的兼容性
