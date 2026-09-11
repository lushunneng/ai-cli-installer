#!/usr/bin/env bash
# system-tools.sh - 常用 Ubuntu 开发与运维工具
# PLUGIN_ID: system-tools
# PLUGIN_CMD: rg
# PLUGIN_NAME: 常用系统工具
# PLUGIN_DESC: ripgrep、fd、bat、jq、tree、htop、tmux、mosh、压缩工具和编译工具

SYSTEM_TOOLS_PACKAGES=(
    ripgrep
    fd-find
    bat
    jq
    tree
    htop
    tmux
    mosh
    zip
    unzip
    build-essential
)

register_plugin "system-tools" "rg" "常用系统工具" "ripgrep、fd、bat、jq、tree、htop、tmux、mosh、压缩工具和编译工具"

install_system_tools() {
    step "安装常用系统工具"
    if ! apt_install "${SYSTEM_TOOLS_PACKAGES[@]}"; then
        error "常用系统工具安装失败"
        record_result "system-tools" "failed" "APT 安装失败"
        return 1
    fi
    success "常用系统工具已安装"
    record_result "system-tools" "ok"
}

uninstall_system_tools() {
    step "卸载常用系统工具"
    warn "为避免删除系统或用户已有依赖，安装器不会自动卸载这些 APT 软件包"
    info "如需卸载，请手动执行: sudo apt-get remove ${SYSTEM_TOOLS_PACKAGES[*]}"
    record_result "system-tools" "skipped" "保留 APT 软件包"
}
