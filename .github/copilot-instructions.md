# ZeroTier 全局路由网关项目 - GitHub Copilot 自定义指令

我们的项目是一个基于 Shell/Bash 脚本的 ZeroTier 全局路由网关工具，专门为 CentOS 系统设计。在生成代码或提供建议时，请遵循以下规范：

## 技术栈和工具

我们主要使用 Shell/Bash 脚本编写，配合以下技术：
- iptables 用于防火墙规则配置
- systemd 用于服务管理
- ZeroTier 网络虚拟化
- ipset 用于 IP 地址集合管理
- dnsmasq 用于 DNS 解析和分流
- NetworkManager 用于网络接口管理

## 编码规范

### Shell 脚本规范
- 始终在脚本开头使用 `#!/bin/bash`
- 使用 `set -e` 在适当的地方处理错误
- 所有变量使用大写命名，如 `ZT_INTERFACE`、`WAN_INTERFACE`
- 函数名使用下划线分隔的小写，如 `setup_firewall`、`detect_zt_interface`
- 文件路径使用双引号包围，如 `"$CONFIG_FILE"`

### 日志和输出规范
- 使用统一的日志函数 `log()` 记录信息，格式为：`log "级别" "消息"`
- 日志级别包括：INFO、WARN、ERROR、DEBUG
- 使用彩色输出变量：`$GREEN`、`$YELLOW`、`$RED`、`$BLUE`、`$NC`
- 错误处理使用 `handle_error "错误信息"` 函数
- 输出格式：`echo -e "${GREEN}成功信息${NC}"`

### 配置文件管理
- 所有配置文件统一集中管理在项目目录下的对应子目录（config/, templates/, cmd/）
- 通过软链接 (`ln -sf`) 部署到系统目标位置，方便版本控制和集中管理
- 配置文件层次结构：
  - 项目源文件：`$SCRIPT_DIR/config/` （主管理位置）
  - 系统链接：`/etc/zt-gateway/` （软链接到项目文件）
- 使用模板文件（`.template` 后缀）生成实际配置
- 配置变量格式：`VARIABLE_NAME="value"`
- 在脚本中使用 `source "$CONFIG_FILE"` 加载配置
- 软链接创建模式：先尝试 `ln -sf`，失败时使用 `sudo ln -sf`，最后备用 `cp -f`

### 目录结构约定
- 主脚本：`zerotier-gateway.sh`
- 功能模块：`cmd/` 目录下的 `.sh` 文件
- 配置模板：`templates/` 目录下的 `.template` 文件
- 实际配置：`config/` 目录下的配置文件（项目内集中管理）
- 系统软链接：通过软链接部署到 `/etc/zt-gateway/` 等系统位置
- 日志文件：统一存放在 `logs/` 目录
- 便携脚本：`scripts/` 目录下的辅助脚本

### 软链接管理原则
- 优先使用项目目录内的文件作为主要配置源
- 系统目录中的配置文件通过软链接指向项目文件
- 实现配置集中化管理，便于版本控制和迁移
- 创建软链接的标准流程：
  1. 确保目标目录存在：`mkdir -p $(dirname "$target")`
  2. 尝试创建软链接：`ln -sf "$source" "$target"`
  3. 失败时使用 sudo：`sudo ln -sf "$source" "$target"`
  4. 最后备用复制：`cp -f "$source" "$target"`

## 功能模块设计

### 模块化原则
- 每个功能模块独立为一个文件，如 `firewall.sh`、`monitor.sh`
- 使用 `source` 命令加载模块
- 模块内函数名以模块功能为前缀

### 网络配置特点
- 优先自动检测网络接口
- 支持多 ZeroTier 接口选择
- 使用 `ip` 命令而非 `ifconfig`
- 防火墙规则使用自定义链管理（如 `ZT-IN`、`ZT-FWD`）

### 错误处理和恢复
- 提供配置备份功能
- 支持重启和更新模式
- 包含卸载功能清理配置

## 项目特色功能

### GFW List 分流
- 支持基于域名列表的智能分流
- 使用 ipset 和 dnsmasq 实现
- 配置变量：`GFWLIST_MODE`

### DNS 日志记录
- 可选的 DNS 查询日志功能
- 日志文件：`zt-dns-queries.log`
- 配置变量：`DNS_LOGGING`

### IPv6 支持
- 可选的 IPv6 转发支持
- 配置变量：`IPV6_ENABLED`

## 部署和打包

我们使用 `build.sh` 脚本创建单文件打包版本，将所有模块和模板整合为一个可执行脚本。生成代码时考虑便携性和易部署性。

## 注释和文档

- 每个函数前添加简短说明注释
- 重要的配置步骤添加解释性注释
- 使用中文注释说明业务逻辑
- README 文档保持最新的使用说明

## 兼容性要求

- 目标系统：CentOS 7/8
- 确保脚本在不同环境下的兼容性
- 优雅处理依赖包缺失的情况
- 提供清晰的错误信息和解决建议

当我询问关于网络配置、防火墙规则、Shell 脚本优化等问题时，请基于这些约定提供建议和代码示例。
