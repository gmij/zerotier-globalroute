# ZeroTier Gateway Copilot 配置说明

本目录包含了针对 ZeroTier 全局路由网关项目的 GitHub Copilot 自定义配置文件。

## 文件结构

```
.github/
├── copilot-instructions.md          # 仓库级别的自定义指令
└── prompts/                         # 提示词文件目录
    ├── Add Network Module.prompt.md      # 新增网络功能模块
    ├── Shell Script Optimization.prompt.md  # Shell脚本优化
    ├── Network Troubleshooting.prompt.md    # 网络故障诊断
    ├── Configuration Template.prompt.md     # 配置模板生成
    ├── Security Review.prompt.md           # 安全审查
    └── Documentation Generator.prompt.md   # 文档生成

.vscode/
└── settings.json                    # VS Code 工作区设置
```

## 使用方法

### 1. 启用功能

确保在 VS Code 中启用了以下设置：
- `chat.promptFiles`: true
- `github.copilot.chat.codeGeneration.useInstructionFiles`: true

### 2. 使用仓库自定义指令

仓库自定义指令会自动应用到所有 Copilot Chat 对话中，无需手动操作。

### 3. 使用提示词文件

在 Copilot Chat 中：
- 点击 "Attach context" 图标
- 选择 "Prompt..."
- 选择需要的提示词文件

或者在聊天框中输入：
```
/Add Network Module
/Shell Script Optimization
/Network Troubleshooting
/Configuration Template
/Security Review
/Documentation Generator
```

## 提示词文件说明

### Add Network Module
用于为项目添加新的网络功能模块，会自动生成符合项目规范的代码结构。

### Shell Script Optimization
优化现有 Shell 脚本的性能和可靠性，提供最佳实践建议。

### Network Troubleshooting
诊断和解决网络连通性问题，提供系统化的故障排除流程。

### Configuration Template
生成新的配置模板文件，确保符合项目的模板化设计模式。

### Security Review
进行安全审查和加固建议，涵盖网络、系统和代码安全。

### Documentation Generator
生成和更新项目文档，包括 README、API 文档和用户手册。

## 项目编码规范

### Shell 脚本规范
- 变量命名：全大写，下划线分隔 (`ZT_INTERFACE`)
- 函数命名：小写，下划线分隔 (`setup_firewall`)
- 日志格式：`log "级别" "消息"`
- 错误处理：`handle_error "错误信息"`

### 目录结构约定
- `cmd/`: 功能模块
- `templates/`: 配置模板
- `logs/`: 日志文件
- `config/`: 配置文件

### 网络配置特点
- 优先使用 `ip` 命令
- 自定义 iptables 链管理
- 模块化防火墙规则
- 支持 IPv6 和分流功能

## 自定义配置

如需添加更多提示词文件或修改现有配置：

1. 在 `.github/prompts/` 目录下创建新的 `.prompt.md` 文件
2. 使用 Front Matter 语法定义元数据
3. 更新此说明文件

## 注意事项

- 提示词文件使用实验性功能，可能会有变化
- 确保 VS Code 和 GitHub Copilot 扩展为最新版本
- 如遇问题，可尝试重启 VS Code 或重新加载工作区
