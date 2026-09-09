#!/usr/bin/env bash
# kimi.sh - Kimi Code CLI 安装模块
# PLUGIN_ID: kimi
# PLUGIN_CMD: kimi
# PLUGIN_NAME: Kimi Code CLI (Moonshot AI)
# PLUGIN_DESC: Moonshot AI 官方终端 AI 编程助手

KIMI_INSTALL_URL="https://code.kimi.com/install.sh"

register_plugin "kimi" "kimi" "Kimi Code CLI (Moonshot AI)" "Moonshot AI 官方终端 AI 编程助手"

install_kimi() {
    step "安装 Kimi Code CLI"

    if [[ "$DRY_RUN" == "true" ]]; then
        download_and_run "Kimi Code CLI" "$KIMI_INSTALL_URL" bash
        success "[DRY-RUN] Kimi Code CLI 安装命令已计划"
        record_result "kimi" "ok"
        return 0
    fi

    if is_installed kimi; then
        if ! confirm "  是否更新到最新版本？" "Y"; then
            record_result "kimi" "skipped"
            return 0
        fi

        if command_exists uv && run_cmd uv tool upgrade kimi-cli --no-cache; then
            success "Kimi Code CLI 已更新"
        elif download_and_run "Kimi Code CLI" "$KIMI_INSTALL_URL" bash; then
            success "Kimi Code CLI 已通过官方安装器更新"
        else
            error "Kimi Code CLI 更新失败"
            record_result "kimi" "failed" "uv 和官方安装器均失败"
            return 1
        fi
    elif ! download_and_run "Kimi Code CLI" "$KIMI_INSTALL_URL" bash; then
        error "Kimi Code CLI 安装失败"
        record_result "kimi" "failed" "官方安装器失败"
        return 1
    fi

    ensure_in_path "$HOME/.local/bin"
    if command_exists kimi; then
        success "Kimi Code CLI $(kimi --version 2>/dev/null | head -n1) 可用"
        record_result "kimi" "ok"
    else
        warn "安装完成但 kimi 命令不可用，可能需要重新打开终端"
        record_result "kimi" "failed"
    fi
}

uninstall_kimi() {
    step "卸载 Kimi Code CLI"

    if command_exists uv; then
        uv tool uninstall kimi-cli || true
    elif command_exists kimi; then
        warn "未找到 uv，已保留 Kimi Code CLI；请使用原安装方式卸载"
        return 1
    else
        info "Kimi Code CLI 未安装，跳过"
        return 0
    fi

    local dir bak
    for dir in "$HOME/.kimi" "$HOME/.config/kimi"; do
        [[ -d "$dir" ]] || continue
        bak="${dir}.bak.$(date +%Y%m%d%H%M%S)"
        cp -r "$dir" "$bak"
        info "配置已备份到 $bak"
        if confirm "  是否删除 $dir？" "Y"; then
            rm -rf "$dir"
        fi
    done
    success "Kimi Code CLI 已卸载"
}
