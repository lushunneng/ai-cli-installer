#!/usr/bin/env bash
# ai-cli-installer - AI CLI 工具一键安装脚本 v3 (插件式架构)
# 支持: Ubuntu 22.04 / 24.04
# 新增工具: 只需在 lib/ 下添加 .sh 文件，无需修改本脚本

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 先加载公共函数（含 register_plugin 等基础能力）
source "${SCRIPT_DIR}/lib/common.sh"

# 自动加载 lib/ 下所有插件（每个插件自注册）
load_plugins "${SCRIPT_DIR}/lib"

# ==================== 显示横幅 ====================
show_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
    _        _____ _     _____ ____  ____
   / \   ___|_   _| |   | ____|  _ \| __ )
  / _ \ / _ \ | | | |   |  _| | | | |  _ \
 / ___ \ (_) || | | |___| |___| |_| | |_) |
/_/   \_\___/ |_| |_____|_____|____/|____/

  AI CLI 工具一键安装器 v3
EOF
    echo -e "${NC}"
    echo -e "  系统: $(detect_os) $(detect_version) ($(detect_arch))"
    echo -e "  已注册工具: ${#PLUGIN_LIST[@]} 个"
    [[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}模式: DRY-RUN${NC}"
    echo ""
}

# ==================== 动态菜单 ====================
show_menu() {
    echo -e "${BOLD}可用工具:${NC}"
    echo ""

    local idx=1
    for plugin in "${PLUGIN_LIST[@]}"; do
        local id cmd name desc
        id=$(get_plugin_field "$plugin" 1)
        cmd=$(get_plugin_field "$plugin" 2)
        name=$(get_plugin_field "$plugin" 3)
        desc=$(get_plugin_field "$plugin" 4)

        local installed=false
        if [[ "$cmd" == "nvm" ]]; then
            [[ -d "$HOME/.nvm" ]] && installed=true
        else
            command_exists "$cmd" 2>/dev/null && installed=true
        fi

        if [[ "$installed" == "true" ]]; then
            echo -e "  ${GREEN}[已安装]${NC} $idx) $name"
        else
            echo -e "  $idx) $name"
        fi
        echo -e "     ${CYAN}${desc}${NC}"
        ((idx++))
    done

    echo ""
    echo -e "  ${BOLD}A) 全部安装${NC}"
    echo -e "  ${BOLD}U) 全部卸载${NC}"
    echo -e "  ${BOLD}Q) 退出${NC}"
    echo ""
}

# ==================== 通过编号查找插件 ====================
find_plugin_by_index() {
    local target="$1"
    [[ "$target" =~ ^[0-9]+$ ]] || return 1

    local idx=1
    for plugin in "${PLUGIN_LIST[@]}"; do
        if [[ $idx -eq $target ]]; then
            echo "$plugin"
            return 0
        fi
        ((idx++))
    done
    return 1
}

find_plugin_by_key() {
    local key="$1"
    local plugin id cmd
    for plugin in "${PLUGIN_LIST[@]}"; do
        id=$(get_plugin_field "$plugin" 1)
        cmd=$(get_plugin_field "$plugin" 2)
        if [[ "$key" == "$id" || "$key" == "$cmd" ]]; then
            echo "$plugin"
            return 0
        fi
    done
    return 1
}

# ==================== 处理用户选择 ====================
process_choice() {
    local choice="$1"

    case "$choice" in
        [Aa])
            step "开始全部安装"
            do_full_install
            ;;
        [Uu])
            step "开始全部卸载"
            do_full_uninstall
            ;;
        [Qq])
            info "已退出"
            exit 0
            ;;
        *)
            local IFS=', '
            read -ra selections <<< "$choice"
            for sel in "${selections[@]}"; do
                sel=$(echo "$sel" | tr -d ' ')
                local plugin
                if plugin=$(find_plugin_by_index "$sel"); then
                    install_plugin "$plugin" || true
                else
                    warn "无效选择: $sel"
                fi
            done
            ;;
    esac
}

# ==================== 安装/卸载分发 ====================
install_plugin() {
    local plugin="$1"
    local id name cmd func
    id=$(get_plugin_field "$plugin" 1)
    cmd=$(get_plugin_field "$plugin" 2)
    name=$(get_plugin_field "$plugin" 3)
    func=$(get_plugin_field "$plugin" 5)

    if ! declare -f "$func" &>/dev/null; then
        warn "未找到安装函数: $func"
        record_result "$id" "failed" "插件接口不完整"
        return 1
    fi

    if "$func"; then
        local existing_status
        existing_status=$(get_result_status "$id" 2>/dev/null || true)
        if [[ "$existing_status" == "skipped" ]]; then
            return 0
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            record_result "$id" "planned" "$cmd"
            return 0
        fi

        if plugin_is_installed "$plugin"; then
            record_result "$id" "ok" "$cmd 可用"
            return 0
        fi

        record_result "$id" "failed" "$cmd 命令未检测到"
        return 1
    fi

    if ! get_result_status "$id" >/dev/null 2>&1; then
        record_result "$id" "failed" "$name 安装函数返回失败"
    fi
    return 1
}

install_tool() {
    local key="$1"
    local plugin
    if plugin=$(find_plugin_by_key "$key"); then
        install_plugin "$plugin"
    else
        warn "未找到工具: $key"
        return 1
    fi
}

