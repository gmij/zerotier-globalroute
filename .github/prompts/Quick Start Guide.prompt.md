---
description: '快速开始指南和常用操作'
mode: 'agent'
tools: ['codebase']
---

# ZeroTier 网关快速开始

帮助新用户快速上手 ZeroTier 网关项目的开发和使用。

## 快速部署

### 基础安装
```bash
# 1. 克隆项目
git clone <repository-url>
cd zerotier-globalroute

# 2. 基本安装
chmod +x zerotier-gateway.sh
sudo ./zerotier-gateway.sh

# 3. 启用分流功能
sudo ./zerotier-gateway.sh --gfwlist

# 4. 查看状态
sudo ./zerotier-gateway.sh --status
```

### 打包部署
```bash
# 生成单文件部署包
./build.sh

# 在目标服务器上运行
sudo ./zerotier-gateway-bundle.sh
```

## 常用操作

### 配置管理
- 查看当前配置：`--status`
- 重启网关：`--restart`
- 更新配置：`--update`
- 备份规则：`--backup`

#### 配置文件位置
- **项目配置目录**：`$SCRIPT_DIR/config/` (主要配置存储)
- **系统配置目录**：`/etc/zt-gateway/` (软链接到项目配置)
- **日志目录**：`$SCRIPT_DIR/logs/` (项目日志)

#### 配置迁移
```bash
# 迁移整个配置到新服务器
scp -r /path/to/zerotier-globalroute/ user@newserver:/opt/
ssh user@newserver "cd /opt/zerotier-globalroute && sudo ./zerotier-gateway.sh --update"
```

### 分流功能
- 启用分流：`--gfwlist`
- 更新列表：`--update-gfwlist`
- 查看状态：`--gfwlist-status`
- 添加域名：`--add-domain example.com`
- 删除域名：`--remove-domain example.com`

### 监控诊断
- 测试连通性：`--test`
- 查看流量：`--stats`
- DNS 日志：`--show-dns-log`
- 网络状态：`/usr/local/bin/zt-status`

## 开发指南

### 项目结构理解
参考：[项目编码规范](../copilot-instructions.md)

```bash
zerotier-globalroute/
├── zerotier-gateway.sh          # 主脚本
├── build.sh                     # 打包脚本
├── cmd/                         # 功能模块
│   ├── detect.sh               # 接口检测
│   ├── firewall.sh             # 防火墙配置
│   ├── gfwlist.sh              # 分流功能
│   ├── monitor.sh              # 监控功能
│   ├── uninstall.sh            # 卸载功能
│   └── utils.sh                # 工具函数
├── templates/                   # 配置模板
└── config/                      # 配置文件
```

### 添加新功能
使用提示词：`/Add Network Module`

1. 在 `cmd/` 目录创建功能模块
2. 在主脚本中添加参数解析
3. 创建必要的配置模板
4. 添加测试和文档

### 代码规范检查
```bash
# 使用 shellcheck 检查脚本
shellcheck zerotier-gateway.sh
shellcheck cmd/*.sh

# 检查模板文件语法
bash -n templates/*.template
```

## 故障排除

### 常见问题
1. **接口检测失败**
   - 确认 ZeroTier 服务运行
   - 检查网络接口状态
   - 验证 zerotier-cli 命令

2. **防火墙规则问题**
   - 检查 iptables 服务状态
   - 验证规则是否正确加载
   - 查看系统日志

3. **连通性问题**
   - 使用 `--test` 进行诊断
   - 检查 IP 转发设置
   - 验证路由配置

### 调试模式
```bash
# 启用调试输出
sudo ./zerotier-gateway.sh --debug

# 查看详细日志
tail -f logs/zt-gateway.log
```

## 贡献指南

### 代码提交
1. 遵循项目编码规范
2. 添加适当的测试
3. 更新相关文档
4. 提交 Pull Request

### 文档更新
使用提示词：`/Documentation Generator`

### 安全审查
使用提示词：`/Security Review`

## 进阶配置

### 自定义网络环境
- 修改防火墙规则
- 调整网络参数
- 配置负载均衡
- 设置 QoS 策略

### 集成其他服务
- Nginx 代理配置
- DNS 服务器集成
- VPN 服务配置
- 监控系统集成

### 性能优化
使用提示词：`/Shell Script Optimization`

请选择你需要的操作类型，我将提供详细的指导和代码示例。
