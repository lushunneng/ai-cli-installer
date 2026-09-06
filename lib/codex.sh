#!/usr/bin/env bash
# codex.sh - Codex CLI (OpenAI) 安装模块
# PLUGIN_ID: codex
# PLUGIN_CMD: codex
# PLUGIN_NAME: Codex CLI (OpenAI)
# PLUGIN_DESC: OpenAI 官方 AI 编程助手

CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"

register_plugin "codex" "codex" "Codex CLI (OpenAI)" "OpenAI 官方 AI 编程助手"

install_codex() {
    step "安装 Codex CLI (OpenAI)"

    if is_installed codex; then
        if confirm "  是否更新到最新版本？" "Y"; then
            info "正在更新..."
        else
            record_result "codex" "skipped"
            return 0
        fi
    fi

    if download_and_run "Codex CLI" "$CODEX_INSTALL_URL" sh; then
        success "Codex CLI 已安装"
    else
        warn "Codex 官方安装器失败，尝试 npm 安装..."
        load_nvm
        if command_exists npm && run_cmd npm install -g @openai/codex; then
            success "Codex CLI 已通过 npm 安装"
        else
            error "Codex CLI 安装失败"
            record_result "codex" "failed" "官方安装器和 npm 均失败"
            return 1
        fi
    fi

    local codex_dir
    codex_dir=$(dirname "$(which codex 2>/dev/null || echo "/dev/null")")
    if [[ -n "$codex_dir" && "$codex_dir" != "." && "$codex_dir" != "/dev/null" ]]; then
        ensure_in_path "$codex_dir"
    fi

    if command_exists codex; then
        success "Codex CLI $(codex --version 2>/dev/null | head -n1) 可用"
        record_result "codex" "ok"
    else
        warn "安装完成但 codex 命令不可用，可能需要重新打开终端"
        record_result "codex" "failed"
    fi
}

uninstall_codex() {
    step "卸载 Codex CLI"

    local codex_bin
    codex_bin=$(which codex 2>/dev/null || echo "")

    if [[ -n "$codex_bin" ]]; then
        if [[ -d "$HOME/.codex" ]]; then
            local bak
            bak="$HOME/.codex.bak.$(date +%Y%m%d%H%M%S)"
            cp -r "$HOME/.codex" "$bak"
            info "配置已备份到 $bak"
            if confirm "  是否删除 ~/.codex 目录？" "Y"; then
                rm -rf "$HOME/.codex"
                success "已删除 ~/.codex"
            else
                info "保留 ~/.codex"
            fi
        fi

        if [[ -f "$codex_bin" || -L "$codex_bin" ]]; then
            if [[ "$codex_bin" == "$HOME"* ]]; then
                rm -f "$codex_bin"
                success "已删除 $codex_bin"
            fi
        fi

        clean_path_from_profiles "$(dirname "$codex_bin")"
        success "Codex CLI 已卸载"
    else
        info "Codex CLI 未安装，跳过"
    fi
}