uninstall_plugin() {
    local plugin="$1"
    local id func
    id=$(get_plugin_field "$plugin" 1)
    func=$(get_plugin_field "$plugin" 6)

    if declare -f "$func" &>/dev/null; then
        "$func"
    else
        warn "未找到卸载函数: $func"
        return 1
    fi
}

uninstall_tool() {
    local key="$1"
    local plugin
    if plugin=$(find_plugin_by_key "$key"); then
        uninstall_plugin "$plugin"
    else
        warn "未找到工具: $key"
        return 1
    fi
}

# ==================== 全部安装/卸载 ====================
do_full_install() {
    # 按插件注册顺序安装
    for plugin in "${PLUGIN_LIST[@]}"; do
        install_plugin "$plugin" || true
    done
}

do_full_uninstall() {
    echo ""
    echo -e "${RED}${BOLD}⚠ 警告: 这将卸载所有已注册的 AI CLI 工具:${NC}"
    for plugin in "${PLUGIN_LIST[@]}"; do
        local name
        name=$(get_plugin_field "$plugin" 3)
        echo "  - $name"
    done
    echo ""
    if confirm "确认全部卸载？" "N"; then
        # 反序卸载
        local i=$((${#PLUGIN_LIST[@]} - 1))
        while [[ $i -ge 0 ]]; do
            local cmd
            cmd=$(get_plugin_field "${PLUGIN_LIST[$i]}" 1)
            uninstall_tool "$cmd" || true
            i=$((i - 1))
        done
        success "全部卸载完成"
    else
        info "已取消卸载"
    fi
}

# ==================== 系统检查 ====================
system_check() {
    step "系统检查"
    check_ubuntu

    local os ver arch
    os=$(detect_os)
    ver=$(detect_version)
    arch=$(detect_arch)
    info "系统: $os $ver ($arch)"

    if [[ $EUID -eq 0 ]]; then
        warn "不建议以 root 身份运行此脚本"
        if ! confirm "  继续以 root 运行？" "N"; then
            exit 1
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN 模式跳过网络连通性检查"
    elif curl_install --max-time 5 https://github.com -o /dev/null 2>/dev/null; then
        success "网络连接正常"
    else
        warn "网络连通性检查失败，后续下载安装可能失败"
        if ! confirm "  是否继续？" "N"; then
            exit 1
        fi
    fi
}

# ==================== 系统预处理 ====================
do_system_setup() {
    echo ""
    echo -e "${BOLD}系统预处理:${NC}"
    echo "  1) 仅更新 apt 索引（推荐）"
    echo "  2) 更新 + 升级（较慢）"
    echo "  3) 跳过"
    echo ""
    if [[ "$FORCE_YES" == "true" || ! -t 0 ]]; then
        sys_choice="1"
        info "系统预处理自动选择: 1"
    else
        echo -n "选择 [1/2/3] (默认 1): "
        read -r sys_choice
    fi
    sys_choice="${sys_choice:-1}"

    case "$sys_choice" in
        1) apt_update && install_system_deps ;;
        2) apt_update && run_cmd sudo apt-get upgrade -y && install_system_deps ;;
        3) info "跳过系统预处理" ;;
        *) warn "无效选择，跳过" ;;
    esac
}

# ==================== 命令行参数 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)        DO_FULL_INSTALL=true; shift ;;
            --uninstall|-u)  DO_FULL_UNINSTALL=true; shift ;;
            --yes|-y)        FORCE_YES=true; shift ;;
            --dry-run)       DRY_RUN=true; shift ;;
            --node-version)
                if [[ $# -lt 2 || "$2" == --* ]]; then
                    error "--node-version 需要一个版本号，例如: --node-version 22"
                    exit 1
                fi
                export NODE_VERSION="$2"
                shift 2
                ;;
            --help|-h)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  无参数          交互式安装"
                echo "  --all, -a       一键安装全部"
                echo "  --uninstall, -u 一键卸载全部"
                echo "  --yes, -y       跳过确认"
                echo "  --dry-run       仅显示操作"
                echo "  --node-version  指定 Node.js 版本 (默认 22)"
                echo ""
                echo "新增工具: 在 lib/ 下创建 .sh 文件，调用 register_plugin 注册即可"
                exit 0
                ;;
            *) error "未知参数: $1"; exit 1 ;;
        esac
    done
}

# ==================== 主流程 ====================
DO_FULL_INSTALL=false
DO_FULL_UNINSTALL=false

parse_args "$@"
init_log
show_banner
system_check

if [[ "$DO_FULL_INSTALL" == "true" ]]; then
    do_system_setup
    do_full_install
    print_summary
    exit 0
fi

if [[ "$DO_FULL_UNINSTALL" == "true" ]]; then
    do_full_uninstall
    exit 0
fi

do_system_setup

while true; do
    clear_results
    show_menu
    echo -n -e "${BOLD}请选择要安装的工具 (编号，逗号分隔): ${NC}"
    read -r choice

    [[ -z "$choice" ]] && continue

    process_choice "$choice"
    print_summary

    echo ""
    if confirm "是否继续？" "N"; then
        echo ""
    else
        break
    fi
done

echo ""
success "操作完成！"
echo -e "${YELLOW}提示: 如果命令不可用，请运行: source ~/.bashrc 或重新打开终端${NC}"
echo -e "${YELLOW}日志: ${LOG_FILE}${NC}"
