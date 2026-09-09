#!/usr/bin/env bash
# uninstall.sh - AI CLI 工具卸载脚本 v3 (插件式架构)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
load_plugins "${SCRIPT_DIR}/lib"

find_plugin_by_id() {
    local target="$1"
    local plugin id
    for plugin in "${PLUGIN_LIST[@]}"; do
        id=$(get_plugin_field "$plugin" 1)
        if [[ "$id" == "$target" ]]; then
            echo "$plugin"
            return 0
        fi
    done
    return 1
}

show_uninstall_menu() {
    echo -e "${BOLD}${RED}"
    cat << 'EOF'
    _        _____ _     _____ ____  ____
   / \   ___|_   _| |   | ____|  _ \| __ )
  / _ \ / _ \ | | | |   |  _| | | | |  _ \
 / ___ \ (_) || | | |___| |___| |_| | |_) |
/_/   \_\___/ |_| |_____|_____|____/|____@

  AI CLI 工具卸载器 v3
EOF
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}已检测到的工具:${NC}"
    echo ""

    local idx=1
    local UNINSTALL_MAP=()

    for plugin in "${PLUGIN_LIST[@]}"; do
        local id cmd name
        id=$(get_plugin_field "$plugin" 1)
        cmd=$(get_plugin_field "$plugin" 2)
        name=$(get_plugin_field "$plugin" 3)

        local installed=false
        if [[ "$cmd" == "nvm" ]]; then
            [[ -d "$HOME/.nvm" ]] && installed=true
        else
            command_exists "$cmd" 2>/dev/null && installed=true
        fi

        if [[ "$installed" == "true" ]]; then
            echo -e "  ${GREEN}[已安装]${NC} $idx) $name"
            UNINSTALL_MAP+=("$idx|$id")
        else
            echo -e "  $idx) $name ${YELLOW}(未安装)${NC}"
        fi
        ((idx++))
    done

    echo ""
    echo -e "  ${BOLD}A) 全部卸载${NC}"
    echo -e "  ${BOLD}Q) 退出${NC}"
    echo ""

    echo -n -e "${BOLD}请选择要卸载的工具: ${NC}"
    read -r choice

    case "$choice" in
        [Aa])
            echo ""
            echo -e "${RED}${BOLD}⚠ 警告: 这将卸载所有 AI CLI 工具！${NC}"
            if confirm "确认？" "N"; then
                local i=$((${#PLUGIN_LIST[@]} - 1))
                while [[ $i -ge 0 ]]; do
                    local cmd
                    cmd=$(get_plugin_field "${PLUGIN_LIST[$i]}" 6)
                    local func="$cmd"
                    declare -f "$func" &>/dev/null && "$func"
                    i=$((i - 1))
                done
                echo ""
                success "全部卸载完成"
            else
                info "已取消"
            fi
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
                local item item_idx tool plugin func
                tool=""
                for item in "${UNINSTALL_MAP[@]}"; do
                    item_idx=$(get_plugin_field "$item" 1)
                    if [[ "$item_idx" == "$sel" ]]; then
                        tool=$(get_plugin_field "$item" 2)
                        break
                    fi
                done

                if [[ -n "$tool" ]] && plugin=$(find_plugin_by_id "$tool"); then
                    func=$(get_plugin_field "$plugin" 6)
                    declare -f "$func" &>/dev/null && "$func"
                else
                    warn "无效选择: $sel"
                fi
            done
            echo ""
            success "卸载完成"
            ;;
    esac

    echo -e "${YELLOW}提示: 请重新打开终端或运行: source ~/.bashrc${NC}"
}

show_uninstall_menu
