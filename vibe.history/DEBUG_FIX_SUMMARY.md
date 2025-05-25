# ZeroTier 网关调试模式接口检测修复

## 问题描述

在调试模式 (`-d`) 下运行 ZeroTier 网关脚本时，`detect_zt_interface()` 函数返回的结果包含了大量调试信息，而不是纯净的接口名称。这导致接口验证失败。

### 错误表现
```
[INFO] 使用 ZeroTier 接口: [DEBUG]开始检测ZeroTier接口...[DEBUG]方法1：检查网络接口名称...
[ERROR] ZeroTier 接口 '[DEBUG]开始检测ZeroTier接口...' 不存在，请检查接口名称是否正确
```

## 根本原因

1. **日志函数污染问题**：在调试模式下，`log()` 函数的输出混合到了函数的返回值中
2. **输出重定向不当**：虽然尝试使用 `>&2` 重定向，但在某些情况下仍然无效
3. **返回值处理不严格**：主脚本没有对返回值进行充分的清理和验证

## 修复方案

### 1. 优化 detect.sh 中的接口检测函数

**文件**: `cmd/detect.sh`

- 将所有调试信息使用大括号分组并重定向到 stderr：`{ log "DEBUG" "信息"; } >&2`
- 确保函数只在 stdout 输出纯净的接口名称
- 添加 `/dev/null` 重定向避免命令错误输出

### 2. 加强主脚本中的返回值处理

**文件**: `zerotier-gateway.sh`

- 使用临时变量接收函数返回值
- 添加 `2>/dev/null` 重定向确保调试信息不污染结果
- 使用正则表达式过滤，只保留有效的接口名：`grep -o '^[a-zA-Z0-9]*$\|^multiple$'`

### 3. 修复内容详述

#### `detect_zt_interface()` 函数修复：
```bash
# 修复前：调试信息直接输出到 stdout
log "DEBUG" "开始检测 ZeroTier 接口..."

# 修复后：调试信息重定向到 stderr
if [ "$DEBUG_MODE" = "1" ]; then
    {
        log "DEBUG" "开始检测 ZeroTier 接口..."
        log "DEBUG" "方法1：检查网络接口名称..."
    } >&2
fi
```

#### 主脚本调用修复：
```bash
# 修复前：直接接收可能污染的返回值
ZT_INTERFACE=$(detect_zt_interface)

# 修复后：使用临时变量和过滤
local detected_zt_interface
detected_zt_interface=$(detect_zt_interface 2>/dev/null)
ZT_INTERFACE=$(echo "$detected_zt_interface" | grep -o '^[a-zA-Z0-9]*$\|^multiple$' | head -1)
```

## 测试验证

修复后的结果应该是：
- ZeroTier 接口检测返回干净的接口名（如 `ztzxudepi2`）或 `multiple`
- WAN 接口检测返回干净的接口名（如 `eth0`）
- 调试信息正常显示但不污染返回值

## 兼容性说明

- 修复保持向后兼容性
- 非调试模式运行不受影响
- 所有原有功能保持正常

---
修复时间：2025年5月25日
修复版本：v3.1
