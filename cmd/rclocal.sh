#!/bin/bash
#
# ZeroTier 网关 rc.local 配置模块
# 用于确保 rc.local 正确配置，解决权限问题
#

# 配置 rc.local
setup_rc_local() {
    log "INFO" "配置 rc.local 执行权限..."

    # 检查rc.local文件是否存在
    if [ ! -f "/etc/rc.d/rc.local" ]; then
        log "INFO" "rc.local 文件不存在，创建新文件..."
        cat > /etc/rc.d/rc.local << 'EOF'
#!/bin/bash
# THIS FILE IS ADDED FOR COMPATIBILITY PURPOSES
#
# It is highly advisable to create own systemd services or udev rules
# to run scripts during boot instead of using this file.
#
# In contrast to previous versions due to parallel execution during boot
# this script will NOT be run after all other services.
#
# Please note that you must run 'chmod +x /etc/rc.d/rc.local' to ensure
# that this script will be executed during boot.

touch /var/lock/subsys/local
EOF
        log "INFO" "rc.local 文件已创建"
    fi

    # 设置执行权限
    chmod +x /etc/rc.d/rc.local
    log "DEBUG" "已设置 /etc/rc.d/rc.local 执行权限"

    # 检查SELinux上下文
    if command -v restorecon &>/dev/null; then
        log "DEBUG" "恢复 SELinux 上下文..."
        restorecon -v /etc/rc.d/rc.local
    fi

    # 检查rc-local服务是否启用
    if command -v systemctl &>/dev/null; then
        log "DEBUG" "检查 rc-local.service 状态..."

        if ! systemctl is-enabled rc-local.service &>/dev/null; then
            log "INFO" "启用 rc-local.service..."
            systemctl enable rc-local.service
        fi

        if ! systemctl is-active rc-local.service &>/dev/null; then
            log "INFO" "启动 rc-local.service..."
            systemctl start rc-local.service
        fi
    fi

    log "INFO" "rc.local 配置完成"
    return 0
}
