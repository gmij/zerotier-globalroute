---
description: '进行安全审查和加固'
mode: 'agent'
tools: ['codebase']
---

# 网络安全审查和加固

对 ZeroTier 网关进行全面的安全审查和加固建议。

## 安全审查要点

### 网络安全
1. **防火墙规则审查**
   - 检查 iptables 规则的最小权限原则
   - 验证默认拒绝策略
   - 审查端口开放的必要性
   - 确保 NAT 规则的安全性

2. **网络隔离**
   - ZeroTier 网络与本地网络的隔离
   - 验证路由表的安全性
   - 检查网桥配置的风险
   - 评估网络分段策略

3. **访问控制**
   - 验证 ZeroTier 网络的访问控制规则
   - 检查 MAC 地址过滤设置
   - 审查网络成员管理
   - 评估流量控制策略

### 系统安全
1. **权限管理**
   - 脚本执行权限最小化
   - 配置文件权限设置
   - 日志文件访问控制
   - 临时文件安全处理

2. **服务安全**
   - systemd 服务配置安全
   - 服务运行用户权限
   - 配置文件集中管理安全性评估
   - 软链接安全风险检查

3. **配置文件安全**
   - 项目配置目录权限：`$SCRIPT_DIR/config/` 应限制访问
   - 敏感配置文件加密存储
   - 软链接目标验证，防止链接劫持
   - 配置文件完整性检查
   - 审查配置文件中的硬编码凭据
   - 评估配置文件的备份和恢复安全性
   ```bash
   # 配置文件安全检查示例
   find "$SCRIPT_DIR/config" -type f -perm /o+rwx -ls  # 检查其他用户权限
   find /etc/zt-gateway -type l ! -path "$SCRIPT_DIR/*" -ls  # 检查异常软链接
   grep -r "password\|secret\|key" "$SCRIPT_DIR/config/" 2>/dev/null  # 查找敏感信息
   ```
   - 服务依赖关系验证
   - 自启动服务审查

3. **文件系统安全**
   - 敏感配置文件保护
   - 脚本文件完整性
   - 日志轮转和保留策略
   - 备份文件安全

### 代码安全
1. **输入验证**
   - 用户输入参数验证
   - 配置文件内容验证
   - 网络接口名称验证
   - IP 地址格式验证

2. **命令注入防护**
   - 避免不安全的命令执行
   - 参数引用和转义
   - 临时文件安全创建
   - 环境变量安全

## 安全加固建议

### 网络层加固
1. **防火墙增强**
   ```bash
   # 添加连接状态跟踪
   iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

   # 限制连接速率
   iptables -A INPUT -p tcp --dport 22 -m recent --set --name SSH
   iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
   ```

2. **DDoS 防护**
   - 启用 SYN flood 保护
   - 配置连接限制
   - 启用 ICMP 限制

3. **网络监控**
   - 启用连接日志记录
   - 配置异常流量告警
   - 实施网络流量分析

### 系统层加固
1. **服务配置**
   ```bash
   # systemd 服务安全配置示例
   [Service]
   User=zerotier
   Group=zerotier
   NoNewPrivileges=true
   ProtectSystem=strict
   ProtectHome=true
   ```

2. **内核参数调优**
   ```bash
   # 网络安全参数
   net.ipv4.conf.all.log_martians=1
   net.ipv4.conf.all.send_redirects=0
   net.ipv4.conf.all.accept_redirects=0
   net.ipv4.conf.all.accept_source_route=0
   ```

### 应用层加固
1. **脚本安全**
   - 使用 `set -euo pipefail` 增强错误处理
   - 避免使用 `eval` 和动态命令执行
   - 实施输入参数严格验证
   - 使用临时目录安全模式

2. **配置安全**
   - 敏感配置文件权限 600
   - 配置文件内容加密存储
   - 定期更新和轮换密钥
   - 实施配置完整性检查

## 安全监控

### 日志审计
1. **安全事件记录**
   - 登录尝试记录
   - 配置更改日志
   - 网络连接日志
   - 错误和异常日志

2. **日志分析**
   - 自动化日志分析
   - 异常模式检测
   - 安全事件告警
   - 日志归档和保留

### 威胁检测
1. **实时监控**
   - 网络流量异常检测
   - 系统资源使用监控
   - 进程行为分析
   - 文件完整性监控

## 合规性检查

### 安全标准
- 遵循网络安全最佳实践
- 实施最小权限原则
- 确保数据传输加密
- 维护安全配置基线

### 定期审查
- 安全配置定期检查
- 漏洞扫描和修复
- 安全策略更新
- 应急响应计划

请指定需要重点审查的安全方面，我将提供详细的安全分析和加固建议。
