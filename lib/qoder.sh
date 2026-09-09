#!/usr/bin/env bash
# qoder.sh - Qoder CLI 安装模块
# PLUGIN_ID: qoder
# PLUGIN_CMD: qoder
# PLUGIN_NAME: Qoder CLI
# PLUGIN_DESC: Qoder 官方终端 AI 编程助手

QODER_NPM_PACKAGE="@qoder-ai/qodercli"

register_plugin "qoder" "qoder" "Qoder CLI" "Qoder 官方终端 AI 编程助手"

install_qoder() {
    step "安装 Qoder CLI"

    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd npm install -g "$QODER_NPM_PACKAGE@latest"
        success "[DRY-RUN] Qoder CLI 安装命令已计划"
        record_result "qoder" "ok"
        return 0
    fi

    if is_installed qoder && ! confirm "  是否更新到最新版本？" "Y"; then
        record_result "qoder" "skipped"
        return 0
    fi

    load_nvm
    if ! command_exists npm; then
        error "Qoder CLI 需要 Node.js 20 或更高版本；请先安装 NVM + Node.js"
        record_result "qoder" "failed" "npm 不可用"
        return 1
    fi

    if ! run_cmd npm install -g "$QODER_NPM_PACKAGE@latest"; then
        error "Qoder CLI 安装失败"
        record_result "qoder" "failed" "npm 安装失败"
        return 1
    fi

    local qoder_dir
    qoder_dir=$(dirname "$(command -v qoder 2>/dev/null || echo /dev/null)")
    if [[ "$qoder_dir" != "/dev/null" && "$qoder_dir" != "." ]]; then
        ensure_in_path "$qoder_dir"
    fi

    if command_exists qoder; then
        success "Qoder CLI $(qoder --version 2>/dev/null | head -n1) 可用"
        record_result "qoder" "ok"
    else
        warn "安装完成但 qoder 命令不可用，可能需要重新打开终端"
        record_result "qoder" "failed"
    fi
}

uninstall_qoder() {
    step "卸载 Qoder CLI"
    load_nvm
    if command_exists npm; then
        npm uninstall -g "$QODER_NPM_PACKAGE" || true
    fi

    if [[ -d "$HOME/.qoder" ]]; then
        local bak="$HOME/.qoder.bak.$(date +%Y%m%d%H%M%S)"
        cp -r "$HOME/.qoder" "$bak"
        info "配置已备份到 $bak"
        if confirm "  是否删除 ~/.qoder 目录？" "Y"; then
            rm -rf "$HOME/.qoder"
        fi
    fi
    success "Qoder CLI 已卸载"
}
