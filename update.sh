#!/usr/bin/env bash
# update.sh - 检查并更新已安装的 AI CLI 工具

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
load_plugins "${SCRIPT_DIR}/lib"

DO_ALL=false
CHECK_ONLY=false
FORCE_UPDATE=false
UPDATE_APT_INDEX=false
UPDATE_SYSTEM=false
UPDATE_KERNEL=false

show_help() {
    cat << EOF
用法: $0 [选项]

选项:
  --apt           刷新 APT 仓库索引
  --system        刷新 APT 索引并升级已安装的软件包
  --kernel        安装 Ubuntu 最新通用内核元包（同时刷新 APT 索引）
  无参数          交互式检查并选择更新
  --all, -a       更新所有检测为可更新的工具
  --force, -f     配合 --all 时，强制更新所有已安装工具
  --check-only    只检查版本，不执行更新
  --yes, -y       跳过确认
  --dry-run       只显示将执行的更新命令
  --help, -h      显示帮助
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)      DO_ALL=true; shift ;;
            --force|-f)    FORCE_UPDATE=true; shift ;;
            --check-only)  CHECK_ONLY=true; shift ;;
            --yes|-y)      FORCE_YES=true; shift ;;
            --apt)         UPDATE_APT_INDEX=true; shift ;;
            --system)      UPDATE_SYSTEM=true; shift ;;
            --kernel)      UPDATE_KERNEL=true; shift ;;
            --dry-run)     DRY_RUN=true; shift ;;
            --help|-h)     show_help; exit 0 ;;
            *) error "未知参数: $1"; exit 1 ;;
        esac
    done
}

strip_version_prefix() {
    local version="${1:-}"
    version="${version#v}"
    version="${version%%-*}"
    version="${version%%+*}"
    echo "$version"
}

extract_semver() {
    local text="${1:-}"
    echo "$text" | grep -Eo 'v?[0-9]+([.][0-9]+){1,3}([-+][0-9A-Za-z.-]+)?' | head -n1 | sed 's/^v//'
}

version_gt() {
    local left right
    left=$(strip_version_prefix "$1")
    right=$(strip_version_prefix "$2")

    local l_major l_minor l_patch r_major r_minor r_patch
    IFS='.' read -r l_major l_minor l_patch _ <<< "$left"
    IFS='.' read -r r_major r_minor r_patch _ <<< "$right"

    l_major=${l_major:-0}; l_minor=${l_minor:-0}; l_patch=${l_patch:-0}
    r_major=${r_major:-0}; r_minor=${r_minor:-0}; r_patch=${r_patch:-0}

    [[ "$l_major" =~ ^[0-9]+$ ]] || l_major=0
    [[ "$l_minor" =~ ^[0-9]+$ ]] || l_minor=0
    [[ "$l_patch" =~ ^[0-9]+$ ]] || l_patch=0
    [[ "$r_major" =~ ^[0-9]+$ ]] || r_major=0
    [[ "$r_minor" =~ ^[0-9]+$ ]] || r_minor=0
    [[ "$r_patch" =~ ^[0-9]+$ ]] || r_patch=0

    if (( l_major > r_major )); then return 0; fi
    if (( l_major < r_major )); then return 1; fi
    if (( l_minor > r_minor )); then return 0; fi
    if (( l_minor < r_minor )); then return 1; fi
    (( l_patch > r_patch ))
}

version_eq() {
    [[ "$(strip_version_prefix "$1")" == "$(strip_version_prefix "$2")" ]]
}

json_string_field() {
    local field="$1"
    sed -nE "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"v?([^\"]+)\".*/\\1/p" | head -n1
}

github_latest_release() {
    local owner="$1" repo="$2"
    curl -fsSL --connect-timeout 5 --max-time 10 "https://api.github.com/repos/${owner}/${repo}/releases/latest" 2>/dev/null \
        | json_string_field "tag_name" \
        | sed 's/^v//'
}

pypi_latest_version() {
    local package="$1"
    curl -fsSL --connect-timeout 5 --max-time 10 "https://pypi.org/pypi/${package}/json" 2>/dev/null \
        | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        | head -n1
}

npm_latest_version() {
    local package="$1"
    load_nvm
    command_exists npm || return 1
    npm --fetch-timeout=8000 --fetch-retries=0 --prefer-online view "$package" version 2>/dev/null | tail -n1
}

current_version_for() {
    local id="$1" cmd="$2"

    case "$id" in
        nvm)
            load_nvm
            command_exists nvm || return 1
            nvm --version 2>/dev/null
            ;;
        herdr)
            if "$cmd" status client --json >/dev/null 2>&1; then
                "$cmd" status client --json 2>/dev/null | json_string_field "version"
            else
                extract_semver "$("$cmd" --version 2>/dev/null | head -n1)"
            fi
            ;;
        *)
            command_exists "$cmd" || return 1
            extract_semver "$("$cmd" --version 2>/dev/null | head -n1)"
            ;;
    esac
}

