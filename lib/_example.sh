#!/usr/bin/env bash
# example.sh - 插件模板（复制此文件添加新工具）
#
# ========== 添加新工具只需 3 步 ==========
# 1. 复制本文件: cp lib/_example.sh lib/my-tool.sh
# 2. 修改下方 5 个 MARKER 处
# 3. 完成！无需改 install.sh / uninstall.sh / common.sh
#
# 文件命名: 小写 + 短横线 (如 pi-agent.sh)
# 函数命名: 默认 install_${PLUGIN_ID//-/_} / uninstall_${PLUGIN_ID//-/_}
# 注意: 下划线开头的模板文件不会被自动加载。

# ==========< MARKER 1: 元数据 >==========
# PLUGIN_ID: my-tool           # 唯一标识（内部路由用）
# PLUGIN_CMD: my-tool          # 安装后用户输入的命令名
# PLUGIN_NAME: My Tool         # 菜单显示名称
# PLUGIN_DESC: 这是一个示例工具  # 菜单描述

MY_TOOL_INSTALL_URL="https://example.com/install.sh"

# ==========< MARKER 2: 注册 >==========
register_plugin "my-tool" "my-tool" "My Tool" "这是一个示例工具"

# ==========< MARKER 3: 安装函数 >==========
install_my_tool() {
    step "安装 My Tool"

    if is_installed my-tool; then
        if confirm "  是否更新？" "Y"; then
            info "正在更新..."
        else
            record_result "my-tool" "skipped"
            return 0
        fi
    fi

    # 方式 A: 官方原生安装器（推荐）
    if download_and_run "My Tool" "$MY_TOOL_INSTALL_URL" bash; then
        success "My Tool 已安装"
    else
        error "My Tool 下载失败"
        record_result "my-tool" "failed" "官方安装器失败"
        return 1
    fi

    # 方式 B: npm 安装（需 Node.js）
    # if command_exists npm; then
    #     run_cmd npm install -g my-tool
    # else
    #     error "需要 Node.js，请先安装 NVM + Node.js"
    #     return 1
    # fi

    local tool_dir
    tool_dir=$(dirname "$(which my-tool 2>/dev/null || echo "/dev/null")")
    if [[ -n "$tool_dir" && "$tool_dir" != "." && "$tool_dir" != "/dev/null" ]]; then
        ensure_in_path "$tool_dir"
    fi

    if command_exists my-tool; then
        success "My Tool $(my-tool --version 2>/dev/null | head -n1) 可用"
        record_result "my-tool" "ok"
    else
        warn "安装完成但命令不可用，可能需要重新打开终端"
        record_result "my-tool" "failed"
    fi
}

# ==========< MARKER 4: 卸载函数 >==========
uninstall_my_tool() {
    step "卸载 My Tool"

    local tool_bin
    tool_bin=$(which my-tool 2>/dev/null || echo "")

    if [[ -n "$tool_bin" ]]; then
        if [[ -d "$HOME/.my-tool" ]]; then
            local bak
            bak="$HOME/.my-tool.bak.$(date +%Y%m%d%H%M%S)"
            cp -r "$HOME/.my-tool" "$bak"
            info "配置已备份到 $bak"
            if confirm "  是否删除配置？" "Y"; then
                rm -rf "$HOME/.my-tool"
            fi
        fi

        if [[ -f "$tool_bin" || -L "$tool_bin" ]] && [[ "$tool_bin" == "$HOME"* ]]; then
            rm -f "$tool_bin"
        fi

        clean_path_from_profiles "$(dirname "$tool_bin")"
        success "My Tool 已卸载"
    else
        info "My Tool 未安装，跳过"
    fi
}

# ==========< MARKER 5: npm 卸载（如果用了 npm） >==========
# npm uninstall -g my-tool 2>/dev/null || true
