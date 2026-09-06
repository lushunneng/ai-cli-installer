#!/usr/bin/env bash
# claude-code.sh - Claude Code CLI 安装模块
# PLUGIN_ID: claude-code
# PLUGIN_CMD: claude
# PLUGIN_NAME: Claude Code (Anthropic)
# PLUGIN_DESC: Anthropic 官方 AI 编程助手

CLAUDE_INSTALL_URL="https://claude.ai/install.sh"

register_plugin "claude-code" "claude" "Claude Code (Anthropic)" "Anthropic 官方 AI 编程助手"

install_claude_code() {
    step "安装 Claude Code CLI"

    if is_installed claude; then
        if confirm "  是否更新到最新版本？" "Y"; then
            info "正在更新..."
        else
            record_result "claude-code" "skipped"
            return 0
        fi
    fi

    load_nvm
    if command_exists npm && run_cmd npm install -g @anthropic-ai/claude-code; then
        success "Claude Code 已通过 npm 安装"
    elif download_and_run "Claude Code" "$CLAUDE_INSTALL_URL" bash; then
        success "Claude Code 已安装"
    else
        error "Claude Code 安装失败"
        record_result "claude-code" "failed" "npm 和官方安装器均失败"
        return 1
    fi

    # 确保 PATH 生效
    local claude_dir
    claude_dir=$(dirname "$(which claude 2>/dev/null || echo "/dev/null")")
    if [[ -n "$claude_dir" && "$claude_dir" != "." && "$claude_dir" != "/dev/null" ]]; then
        ensure_in_path "$claude_dir"
    fi

    # 验证
    if command_exists claude; then
        success "Claude Code $(claude --version 2>/dev/null | head -n1) 可用"
        record_result "claude-code" "ok"
    else
        warn "安装完成但 claude 命令不可用，可能需要重新打开终端"
        record_result "claude-code" "failed"
    fi
}

uninstall_claude_code() {
    step "卸载 Claude Code"

    local claude_bin
    claude_bin=$(which claude 2>/dev/null || echo "")

    if [[ -n "$claude_bin" ]]; then
        # 备份配置目录
        if [[ -d "$HOME/.claude" ]]; then
            local bak
            bak="$HOME/.claude.bak.$(date +%Y%m%d%H%M%S)"
            cp -r "$HOME/.claude" "$bak"
            info "配置已备份到 $bak"
            if confirm "  是否删除 ~/.claude 目录？" "Y"; then
                rm -rf "$HOME/.claude"
                success "已删除 ~/.claude"
            else
                info "保留 ~/.claude"
            fi
        fi

        # 删除二进制文件
        if [[ -f "$claude_bin" || -L "$claude_bin" ]]; then
            if [[ "$claude_bin" == "$HOME"* ]]; then
                rm -f "$claude_bin"
                success "已删除 $claude_bin"
            fi
        fi

        # 清理 PATH
        clean_path_from_profiles "$(dirname "$claude_bin")"

        success "Claude Code 已卸载"
    else
        info "Claude Code 未安装，跳过"
    fi
}
