#!/usr/bin/env bash
# pi.sh - Pi Coding Agent 安装模块
# PLUGIN_ID: pi
# PLUGIN_CMD: pi
# PLUGIN_NAME: Pi Coding Agent
# PLUGIN_DESC: 支持多模型的终端 AI 编程智能体

# https://pi.dev 的官方 npm 安装方式；Node.js >=22.19.0
PI_NPM_PACKAGE="@earendil-works/pi-coding-agent"

register_plugin "pi" "pi" "Pi Coding Agent" "支持多模型的终端 AI 编程智能体"

install_pi() {
    step "安装 Pi Coding Agent"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Pi 需要 Node.js >=22.19.0"
        run_cmd npm install -g --ignore-scripts "$PI_NPM_PACKAGE@latest"
        record_result "pi" "planned"
        return 0
    fi

    load_nvm || true
    if is_installed pi && ! confirm "  是否更新到最新版本？" "Y"; then
        record_result "pi" "skipped"
        return 0
    fi

    if ! command_exists npm || ! command_exists node; then
        error "Pi 需要 Node.js >=22.19.0 和 npm；请先安装或更新 Node.js (NVM)"
        record_result "pi" "failed" "Node.js 或 npm 不可用"
        return 1
    fi
    if ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)'; then
        error "当前 Node.js $(node --version) 不满足 Pi 要求；请先更新到 >=22.19.0"
        record_result "pi" "failed" "Node.js 版本过低"
        return 1
    fi

    if ! run_cmd npm install -g --ignore-scripts "$PI_NPM_PACKAGE@latest"; then
        error "Pi Coding Agent 安装失败"
        record_result "pi" "failed" "npm 安装失败"
        return 1
    fi

    local npm_prefix
    if npm_prefix=$(npm prefix -g) && [[ -n "$npm_prefix" ]]; then
        ensure_in_path "$npm_prefix/bin"
    fi
    if command_exists pi; then
        success "Pi Coding Agent $(pi --version 2>/dev/null | head -n1) 可用"
        info "运行 pi 开始使用"
        record_result "pi" "ok"
    else
        error "安装完成但 pi 命令不可用，可能需要重新打开终端"
        record_result "pi" "failed" "pi 命令未检测到"
        return 1
    fi
}

uninstall_pi() {
    step "卸载 Pi Coding Agent"

    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd npm uninstall -g "$PI_NPM_PACKAGE"
        info "[DRY-RUN] 保留 ~/.pi；实际卸载时可选择备份后删除"
        return 0
    fi

    load_nvm || true
    if ! command_exists npm; then
        error "npm 不可用，无法卸载 Pi；请先加载安装 Pi 时使用的 Node.js 环境"
        return 1
    fi
    if ! run_cmd npm uninstall -g "$PI_NPM_PACKAGE"; then
        error "Pi Coding Agent 卸载失败"
        return 1
    fi

    if [[ -d "$HOME/.pi" ]] && confirm "  是否备份并删除 ~/.pi（包含配置、认证和会话）？" "N"; then
        local bak
        bak="$HOME/.pi.bak.$(date +%Y%m%d%H%M%S)"
        if ! cp -a "$HOME/.pi" "$bak"; then
            error "配置备份失败，保留 ~/.pi"
            return 1
        fi
        info "配置已备份到 $bak"
        run_cmd rm -rf "$HOME/.pi" || return 1
    fi
    success "Pi Coding Agent npm 包已卸载"
}
