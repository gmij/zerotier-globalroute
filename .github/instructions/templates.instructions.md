---
applyTo: "**/templates/**"
---
# 配置模板文件指令

## 模板处理
- 模板文件使用 `.template` 后缀
- 变量替换格式：`{{VARIABLE_NAME}}`
- 支持条件块：`{{#IF CONDITION}}...{{/IF}}`
- 生成的配置文件保存在 `config/` 目录

## 配置部署
- 通过软链接部署到系统位置
- 创建链接流程：
  1. `mkdir -p $(dirname "$target")`
  2. `ln -sf "$source" "$target"`
  3. 失败时使用 `sudo ln -sf`
  4. 最后备用 `cp -f`

## 特定配置类型
- **systemd 服务**：部署到 `/etc/systemd/system/`
- **dnsmasq 配置**：部署到 `/etc/dnsmasq.d/`
- **iptables 脚本**：部署到 `/etc/zt-gateway/scripts/`
- **监控脚本**：部署到项目 `scripts/` 目录
