#!/usr/bin/env bash
# node.sh - NVM + Node.js 安装模块
# PLUGIN_ID: nvm
# PLUGIN_CMD: nvm
# PLUGIN_NAME: Node.js (NVM)
# PLUGIN_DESC: NVM + Node.js LTS，npm 包管理所需的基础依赖

NVM_VERSION="v0.40.3"
NODE_VERSION="22"

register_plugin "nvm" "nvm" "Node.js (NVM)" "NVM + Node.js LTS，npm 包管理所需的基础依赖"

install_nvm() {
    step "安装 NVM (Node Version Manager)"

    if [[ -d "$HOME/.nvm" ]]; then
        load_nvm
        local current_nvm_version
        current_nvm_version=$(nvm --version 2>/dev/null || echo "unknown")
        success "NVM 已安装 ($current_nvm_version)"

        if confirm "  是否更新 NVM 到 ${NVM_VERSION}？" "Y"; then
            update_nvm || return 1
        else
            record_result "nvm" "skipped" "保留 NVM $current_nvm_version"
        fi
    else
        if download_and_run "NVM ${NVM_VERSION}" "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" bash; then
            if [[ "$DRY_RUN" == "true" ]]; then
                success "[DRY-RUN] NVM $NVM_VERSION 和 Node.js $NODE_VERSION 安装命令已计划"
                return 0
            fi
            load_nvm
            success "NVM $NVM_VERSION 已安装"
        else
            error "NVM 下载或安装失败"
            record_result "nvm" "failed" "NVM 安装失败"
            return 1
        fi
    fi

    install_node
}

update_nvm() {
    step "更新 NVM 到 ${NVM_VERSION}"

    if download_and_run "NVM ${NVM_VERSION}" "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" bash; then
        if [[ "$DRY_RUN" == "true" ]]; then
            success "[DRY-RUN] NVM $NVM_VERSION 更新命令已计划"
            return 0
        fi

        load_nvm
        success "NVM 已更新到 $(nvm --version 2>/dev/null || echo "$NVM_VERSION")"
        return 0
    fi

    error "NVM 更新失败"
    record_result "nvm" "failed" "NVM 更新失败"
    return 1
}

install_node() {
    step "安装 Node.js $NODE_VERSION (LTS)"
    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd nvm install "$NODE_VERSION"
        run_cmd nvm use "$NODE_VERSION"
        run_cmd nvm alias default "$NODE_VERSION"
        success "[DRY-RUN] Node.js $NODE_VERSION 安装命令已计划"
        return 0
    fi

    load_nvm

    if ! command_exists nvm; then
        error "nvm 未加载，无法安装 Node.js"
        record_result "nvm" "failed" "nvm 未加载"
        return 1
    fi

    local current_version
    current_version=$(nvm current 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo "")

    if [[ "$current_version" == "$NODE_VERSION" ]]; then
        success "Node.js $NODE_VERSION 已安装 ($(node --version))"
        return 0
    fi

    run_cmd nvm install "$NODE_VERSION"
    run_cmd nvm use "$NODE_VERSION"
    run_cmd nvm alias default "$NODE_VERSION"

    success "Node.js $(node --version) 已安装"
    info "npm $(npm --version)"
}

uninstall_nvm() {
    step "卸载 NVM + Node.js"
    if [[ -d "$HOME/.nvm" ]]; then
        if confirm "  是否删除 ~/.nvm 目录（包含所有 Node.js 版本）？" "N"; then
            rm -rf "$HOME/.nvm"
            clean_path_from_profiles
            success "NVM + Node.js 已卸载"
        else
            info "保留 NVM"
        fi
    else
        info "NVM 未安装，跳过"
    fi
}