latest_version_for() {
    local id="$1"

    case "$id" in
        nvm)         github_latest_release "nvm-sh" "nvm" ;;
        claude-code) npm_latest_version "@anthropic-ai/claude-code" ;;
        codex)       npm_latest_version "@openai/codex" ;;
        grok)        npm_latest_version "@xai-official/grok" ;;
        herdr)       github_latest_release "herdrdev" "herdr" ;;
        opencode)    npm_latest_version "opencode-ai" ;;
        kimi)        pypi_latest_version "kimi-cli" ;;
        qoder)       npm_latest_version "@qoder-ai/qodercli" ;;
        *)           return 1 ;;
    esac
}

installed_for() {
    local id="$1" cmd="$2"
    if [[ "$id" == "nvm" ]]; then
        [[ -d "$HOME/.nvm" ]]
        return
    fi
    command_exists "$cmd"
}

status_for_versions() {
    local current="$1" latest="$2"

    if [[ -z "$current" || "$current" == "unknown" ]]; then
        echo "unknown"
    elif [[ -z "$latest" || "$latest" == "unknown" ]]; then
        echo "unknown"
    elif version_eq "$current" "$latest"; then
        echo "latest"
    elif version_gt "$latest" "$current"; then
        echo "outdated"
    else
        echo "latest"
    fi
}

status_label() {
    case "$1" in
        latest)        echo "${GREEN}[最新]${NC}" ;;
        outdated)      echo "${YELLOW}[可更新]${NC}" ;;
        unknown)       echo "${YELLOW}[未知]${NC}" ;;
        not-installed) echo "${CYAN}[未安装]${NC}" ;;
        *)             echo "[$1]" ;;
    esac
}

update_plugin() {
    local plugin="$1"
    local id cmd name install_func old_force
    id=$(get_plugin_field "$plugin" 1)
    cmd=$(get_plugin_field "$plugin" 2)
    name=$(get_plugin_field "$plugin" 3)
    install_func=$(get_plugin_field "$plugin" 5)

    step "更新 $name"

    old_force="$FORCE_YES"
    FORCE_YES=true

    case "$id" in
        claude-code)
            if command_exists claude && run_cmd claude update; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
        codex)
            if command_exists codex && run_cmd codex update; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
        herdr)
            if command_exists herdr && run_cmd herdr update; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
        opencode)
            if command_exists opencode && run_cmd opencode upgrade latest; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
        kimi)
            if command_exists uv && run_cmd uv tool upgrade kimi-cli --no-cache; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
        qoder)
            load_nvm
            if command_exists npm && run_cmd npm install -g @qoder-ai/qodercli@latest; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
        system-tools)
            if apt_update && run_cmd sudo apt-get install -y --only-upgrade \
                ripgrep fd-find bat jq tree htop tmux mosh zip unzip build-essential; then
                FORCE_YES="$old_force"
                return 0
            fi
            ;;
    esac

    if declare -f "$install_func" >/dev/null 2>&1; then
        "$install_func"
    else
        FORCE_YES="$old_force"
        error "未找到更新函数: $install_func"
        return 1
    fi

    FORCE_YES="$old_force"
}

SCAN_ROWS=()      # idx|plugin_pos|status|current|latest
UPDATABLE_INDEXES=()
INSTALLED_INDEXES=()

scan_versions() {
    SCAN_ROWS=()
    UPDATABLE_INDEXES=()
    INSTALLED_INDEXES=()

    local idx=1
    local plugin_pos plugin id cmd current latest status
    for plugin in "${PLUGIN_LIST[@]}"; do
        plugin_pos=$((idx - 1))
        id=$(get_plugin_field "$plugin" 1)
        cmd=$(get_plugin_field "$plugin" 2)

        if ! installed_for "$id" "$cmd"; then
            status="not-installed"
            current="-"
            latest="-"
        else
            current=$(current_version_for "$id" "$cmd" 2>/dev/null || echo "unknown")
            current="${current:-unknown}"
            latest=$(latest_version_for "$id" 2>/dev/null || echo "unknown")
            latest="${latest:-unknown}"
            status=$(status_for_versions "$current" "$latest")
            INSTALLED_INDEXES+=("$idx")
            if [[ "$status" == "outdated" ]]; then
                UPDATABLE_INDEXES+=("$idx")
            fi
        fi

        SCAN_ROWS+=("${idx}|${plugin_pos}|${status}|${current}|${latest}")
        idx=$((idx + 1))
    done
}

