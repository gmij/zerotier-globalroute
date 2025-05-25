---
description: '创建新的配置模板文件'
mode: 'agent'
tools: ['codebase']
---

# 配置模板文件生成器

帮我为 ZeroTier 网关项目创建新的配置模板文件。

## 模板文件规范

### 文件位置和命名
- 模板文件存放在 `templates/` 目录
- 文件名格式：`功能名.扩展名.template`
- 例如：`nginx.conf.template`、`firewall.rules.template`

### 模板语法
- 使用变量占位符：`$VARIABLE_NAME` 或 `${VARIABLE_NAME}`
- 条件占位符：`#CONDITION_PLACEHOLDER#`
- 配置注释：使用目标文件格式的注释语法

### 变量规范
- 所有变量使用大写字母和下划线
- 网络相关：`ZT_INTERFACE`、`WAN_INTERFACE`、`ZT_NETWORK`
- 路径相关：`SCRIPT_DIR`、`LOG_FILE`、`CONFIG_DIR`
- 功能开关：`IPV6_ENABLED`、`GFWLIST_MODE`、`DNS_LOGGING`

## 常用模板类型

### 系统服务模板
- systemd 服务单元文件
- cron 任务配置
- NetworkManager dispatcher 脚本

### 网络配置模板
- iptables 规则集
- dnsmasq 配置
- 网络接口配置

### 应用配置模板
- Nginx/Apache 配置
- DNS 服务器配置
- 监控脚本配置

### 脚本模板
- 状态检查脚本
- 定时任务脚本
- 初始化脚本

## 模板生成要求

### 配置验证
- 包含配置参数验证
- 提供默认值设置
- 添加配置说明注释

### 错误处理
- 处理缺失变量的情况
- 提供配置错误提示
- 支持配置回滚

### 兼容性
- 支持不同系统版本
- 处理软件版本差异
- 提供兼容性说明

## 模板使用流程

### 模板处理步骤
1. 读取模板文件内容
2. 替换变量占位符
3. 处理条件性内容
4. 写入目标位置
5. 设置正确权限

### 集成到主脚本
- 在相关功能函数中调用模板
- 使用统一的模板处理函数
- 提供模板验证机制

### 示例代码结构
```bash
# 统一的模板处理函数
process_template() {
    local template_file="$1"
    local project_config="$2"  # 项目配置文件路径
    local system_config="$3"   # 系统配置文件路径（可选）

    if [ ! -f "$template_file" ]; then
        handle_error "模板文件不存在: $template_file"
    fi

    # 确保项目配置目录存在
    mkdir -p $(dirname "$project_config")

    # 处理模板变量替换
    local temp_content=$(cat "$template_file")

    # 替换基本变量
    temp_content="${temp_content//\$ZT_INTERFACE/$ZT_INTERFACE}"
    temp_content="${temp_content//\$WAN_INTERFACE/$WAN_INTERFACE}"
    temp_content="${temp_content//\$SCRIPT_DIR/$SCRIPT_DIR}"

    # 处理条件性内容
    if [ "$IPV6_ENABLED" = "1" ]; then
        temp_content="${temp_content//#IPV6_SETTINGS#/$IPV6_CONFIG}"
    else
        temp_content="${temp_content//#IPV6_SETTINGS#/}"
    fi

    # 生成项目配置文件
    echo "$temp_content" > "$project_config"
    log "INFO" "配置文件已生成: $project_config"

    # 如果需要，创建系统软链接
    if [ -n "$system_config" ]; then
        mkdir -p $(dirname "$system_config")
        ln -sf "$project_config" "$system_config" || {
            sudo ln -sf "$project_config" "$system_config" || {
                log "INFO" "使用复制代替软链接"
                cp -f "$project_config" "$system_config"
            }
        }
        log "INFO" "系统链接已创建: $system_config -> $project_config"
    fi
}

# 使用示例
TEMPLATE_FILE="$SCRIPT_DIR/templates/service.conf.template"
PROJECT_CONFIG="$SCRIPT_DIR/config/service.conf"
SYSTEM_CONFIG="/etc/zt-gateway/service.conf"

process_template "$TEMPLATE_FILE" "$PROJECT_CONFIG" "$SYSTEM_CONFIG"
```

### 配置文件集中管理
- **项目配置**：所有生成的配置文件优先保存在 `$SCRIPT_DIR/config/`
- **系统部署**：通过软链接将项目配置部署到系统目录
- **版本控制**：项目配置文件可纳入 Git 管理
- **迁移友好**：整个项目目录可直接迁移到其他服务器

### 模板中的路径变量
```bash
# 在模板中使用这些路径变量
SCRIPT_CONFIG_DIR="$SCRIPT_DIR/config"      # 项目配置目录
SCRIPT_LOG_DIR="$SCRIPT_DIR/logs"           # 项目日志目录
SYSTEM_CONFIG_DIR="/etc/zt-gateway"         # 系统配置目录
```

请告诉我你需要创建什么类型的配置模板，我将为你生成完整的模板文件和处理代码。
