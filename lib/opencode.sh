#!/usr/bin/env bash
# opencode.sh - OpenCode CLI 安装模块
# PLUGIN_ID: opencode
# PLUGIN_CMD: opencode
# PLUGIN_NAME: OpenCode CLI
# PLUGIN_DESC: 开源多模型 AI 编程助手

OPENCODE_INSTALL_URL="https://opencode.ai/install"

register_plugin "opencode" "opencode" "OpenCode CLI" "开源多模型 AI 编程助手"

install_opencode() {
    step "安装 OpenCode CLI"

    if is_installed opencode; then
        if confirm "  是否更新到最新版本？" "Y"; then
            info "正在更新..."
        else
            record_result "opencode" "skipped"
            return 0
        fi
    fi

    if download_and_run "OpenCode CLI" "$OPENCODE_INSTALL_URL" bash; then
        success "OpenCode CLI 已安装"
    else
        error "OpenCode CLI 下载或安装失败"
        record_result "opencode" "failed" "官方安装器失败"
        return 1
    fi

    # OpenCode 安装到 ~/.opencode/bin 或 $OPENCODE_INSTALL_DIR
    local opencode_dir="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    if [[ -d "$opencode_dir" ]]; then
        ensure_in_path "$opencode_dir"
    fi

    if command_exists opencode; then
        success "OpenCode CLI $(opencode --version 2>/dev/null | head -n1) 可用"
        record_result "opencode" "ok"
    else
        warn "安装完成但 opencode 命令不可用，可能需要重新打开终端"
        record_result "opencode" "failed"
    fi
}

uninstall_opencode() {
    step "卸载 OpenCode CLI"

    local opencode_bin
    opencode_bin=$(which opencode 2>/dev/null || echo "")

    if [[ -n "$opencode_bin" ]]; then
        local bak
        bak="$HOME/.opencode.bak.$(date +%Y%m%d%H%M%S)"
        local has_data=false

        for dir in "$HOME/.opencode" "$HOME/.config/opencode" "$HOME/.local/share/opencode"; do
            if [[ -d "$dir" ]]; then
                mkdir -p "$bak"
                cp -r "$dir" "$bak/"
                has_data=true
            fi
        done

        if [[ "$has_data" == "true" ]]; then
            info "配置已备份到 $bak"
            if confirm "  是否删除 OpenCode 配置目录？" "Y"; then
                rm -rf "$HOME/.opencode" "$HOME/.config/opencode" "$HOME/.local/share/opencode"
                success "已删除 OpenCode 配置"
            else
                info "保留 OpenCode 配置"
            fi
        fi

        if [[ -f "$opencode_bin" || -L "$opencode_bin" ]]; then
            if [[ "$opencode_bin" == "$HOME"* ]]; then
                rm -f "$opencode_bin"
                success "已删除 $opencode_bin"
            fi
        fi

        clean_path_from_profiles "$(dirname "$opencode_bin")"
        success "OpenCode CLI 已卸载"
    else
        info "OpenCode CLI 未安装，跳过"
    fi
}