print_scan_table() {
    echo ""
    echo -e "${BOLD}工具版本检查:${NC}"
    echo ""
    printf "  %-4s %-12s %-28s %-16s %-16s\n" "编号" "状态" "工具" "当前版本" "最新版本"
    printf "  %-4s %-12s %-28s %-16s %-16s\n" "----" "------------" "----------------------------" "----------------" "----------------"

    local row idx plugin_pos plugin status current latest name
    for row in "${SCAN_ROWS[@]}"; do
        idx=$(get_plugin_field "$row" 1)
        plugin_pos=$(get_plugin_field "$row" 2)
        plugin="${PLUGIN_LIST[$plugin_pos]}"
        status=$(get_plugin_field "$row" 3)
        current=$(get_plugin_field "$row" 4)
        latest=$(get_plugin_field "$row" 5)
        name=$(get_plugin_field "$plugin" 3)
        printf "  %-4s %-20b %-28s %-16s %-16s\n" "$idx" "$(status_label "$status")" "$name" "$current" "$latest"
    done
    echo ""
}

find_row_by_index() {
    local target="$1"
    local row idx
    for row in "${SCAN_ROWS[@]}"; do
        idx=$(get_plugin_field "$row" 1)
        if [[ "$idx" == "$target" ]]; then
            echo "$row"
            return 0
        fi
    done
    return 1
}

run_updates_for_indexes() {
    local indexes=("$@")
    local idx row plugin_pos plugin status

    if [[ ${#indexes[@]} -eq 0 ]]; then
        info "没有需要更新的工具"
        return 0
    fi

    for idx in "${indexes[@]}"; do
        row=$(find_row_by_index "$idx") || {
            warn "无效编号: $idx"
            continue
        }
        plugin_pos=$(get_plugin_field "$row" 2)
        plugin="${PLUGIN_LIST[$plugin_pos]}"
        status=$(get_plugin_field "$row" 3)

        if [[ "$status" == "not-installed" ]]; then
            warn "$(get_plugin_field "$plugin" 3) 未安装，跳过"
            continue
        fi

        update_plugin "$plugin" || warn "$(get_plugin_field "$plugin" 3) 更新失败"
    done
}

interactive_update() {
    if [[ ${#UPDATABLE_INDEXES[@]} -eq 0 ]]; then
        info "未发现明确可更新的工具"
    fi

    echo -e "  ${BOLD}A) 更新所有可更新工具${NC}"
    echo -e "  ${BOLD}F) 强制更新所有已安装工具${NC}"
    echo -e "  ${BOLD}S) 更新系统软件包${NC}"
    echo -e "  ${BOLD}K) 更新 Ubuntu 通用内核${NC}"
    echo -e "  ${BOLD}Q) 退出${NC}"
    echo ""
    echo -n -e "${BOLD}请选择要更新的工具编号（逗号分隔）: ${NC}"
    read -r choice

    case "$choice" in
        [Aa]) run_updates_for_indexes "${UPDATABLE_INDEXES[@]}" ;;
        [Ss]) update_system_packages ;;
        [Kk]) update_kernel ;;
        [Ff]) run_updates_for_indexes "${INSTALLED_INDEXES[@]}" ;;
        [Qq]|"") info "已退出" ;;
        *)
            local IFS=', '
            local selections=()
            read -ra selections <<< "$choice"
            run_updates_for_indexes "${selections[@]}"
            ;;
    esac
}

update_apt_index() {
    step "刷新 APT 仓库索引"
    apt_update
}

update_system_packages() {
    step "更新系统软件包"
    apt_update && apt_upgrade
}

update_kernel() {
    step "更新 Ubuntu 通用内核"
    if [[ "$(detect_os)" != "ubuntu" ]]; then
        error "内核元包更新仅支持 Ubuntu"
        return 1
    fi
    apt_update && apt_install --install-recommends linux-generic
}

parse_args "$@"
init_log

echo -e "${BOLD}${CYAN}AI CLI 工具更新检查${NC}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}模式: DRY-RUN${NC}"
echo -e "已注册工具: ${#PLUGIN_LIST[@]}"

if [[ "$CHECK_ONLY" == "true" ]]; then
    scan_versions
    print_scan_table
    exit 0
fi

if [[ "$UPDATE_APT_INDEX" == "true" ]]; then
    update_apt_index
fi
if [[ "$UPDATE_SYSTEM" == "true" ]]; then
    update_system_packages
fi
if [[ "$UPDATE_KERNEL" == "true" ]]; then
    update_kernel
fi
if [[ "$UPDATE_APT_INDEX" == "true" || "$UPDATE_SYSTEM" == "true" || "$UPDATE_KERNEL" == "true" ]] && [[ "$DO_ALL" != "true" ]]; then
    success "系统更新完成"
    exit 0
fi

scan_versions
print_scan_table

if [[ "$DO_ALL" == "true" ]]; then
    if [[ "$FORCE_UPDATE" == "true" ]]; then
        run_updates_for_indexes "${INSTALLED_INDEXES[@]}"
    else
        run_updates_for_indexes "${UPDATABLE_INDEXES[@]}"
    fi
else
    interactive_update
fi

echo ""
success "更新检查完成"
echo -e "${YELLOW}提示: 如果命令不可用，请运行: source ~/.bashrc 或重新打开终端${NC}"
echo -e "${YELLOW}日志: ${LOG_FILE}${NC}"
