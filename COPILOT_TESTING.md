# GitHub Copilot 配置测试指南

本文档提供了测试新创建的 GitHub Copilot 配置的指导。

## 配置状态验证

✅ **配置文件已创建完成**

- `.github/copilot-instructions.md` - 仓库级自定义指令
- `.github/prompts/` - 7个专用提示文件
- `.vscode/settings.json` - VS Code 工作区设置
- `COPILOT_SETUP.md` - 完整设置文档

## 测试建议

### 1. 重启 VS Code
确保新的配置生效：
```bash
# 关闭 VS Code 并重新打开项目
code .
```

### 2. 测试自定义指令
在任何文件中，尝试让 Copilot 生成代码，它应该自动遵循项目编码规范：

**测试示例：**
```bash
# 在新文件中输入以下注释，然后按 Tab 让 Copilot 补全：
# 创建一个检测 ZeroTier 接口的函数
```

**期望结果：**
- 函数名使用下划线分隔（如 `detect_zt_interface`）
- 变量使用大写命名（如 `ZT_INTERFACE`）
- 包含错误处理和日志记录
- 使用彩色输出变量

### 3. 测试专用提示文件

#### 3.1 网络模块开发
1. 在 VS Code 中按 `Ctrl+Shift+P`
2. 输入 "Copilot: Send to"
3. 选择 "Add Network Module" 提示
4. 输入需求描述

#### 3.2 Shell 脚本优化
1. 选择一段现有脚本代码
2. 使用 "Shell Script Optimization" 提示
3. 让 Copilot 提供优化建议

#### 3.3 网络故障排查
1. 描述网络问题
2. 使用 "Network Troubleshooting" 提示
3. 获取诊断和解决方案

### 4. 验证编码规范遵循

创建一个测试文件验证 Copilot 是否遵循规范：

**测试文件：** `test_copilot.sh`
```bash
#!/bin/bash
# 测试 Copilot 编码规范遵循情况

# 让 Copilot 补全以下函数：
# 1. 设置防火墙规则的函数
# 2. 检测网络接口的函数
# 3. 错误处理函数
```

**检查点：**
- [ ] 使用 `set -e` 错误处理
- [ ] 变量大写命名
- [ ] 函数小写下划线命名
- [ ] 包含日志记录 `log()` 函数
- [ ] 使用彩色输出变量
- [ ] 配置文件路径使用双引号

### 5. 测试特定功能提示

#### 配置模板生成
```bash
# 注释：为新的网络服务创建配置模板
# 让 Copilot 生成包含变量占位符的模板文件
```

#### 安全审查
```bash
# 选择防火墙相关代码
# 使用 "Security Review" 提示检查安全问题
```

#### 文档生成
```bash
# 选择函数代码
# 使用 "Documentation Generator" 提示生成文档
```

## 预期改进效果

配置生效后，您应该看到：

1. **代码一致性提升**
   - 变量命名统一
   - 函数结构规范
   - 错误处理标准化

2. **开发效率提升**
   - 减少手动格式调整
   - 自动包含项目特色功能
   - 快速生成符合规范的代码

3. **质量提升**
   - 自动包含安全检查
   - 遵循最佳实践
   - 减少常见错误

## 故障排除

### Copilot 未遵循自定义指令
1. 确认 `.github/copilot-instructions.md` 文件存在
2. 重启 VS Code
3. 检查 GitHub Copilot 扩展是否最新版本

### 提示文件未显示
1. 检查 `.vscode/settings.json` 中的配置
2. 确认 `github.copilot.editor.enablePromptFiles` 为 `true`
3. 重新加载窗口

### 效果不明显
1. 在提示中明确提及项目特点
2. 使用更具体的描述
3. 尝试不同的提示文件

## 团队协作

如果在团队中使用，建议：

1. **统一环境**
   - 所有成员使用相同的 VS Code 设置
   - 确保 Copilot 扩展版本一致

2. **培训和文档**
   - 分享 `COPILOT_SETUP.md` 设置指南
   - 组织团队培训会议
   - 建立最佳实践分享机制

3. **反馈和改进**
   - 收集团队使用反馈
   - 定期更新提示文件
   - 优化自定义指令

## 下一步

1. 按照上述步骤测试配置
2. 根据实际使用效果调整提示文件
3. 考虑添加更多项目特定的提示
4. 与团队成员分享配置和使用经验

---

**注意：** 如果发现任何问题或需要调整，请参考 `COPILOT_SETUP.md` 文档或重新运行配置脚本。
