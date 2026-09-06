#!/usr/bin/env bash
# grok.sh - Grok CLI (xAI) 安装模块
# PLUGIN_ID: grok
# PLUGIN_CMD: grok
# PLUGIN_NAME: Grok CLI (xAI)
# PLUGIN_DESC: xAI 官方 AI 编程助手

GROK_INSTALL_URL="https://x.ai/cli/install.sh"

register_plugin "grok" "grok" "Grok CLI (xAI)" "xAI 官方 AI 编程助手"

install_grok() {
    step "安装 Grok CLI (xAI)"

    if is_installed grok; then
        if confirm "  是否更新到最新版本？" "Y"; then
            info "正在更新..."
        else
            record_result "grok" "skipped"
            return 0
        fi
    fi

    # 官方原生安装器（可能被 Cloudflare 拦截）
    info "尝试使用官方安装器..."
    if download_and_run "Grok CLI" "$GROK_INSTALL_URL" bash; then
        success "Grok CLI 已安装"
    else
        warn "官方安装器失败（可能被 Cloudflare 拦截），尝试 npm 安装..."
        load_nvm
        if command_exists npm; then
            if run_cmd npm install -g @xai-official/grok 2>/dev/null; then
                success "Grok CLI 已通过 npm 安装"
            else
                error "Grok CLI 安装失败（npm 方式也失败）"
                record_result "grok" "failed"
                return 1
            fi
        else
            error "Grok CLI 安装失败（npm 不可用，请先安装 NVM + Node.js）"
            record_result "grok" "failed"
            return 1
        fi
    fi

    local grok_dir
    grok_dir=$(dirname "$(which grok 2>/dev/null || echo "/dev/null")")
    if [[ -n "$grok_dir" && "$grok_dir" != "." && "$grok_dir" != "/dev/null" ]]; then
        ensure_in_path "$grok_dir"
    fi

    if command_exists grok; then
        success "Grok CLI 可用"
        record_result "grok" "ok"
    else
        warn "安装完成但 grok 命令不可用，可能需要重新打开终端"
        record_result "grok" "failed"
    fi
}

uninstall_grok() {
    step "卸载 Grok CLI"

    local grok_bin
    grok_bin=$(which grok 2>/dev/null || echo "")

    if [[ -n "$grok_bin" ]]; then
        if [[ -d "$HOME/.grok" ]]; then
            local bak
            bak="$HOME/.grok.bak.$(date +%Y%m%d%H%M%S)"
            cp -r "$HOME/.grok" "$bak"
            info "配置已备份到 $bak"
            if confirm "  是否删除 ~/.grok 目录？" "Y"; then
                rm -rf "$HOME/.grok"
                success "已删除 ~/.grok"
            else
                info "保留 ~/.grok"
            fi
        fi

        if [[ -f "$grok_bin" || -L "$grok_bin" ]]; then
            if [[ "$grok_bin" == "$HOME"* ]]; then
                rm -f "$grok_bin"
                success "已删除 $grok_bin"
            fi
        fi

        if command_exists npm; then
            npm uninstall -g @xai-official/grok 2>/dev/null || true
        fi

        clean_path_from_profiles "$(dirname "$grok_bin")"
        success "Grok CLI 已卸载"
    else
        info "Grok CLI 未安装，跳过"
    fi
}
