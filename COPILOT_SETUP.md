# GitHub Copilot 配置使用指南

## 🎉 配置完成

您的ZeroTier全局路由网关项目的GitHub Copilot自定义配置已经成功创建！以下是详细的使用说明：

## 📁 已创建的文件

### 1. 仓库自定义指令
- **文件**: `.github/copilot-instructions.md`
- **功能**: 自动应用到所有Copilot Chat对话中
- **内容**: 项目编码规范、技术栈、命名约定等

### 2. 提示词文件（7个）
位于 `.github/prompts/` 目录：
- `Add Network Module.prompt.md` - 新增网络功能模块
- `Shell Script Optimization.prompt.md` - Shell脚本优化
- `Network Troubleshooting.prompt.md` - 网络故障诊断
- `Configuration Template.prompt.md` - 配置模板生成
- `Security Review.prompt.md` - 安全审查和加固
- `Documentation Generator.prompt.md` - 文档生成和更新
- `Quick Start Guide.prompt.md` - 快速开始指南

### 3. VS Code 工作区设置
- **文件**: `.vscode/settings.json`
- **功能**: 启用提示词文件和自定义指令功能

## 🚀 使用方法

### 启用功能（重要）
1. 确保VS Code和GitHub Copilot扩展为最新版本
2. 重新加载VS Code工作区（Ctrl+Shift+P → "Developer: Reload Window"）
3. 检查设置中的以下选项已启用：
   - `Chat: Prompt Files` ✅
   - `Github Copilot Chat Code Generation: Use Instruction Files` ✅

### 使用仓库自定义指令
- 自动生效，无需手动操作
- 在任何Copilot Chat对话中都会应用项目规范

### 使用提示词文件
**方法1：通过界面**
1. 打开Copilot Chat面板
2. 点击"Attach context"图标（📎）
3. 选择"Prompt..."
4. 选择需要的提示词文件

**方法2：通过命令**
在聊天框中直接输入：
```
/Add Network Module
/Shell Script Optimization
/Network Troubleshooting
/Configuration Template
/Security Review
/Documentation Generator
/Quick Start Guide
```

## 🧪 测试配置

### 测试1：验证自定义指令
在Copilot Chat中输入：
```
为这个项目创建一个新的Shell函数来检测网络状态
```
应该能看到生成的代码遵循项目规范（大写变量名、log函数等）

### 测试2：使用提示词文件
在Copilot Chat中输入：
```
/Shell Script Optimization
```
然后选择项目中的任意Shell脚本进行优化

### 测试3：验证引用显示
在Copilot生成的回复中，应该能看到引用列表包含：
- `.github/copilot-instructions.md`
- 相关的提示词文件

## 💡 使用场景示例

### 场景1：添加新功能
```
/Add Network Module

我想添加一个VPN隧道管理功能
```

### 场景2：优化现有代码
选中某个shell脚本中的函数，然后：
```
/Shell Script Optimization
```

### 场景3：故障排除
```
/Network Troubleshooting

ZeroTier接口无法获取IP地址，网关无法正常工作
```

### 场景4：安全审查
```
/Security Review

请审查防火墙配置的安全性
```

### 场景5：生成文档
```
/Documentation Generator

为新增的VPN功能生成用户文档
```

## 🔧 故障排除

### 如果提示词文件不显示
1. 检查文件路径是否正确
2. 确认VS Code设置中`chat.promptFiles`为true
3. 重启VS Code
4. 检查文件扩展名是否为`.prompt.md`

### 如果自定义指令不生效
1. 确认文件位于`.github/copilot-instructions.md`
2. 检查VS Code设置中相关选项已启用
3. 查看Copilot Chat回复的引用列表

### 获取更多帮助
- 查看`.github/README.md`了解详细说明
- 参考VS Code Copilot文档
- 检查GitHub Copilot状态

## 🎯 下一步建议

1. **测试所有提示词文件**：确保它们按预期工作
2. **根据需要自定义**：修改提示词内容以更好适应项目需求
3. **添加更多提示词**：为特定任务创建专门的提示词文件
4. **分享给团队**：确保团队成员了解如何使用这些配置

享受更智能的编程体验！🚀
