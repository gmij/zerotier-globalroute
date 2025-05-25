---
applyTo: "**/*.sh"
---
# Shell 脚本特定指令

## 编码规范
- 使用 `#!/bin/bash` 作为 shebang
- 变量名使用大写，如 `ZT_INTERFACE`、`CONFIG_FILE`
- 函数名使用下划线分隔的小写，如 `setup_firewall`、`detect_interface`
- 文件路径使用双引号包围：`"$CONFIG_FILE"`

## 日志和输出
- 使用统一的日志函数：`log "INFO" "消息"`
- 日志级别：INFO、WARN、ERROR、DEBUG
- 彩色输出：`echo -e "${GREEN}成功${NC}"`
- 错误处理：`handle_error "错误信息"`

## 配置文件管理
- 配置文件集中管理在 `$SCRIPT_DIR/config/`
- 使用软链接部署：`ln -sf "$source" "$target"`
- 失败时尝试：`sudo ln -sf` 然后 `cp -f`
- 模板文件后缀：`.template`

## 网络和防火墙
- 优先使用 `ip` 命令而非 `ifconfig`
- 防火墙规则使用自定义链：`ZT-IN`、`ZT-FWD`
- 自动检测网络接口
- 支持 IPv6 配置（可选）

## 对话记录管理
- 每次 GitHub Copilot 对话的修改记录存放在 `vibe.history/` 目录
- 记录文件命名格式：`YYYY-MM-DD_HH-MM-SS_conversation.md`
- 每个记录包含：对话主题、用户需求、AI 响应、修改文件列表、修改小结
- 使用 `cmd/conversation.sh` 模块管理对话记录
- 模板文件：`templates/conversation-record.md.template`
