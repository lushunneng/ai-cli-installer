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

SYSTEM_TOOLS_NAMES=(
    "ripgrep (rg)"
    "fd-find (fd)"
    "bat"
    "jq"
    "tree"
    "htop"
    "tmux"
    "mosh"
    "zip"
    "unzip"
    "build-essential"
)

register_plugin "system-tools" "rg" "常用系统工具" "ripgrep、fd、bat、jq、tree、htop、tmux、mosh、压缩工具和编译工具"

install_system_tools() {
    step "安装常用系统工具"

    local selected=()
    local choice
    if [[ "$FORCE_YES" == "true" || ! -t 0 ]]; then
        selected=("${SYSTEM_TOOLS_PACKAGES[@]}")
        info "自动安装全部常用系统工具"
    else
        echo "可选择一个或多个工具："
        local i
        for ((i=0; i<${#SYSTEM_TOOLS_PACKAGES[@]}; i++)); do
            printf "  %2d) %s\n" "$((i + 1))" "${SYSTEM_TOOLS_NAMES[$i]}"
        done
        echo "   A) 全部安装"
        echo "   Q) 取消"
        echo ""
        read -r -p "请输入编号（例如 1 或 1,4,8）: " choice
        case "$choice" in
            [Aa]) selected=("${SYSTEM_TOOLS_PACKAGES[@]}") ;;
            [Qq]|"")
                info "已取消常用系统工具安装"
                record_result "system-tools" "skipped" "用户取消"
                return 0
                ;;
            *)
                local IFS=', '
                local selections=()
                read -ra selections <<< "$choice"
                local item index package
                for item in "${selections[@]}"; do
                    [[ "$item" =~ ^[0-9]+$ ]] || { warn "无效选择: $item"; continue; }
                    index=$((item - 1))
                    if (( index >= 0 && index < ${#SYSTEM_TOOLS_PACKAGES[@]} )); then
                        package="${SYSTEM_TOOLS_PACKAGES[$index]}"
                        if [[ ! " ${selected[*]} " =~ " $package " ]]; then
                            selected+=("$package")
                        fi
                    else
                        warn "编号超出范围: $item"
                    fi
                done
                ;;
        esac
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "没有选择任何工具"
        record_result "system-tools" "skipped" "未选择工具"
        return 0
    fi

    info "将安装: ${selected[*]}"
    if ! apt_install "${selected[@]}"; then
        error "常用系统工具安装失败"
        record_result "system-tools" "failed" "APT 安装失败"
        return 1
    fi
    success "已安装所选常用系统工具"
    record_result "system-tools" "ok" "${selected[*]}"
}

uninstall_system_tools() {
    step "卸载常用系统工具"
    warn "为避免删除系统或用户已有依赖，安装器不会自动卸载这些 APT 软件包"
    info "如需卸载，请手动执行: sudo apt-get remove ${SYSTEM_TOOLS_PACKAGES[*]}"
    record_result "system-tools" "skipped" "保留 APT 软件包"
}
