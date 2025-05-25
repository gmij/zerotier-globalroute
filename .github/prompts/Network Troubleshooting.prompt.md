---
description: '调试和排查网络连通性问题'
mode: 'agent'
tools: ['codebase', 'terminalLastCommand']
---

# 网络连通性问题诊断

帮我诊断和修复 ZeroTier 网关的网络连通性问题。

## 诊断步骤

### 基础网络检查
1. **接口状态检查**
   - 验证 ZeroTier 接口是否启动：`ip link show`
   - 检查接口 IP 分配：`ip addr show`
   - 确认 MTU 设置：`ip link show zt接口`

2. **路由表检查**
   - 查看默认路由：`ip route show`
   - 检查 ZeroTier 路由：`ip route show table all`
   - 验证路由优先级

3. **防火墙规则验证**
   - 检查 iptables 规则：`iptables -L -v -n`
   - 验证 NAT 规则：`iptables -t nat -L -v -n`
   - 检查自定义链：`iptables -L ZT-IN ZT-FWD ZT-OUT -v -n`

### 服务状态检查
1. **核心服务**
   - ZeroTier 服务：`systemctl status zerotier-one`
   - 网络服务：`systemctl status NetworkManager`
   - iptables 服务：`systemctl status iptables`

2. **配置验证**
   - IP 转发状态：`sysctl net.ipv4.ip_forward`
   - ZeroTier 网络状态：`zerotier-cli listnetworks`
   - 项目配置文件完整性：检查 `$SCRIPT_DIR/config/`
   - 系统配置软链接状态：验证 `/etc/zt-gateway/` 链接
   - 配置文件同步状态：
     ```bash
     # 检查项目配置与系统配置的一致性
     diff "$SCRIPT_DIR/config/zt-gateway.conf" "/etc/zt-gateway/config" 2>/dev/null || echo "配置文件不同步"

     # 验证软链接完整性
     find /etc/zt-gateway -type l -exec test ! -e {} \; -print | while read broken_link; do
         echo "损坏的软链接: $broken_link"
     done
     ```

### 连通性测试
1. **本地测试**
   - Ping 本地接口：`ping -c 3 ZT接口IP`
   - 测试环回：`ping -c 3 127.0.0.1`

2. **网关测试**
   - 从 ZT 接口 ping 外网：`ping -c 3 -I zt接口 8.8.8.8`
   - 测试 DNS 解析：`nslookup google.com`

3. **端到端测试**
   - 从 ZT 客户端 ping 网关
   - 从 ZT 客户端访问外网
   - 测试反向连通性

## 常见问题解决

### 连接问题
- **ZT接口无IP**：重启 zerotier-one 服务
- **无法访问外网**：检查 NAT 规则和 IP 转发
- **路由冲突**：调整路由优先级

### 配置文件问题
- **项目配置丢失**：检查 `$SCRIPT_DIR/config/` 目录完整性
- **软链接断开**：重建系统配置软链接
- **配置不同步**：同步项目配置到系统目录
- **权限问题**：修复配置文件和目录权限

### 防火墙问题
- **规则丢失**：重新应用防火墙配置
- **链缺失**：重建自定义 iptables 链
- **策略冲突**：清理冲突的防火墙规则

### 性能问题
- **MTU 不匹配**：调整接口 MTU 值
- **DNS 解析慢**：配置更快的 DNS 服务器
- **带宽限制**：检查 QoS 设置

## 自动修复建议

基于诊断结果，提供以下修复选项：
1. **重启相关服务**
2. **重新应用网络配置**
3. **修复防火墙规则**
4. **重置网络接口**
5. **更新系统配置**

请描述你遇到的具体网络问题，我将协助进行诊断和修复。
