# ZeroTier 全局路由网关

ZeroTier 全局路由网关是一套主要针对 CentOS 系统开发的脚本工具集，帮助您轻松将 Linux 服务器配置为 ZeroTier 网络的双向网关。通过本工具，您可以实现 ZeroTier 虚拟网络与外部网络之间的通信。

> **免责声明**：本项目仅用于学习和研究目的，不得用于商业用途。如有违反相关法律法规的使用场景，一切后果由使用者自行承担。

## 功能特点

- **双向网络转发**：允许 ZeroTier 网络内的设备访问互联网，同时允许外部访问 ZeroTier 网络内的服务
- **自动检测网络接口**：智能识别 ZeroTier 接口和外网接口
- **智能防火墙配置**：自动设置 iptables 规则以确保安全性和网络连通性
- **网络性能优化**：优化内核参数提升网关转发性能
- **状态监控**：提供简单的监控脚本查看网关状态
- **自动修复**：周期性检查网络配置，确保服务稳定运行
- **GFW List 分流**：支持基于 GFW List 的智能分流，只有列表中的网站才通过全局路由
- **IPv6 支持**：可选的 IPv6 支持功能
- **便携式打包**：支持生成单一可执行的打包文件

## 系统要求

- CentOS 7/8 系统
- 已安装 ZeroTier 客户端并加入网络
- Root 权限

## 快速开始

### 一键部署

可以使用以下命令快速下载并运行最新的集成脚本：

```bash
curl -fsSL https://github.com/gmij/zerotier-globalroute/releases/latest/download/zerotier-gateway-bundle.sh -o deploy.sh && chmod +x deploy.sh && sudo ./deploy.sh
```

或者使用wget：

```bash
wget -O deploy.sh https://github.com/gmij/zerotier-globalroute/releases/latest/download/zerotier-gateway-bundle.sh && chmod +x deploy.sh && sudo ./deploy.sh
```

### 安装方法

1. 克隆或下载本仓库到您的服务器
2. 执行安装脚本：

```bash
chmod +x zerotier-gateway.sh
./zerotier-gateway.sh
```

脚本会自动检测网络接口并配置必要的规则。

### 使用打包版本

如果您想使用单文件版本，可以先运行打包脚本：

```bash
./build.sh
```

生成的 `zerotier-gateway-bundle.sh` 文件包含了所有必要的组件，可以直接在目标系统上运行。打包版本可以方便地迁移到不同服务器，只需复制整个安装目录即可。

## 命令行参数

脚本支持以下参数：

- `-z, --zt-if <接口名称>` - 指定 ZeroTier 网络接口
- `-w, --wan-if <接口名称>` - 指定外网接口
- `-m, --mtu <值>` - 设置 ZeroTier 接口 MTU 值（默认1400）
- `-s, --status` - 显示当前网关状态
- `-b, --backup` - 备份当前 iptables 规则
- `-d, --debug` - 启用调试模式
- `-r, --restart` - 重启网关（应用现有配置）
- `-u, --update` - 更新模式（保留现有接口设置）
- `-U, --uninstall` - 卸载网关配置
- `--ipv6` - 启用 IPv6 支持
- `--stats` - 显示流量统计
- `--test` - 测试网关连通性
- `--gfwlist` - 启用 GFW List 分流模式（只有列表中的站点才走全局路由）
- `--update-gfwlist` - 更新 GFW List
- `--gfwlist-status` - 显示当前 GFW List 状态

## 项目结构

- `zerotier-gateway.sh` - 主要脚本
- `build.sh` - 打包脚本
- `cmd/` - 功能模块目录
  - `detect.sh` - 网络接口检测
  - `firewall.sh` - 防火墙规则配置
  - `monitor.sh` - 网络监控
  - `uninstall.sh` - 卸载功能
  - `utils.sh` - 实用函数
- `templates/` - 配置模板目录
  - 包含系统配置和监控脚本的模板

## GFW List 分流功能

此功能允许您实现智能分流，只有 GFW List 中的网站才通过 ZeroTier 网络路由，其他网站保持正常线路访问。

### 使用方法

1. 在安装脚本时添加 `--gfwlist` 参数启用分流功能：
    ```bash
    ./zerotier-gateway.sh --gfwlist
    ```

2. 更新 GFW List：
    ```bash
    ./zerotier-gateway.sh --update-gfwlist
    ```

3. 查看 GFW List 状态：
    ```bash
    ./zerotier-gateway.sh --gfwlist-status
    ```

### 工作原理

1. 脚本会下载并解析最新的 GFW List
2. 通过 dnsmasq 进行域名解析，将匹配的域名 IP 地址加入 ipset
3. 使用 iptables 规则，只将 ipset 中的 IP 地址通过 ZeroTier 路由
4. 其余流量保持原有路径不变

### 依赖组件

分流功能需要安装以下组件（脚本会自动安装）：
- ipset：用于存储 IP 地址集合
- dnsmasq：用于域名解析和 ipset 集成
- curl/wget：用于下载 GFW List
- base64：用于解码 GFW List

## 注意事项

1. 本工具仅用于合法的网络环境配置，请遵守当地相关法律法规
2. 使用前请确保您对服务器有足够的操作权限
3. 建议在配置前备份现有的网络和防火墙设置
4. 如有问题，可使用 `--debug` 参数获取详细日志
5. GFW List 分流功能需要正常的 DNS 解析，推荐使用可靠的 DNS 服务器

## 卸载

如需卸载网关配置：

```bash
./zerotier-gateway.sh --uninstall
./zerotier-gateway.sh -U
```

## 故障排除

如果您遇到连接问题：

1. 使用 `zt-status` 命令检查网关状态
2. 检查防火墙规则是否正确应用
3. 验证 ZeroTier 网络配置是否正确
4. 检查路由表设置

## 贡献指南

欢迎提交问题报告和改进建议。如果您想贡献代码，请确保遵循项目的代码风格并提交详细的变更说明。

## 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件