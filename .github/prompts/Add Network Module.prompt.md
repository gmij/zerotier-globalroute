---
description: '为 ZeroTier 网关添加新的网络功能模块'
mode: 'agent'
tools: ['codebase']
---

# 新增网络功能模块

你的目标是为 ZeroTier 网关项目创建一个新的网络功能模块。

## 要求规范

### 文件结构
- 在 `cmd/` 目录下创建新的 `.sh` 文件
- 文件名格式：`功能名.sh`，如 `vpn.sh`、`loadbalance.sh`
- 在主脚本 `zerotier-gateway.sh` 中添加 `source` 加载语句

### 编码规范
- 使用项目统一的编码风格：[代码规范](../copilot-instructions.md)
- 函数命名：功能前缀 + 下划线 + 描述，如 `vpn_setup_tunnel`
- 变量命名：全大写，如 `VPN_SERVER_IP`
- 错误处理：使用 `handle_error "错误信息"` 函数
- 日志记录：使用 `log "级别" "消息"` 函数

### 必需函数
每个功能模块应包含以下标准函数：
1. `功能名_setup()` - 安装和配置功能
2. `功能名_start()` - 启动功能
3. `功能名_stop()` - 停止功能
4. `功能名_status()` - 检查功能状态
5. `功能名_cleanup()` - 清理和卸载功能

### 配置文件管理
- 所有配置文件统一创建在项目目录：`$SCRIPT_DIR/config/`
- 通过软链接部署到系统目录：`/etc/zt-gateway/`
- 配置变量添加到主配置文件：`$SCRIPT_DIR/config/zt-gateway.conf`
- 如需专用配置文件，命名格式：`$SCRIPT_DIR/config/功能名.conf`
- 如需模板文件，在 `templates/` 目录创建 `.template` 文件
- 使用标准软链接创建流程：
  ```bash
  # 项目配置文件
  PROJECT_CONFIG="$SCRIPT_DIR/config/功能名.conf"
  SYSTEM_CONFIG="/etc/zt-gateway/功能名.conf"

  # 创建配置内容
  cat > "$PROJECT_CONFIG" << EOL
  # 配置内容
  EOL

  # 创建软链接
  mkdir -p $(dirname "$SYSTEM_CONFIG")
  ln -sf "$PROJECT_CONFIG" "$SYSTEM_CONFIG" || {
      sudo ln -sf "$PROJECT_CONFIG" "$SYSTEM_CONFIG" || {
          log "INFO" "使用复制代替软链接"
          cp -f "$PROJECT_CONFIG" "$SYSTEM_CONFIG"
      }
  }
  ```

### 命令行参数
在主脚本的参数解析部分添加相关选项：
- 安装：`--install-功能名`
- 状态：`--功能名-status`
- 配置：`--功能名-config`

### 防火墙集成
如果需要修改防火墙规则：
- 在 `firewall.sh` 模块中添加相关函数
- 使用自定义 iptables 链，如 `ZT-VPN`
- 确保规则可以被 `cleanup_firewall` 函数清理

### 服务集成
如果需要创建 systemd 服务：
- 在 `templates/` 目录创建服务模板文件
- 使用 `systemctl` 命令管理服务
- 确保服务可以开机自启动

请提供功能描述，我将帮你生成完整的模块代码。
