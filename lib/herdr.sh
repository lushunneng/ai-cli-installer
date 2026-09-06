#!/usr/bin/env bash
# herdr.sh - Herdr CLI 安装模块
# PLUGIN_ID: herdr
# PLUGIN_CMD: herdr
# PLUGIN_NAME: Herdr
# PLUGIN_DESC: 终端里的 AI 编程智能体复用器

HERDR_INSTALL_URL="https://herdr.dev/install.sh"

register_plugin "herdr" "herdr" "Herdr" "终端里的 AI 编程智能体复用器"

install_herdr() {
    step "安装 Herdr"

    if is_installed herdr; then
        if confirm "  是否更新到最新版本？" "Y"; then
            info "正在更新..."
            if run_cmd herdr update; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    success "[DRY-RUN] Herdr 更新命令已计划"
                    return 0
                fi
                success "Herdr $(herdr --version 2>/dev/null | head -n1) 可用"
                record_result "herdr" "ok"
                return 0
            fi
            warn "herdr update 失败，尝试官方安装器..."
        else
            record_result "herdr" "skipped"
            return 0
        fi
    fi

    if download_and_run "Herdr" "$HERDR_INSTALL_URL" sh; then
        if [[ "$DRY_RUN" == "true" ]]; then
            success "[DRY-RUN] Herdr 安装命令已计划"
            return 0
        fi
        success "Herdr 已安装"
    else
        error "Herdr 下载或安装失败"
        record_result "herdr" "failed" "官方安装器失败"
        return 1
    fi

    local herdr_dir="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
    if [[ -d "$herdr_dir" ]]; then
        ensure_in_path "$herdr_dir"
    fi

    if command_exists herdr; then
        success "Herdr $(herdr --version 2>/dev/null | head -n1) 可用"
        record_result "herdr" "ok"
    else
        warn "安装完成但 herdr 命令不可用，可能需要重新打开终端"
        record_result "herdr" "failed"
    fi
}

uninstall_herdr() {
    step "卸载 Herdr"

    local herdr_bin
    herdr_bin=$(which herdr 2>/dev/null || echo "")

    if [[ -n "$herdr_bin" ]]; then
        local bak
        bak="$HOME/.herdr.bak.$(date +%Y%m%d%H%M%S)"
        local has_data=false

        for dir in "$HOME/.config/herdr" "$HOME/.herdr"; do
            if [[ -d "$dir" ]]; then
                mkdir -p "$bak"
                cp -r "$dir" "$bak/"
                has_data=true
            fi
        done

        if [[ "$has_data" == "true" ]]; then
            info "配置和会话数据已备份到 $bak"
            if confirm "  是否删除 Herdr 配置和会话数据？" "Y"; then
                rm -rf "$HOME/.config/herdr" "$HOME/.herdr"
                success "已删除 Herdr 配置和会话数据"
            else
                info "保留 Herdr 配置和会话数据"
            fi
        fi

        if [[ -f "$herdr_bin" || -L "$herdr_bin" ]]; then
            if [[ "$herdr_bin" == "$HOME"* ]]; then
                rm -f "$herdr_bin"
                success "已删除 $herdr_bin"
            else
                warn "检测到 Herdr 不在用户目录，已保留: $herdr_bin"
            fi
        fi

        clean_path_from_profiles "$(dirname "$herdr_bin")"
        success "Herdr 已卸载"
    else
        info "Herdr 未安装，跳过"
    fi
}
