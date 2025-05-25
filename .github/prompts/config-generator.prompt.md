---
mode: 'edit'
description: '配置文件生成和管理'
---

# 配置文件生成助手

基于项目模板生成和管理配置文件，确保遵循集中化管理原则。

## 生成规则
1. **使用模板文件**
   - 从 `templates/` 目录读取模板
   - 替换变量：`{{VARIABLE_NAME}}`
   - 保存到 `config/` 目录

2. **软链接部署**
   - 创建到系统位置的软链接
   - 标准流程：`ln -sf → sudo ln -sf → cp -f`
   - 记录部署日志

3. **权限管理**
   - 项目配置：用户可写
   - 系统配置：遵循系统权限
   - 服务配置：root 权限

## 支持的配置类型
- 主配置文件：`zt-gateway.conf`
- DNS 配置：`zt-gfwlist.conf`
- 系统服务：`*.service`
- 防火墙脚本：`ipset-init.sh`
- 监控脚本：`network-monitor.sh`

参考现有模板：#templates/ 和配置管理指令：[Configuration Management](../prompts/Configuration Management.prompt.md)
