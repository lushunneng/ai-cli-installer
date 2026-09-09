#!/usr/bin/env bash
# common.sh - 公共函数库 v3 (插件式架构)

set -eo pipefail

# ==================== 全局配置 ====================
CURL_TIMEOUT=60
CURL_RETRY=2
DRY_RUN=false
FORCE_YES=false
LOG_FILE=""

# ==================== 插件注册表 ====================
# 新增工具只需在 lib/ 下放一个 .sh 文件，按规范实现接口即可
# 无需修改 install.sh 或 common.sh
PLUGIN_LIST=()        # 有序列表: "id|cmd|name|desc|install_func|uninstall_func"

register_plugin() {
    local id="$1" cmd="$2" name="$3" desc="$4"
    local safe_id install_func uninstall_func
    safe_id="${id//-/_}"
    install_func="${5:-install_${safe_id}}"
    uninstall_func="${6:-uninstall_${safe_id}}"

    local plugin existing_id
    for plugin in "${PLUGIN_LIST[@]}"; do
        existing_id=$(get_plugin_field "$plugin" 1)
        if [[ "$existing_id" == "$id" ]]; then
            warn "插件重复注册，已跳过: $id"
            return 0
        fi
    done

    PLUGIN_LIST+=("${id}|${cmd}|${name}|${desc}|${install_func}|${uninstall_func}")
}

get_plugin_field() {
    local plugin_str="$1" field="$2"
    echo "$plugin_str" | cut -d'|' -f"$field"
}

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# ==================== 日志函数 ====================
_log() {
    local level="$1"; shift
    local msg="$*"
    echo -e "$msg"
    [[ -n "$LOG_FILE" ]] && echo -e "$(date '+%Y-%m-%d %H:%M:%S') [$level] $msg" >> "$LOG_FILE"
    return 0
}

info()    { _log "INFO" "${BLUE}[INFO]${NC} $*"; }
success() { _log "OK"   "${GREEN}[OK]${NC} $*"; }
warn()    { _log "WARN" "${YELLOW}[WARN]${NC} $*"; }
error()   { _log "ERROR" "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}>>> $*${NC}"; }

# ==================== DRY_RUN ====================
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

# ==================== 工具检查 ====================
command_exists() {
    command -v "$1" &>/dev/null
}

is_installed() {
    local cmd="$1"
    if command_exists "$cmd"; then
        local version
        version=$("$cmd" --version 2>/dev/null | head -n1 || echo "unknown")
        success "$cmd 已安装 ($version)"
        return 0
    fi
    return 1
}

load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
}

plugin_is_installed() {
    local plugin_str="$1"
    local id cmd
    id=$(get_plugin_field "$plugin_str" 1)
    cmd=$(get_plugin_field "$plugin_str" 2)

    case "$id" in
        nvm)
            load_nvm
            [[ -s "$HOME/.nvm/nvm.sh" ]] && command_exists node && command_exists npm
            ;;
        *)
            command_exists "$cmd"
            ;;
    esac
}

download_and_run() {
    local label="$1" url="$2" runner="${3:-bash}"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] 下载并执行 $label: $url"
        return 0
    fi

    local tmp
    tmp=$(mktemp)

    if curl_install "$url" -o "$tmp"; then
        if "$runner" "$tmp"; then
            rm -f "$tmp"
            return 0
        fi
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"
    return 1
}

# ==================== 系统检测 ====================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

detect_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$VERSION_ID"
    else
        echo "unknown"
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)   echo "arm64" ;;
        *)               echo "$arch" ;;
    esac
}

check_ubuntu() {
    local os
    os=$(detect_os)
    if [[ "$os" != "ubuntu" ]]; then
        warn "当前系统为 ${os}，脚本仅在 Ubuntu 22.04/24.04 上测试过"
        if ! confirm "  是否继续？" "N"; then
            exit 0
        fi
    fi
}

# ==================== 确认函数 ====================
confirm() {
    local prompt="${1:-继续？}"
    local default="${2:-Y}"
    if [[ "$FORCE_YES" == "true" ]]; then
        info "自动确认 (--yes)"
        return 0
    fi
    local hint
    [[ "$default" == "Y" ]] && hint="Y/n" || hint="y/N"
    echo -n -e "${prompt} (${hint}): "
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ==================== 网络 ====================
curl_install() {
    curl -fsSL --max-time "$CURL_TIMEOUT" --retry "$CURL_RETRY" --retry-delay 3 "$@"
}

# ==================== apt 操作 ====================
apt_update() {
    local retries=3
    for ((i=1; i<=retries; i++)); do
        if run_cmd sudo apt-get update -y 2>/dev/null; then
            return 0
        fi
        if [[ $i -lt $retries ]]; then
            warn "apt 被占用，等待 15 秒后重试 ($i/$retries)..."
            sleep 15
        fi
    done
    error "apt-get update 失败"
    return 1
}

apt_install() {
    local retries=3
    for ((i=1; i<=retries; i++)); do
        if run_cmd sudo apt-get install -y "$@"; then
            return 0
        fi
        if [[ $i -lt $retries ]]; then
            warn "apt 被占用，等待 15 秒后重试 ($i/$retries)..."
            sleep 15
        fi
    done
    error "apt-get install 失败"
    return 1
}

apt_upgrade() {
    local retries=3
    for ((i=1; i<=retries; i++)); do
        if run_cmd sudo apt-get upgrade -y; then
            return 0
        fi
        if [[ $i -lt $retries ]]; then
            warn "apt 升级失败，等待 15 秒后重试 ($i/$retries)..."
            sleep 15
        fi
    done
    error "apt-get upgrade 失败"
    return 1
}

install_system_deps() {
    step "安装基础依赖"
    apt_install curl wget git build-essential ca-certificates gnupg lsb-release
    success "基础依赖已安装"
}

# ==================== PATH 管理 ====================
ensure_in_path() {
    local dir="$1"
    if [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$dir:$PATH"
        local begin_marker="# ai-cli-installer PATH begin: $dir"
        local end_marker="# ai-cli-installer PATH end"
        local profiles=()
        [[ -f "$HOME/.bashrc" ]]        && profiles+=("$HOME/.bashrc")
        [[ -f "$HOME/.profile" ]]       && profiles+=("$HOME/.profile")
        [[ -f "$HOME/.zshrc" ]]         && profiles+=("$HOME/.zshrc")
        [[ -f "$HOME/.bash_profile" ]]  && profiles+=("$HOME/.bash_profile")

        for profile in "${profiles[@]}"; do
            if ! grep -Fq "$begin_marker" "$profile" 2>/dev/null; then
                {
                    echo ""
                    echo "$begin_marker"
                    echo "export PATH=\"$dir:\$PATH\""
                    echo "$end_marker"
                } >> "$profile"
                info "已将 $dir 添加到 $profile"
            fi
        done
    fi
}

clean_path_from_profiles() {
    local dir="${1:-}"
    local profiles=("$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc" "$HOME/.bash_profile")
    local tmp begin_marker
    for profile in "${profiles[@]}"; do
        [[ -f "$profile" ]] || continue

        tmp=$(mktemp)
        if [[ -n "$dir" ]]; then
            begin_marker="# ai-cli-installer PATH begin: $dir"
            if grep -Fq "$begin_marker" "$profile" 2>/dev/null; then
                sed "\|$begin_marker|,|# ai-cli-installer PATH end|d" "$profile" > "$tmp"
                mv "$tmp" "$profile"
                info "已清理 $profile 中的 PATH 标记: $dir"
            else
                rm -f "$tmp"
            fi
        else
            if grep -q "# ai-cli-installer PATH" "$profile" 2>/dev/null; then
                sed "/# ai-cli-installer PATH begin:/,/# ai-cli-installer PATH end/d; /# ai-cli-installer PATH/,/# ai-cli-installer PATH/d" "$profile" > "$tmp"
                mv "$tmp" "$profile"
                info "已清理 $profile 中的 PATH 标记"
            else
                rm -f "$tmp"
            fi
        fi
    done
}

# ==================== 插件自动加载 ====================
load_plugins() {
    local plugin_dir="${1:-$SCRIPT_DIR/lib}"
    local plugin_file

    if [[ -f "$plugin_dir/node.sh" ]]; then
        # shellcheck source=/dev/null
        source "$plugin_dir/node.sh"
    fi

    for plugin_file in "$plugin_dir"/*.sh; do
        [[ -f "$plugin_file" ]] || continue
        # 跳过 common.sh 和模板文件
        [[ "$(basename "$plugin_file")" == "common.sh" ]] && continue
        [[ "$(basename "$plugin_file")" == "node.sh" ]] && continue
        [[ "$(basename "$plugin_file")" == _* ]] && continue
        # shellcheck source=/dev/null
        source "$plugin_file"
    done
}

# ==================== 安装结果追踪 ====================
INSTALL_RESULTS=() # "id|status|detail"

record_result() {
    local tool="$1"
    local status="$2"
    local detail="${3:-}"
    local i existing_tool

    for ((i=0; i<${#INSTALL_RESULTS[@]}; i++)); do
        existing_tool=$(get_plugin_field "${INSTALL_RESULTS[$i]}" 1)
        if [[ "$existing_tool" == "$tool" ]]; then
            INSTALL_RESULTS[i]="${tool}|${status}|${detail}"
            return 0
        fi
    done

    INSTALL_RESULTS+=("${tool}|${status}|${detail}")
}

get_result_status() {
    local tool="$1"
    local result existing_tool
    for result in "${INSTALL_RESULTS[@]}"; do
        existing_tool=$(get_plugin_field "$result" 1)
        if [[ "$existing_tool" == "$tool" ]]; then
            get_plugin_field "$result" 2
            return 0
        fi
    done
    return 1
}

get_result_detail() {
    local tool="$1"
    local result existing_tool
    for result in "${INSTALL_RESULTS[@]}"; do
        existing_tool=$(get_plugin_field "$result" 1)
        if [[ "$existing_tool" == "$tool" ]]; then
            get_plugin_field "$result" 3
            return 0
        fi
    done
    return 1
}

clear_results() {
    INSTALL_RESULTS=()
}

print_summary() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}          安装结果汇总${NC}"
    echo -e "${BOLD}========================================${NC}"
    if [[ ${#INSTALL_RESULTS[@]} -eq 0 ]]; then
        echo "  本轮没有执行安装任务"
        echo -e "${BOLD}========================================${NC}"
        return 0
    fi

    for plugin in "${PLUGIN_LIST[@]}"; do
        local id name status detail
        id=$(get_plugin_field "$plugin" 1)
        name=$(get_plugin_field "$plugin" 3)
        status=$(get_result_status "$id" 2>/dev/null) || continue
        detail=$(get_result_detail "$id" 2>/dev/null || true)
        case "$status" in
            ok)      echo -e "  ${GREEN}✓${NC} $name 安装成功${detail:+ - $detail}" ;;
            failed)  echo -e "  ${RED}✗${NC} $name 安装失败${detail:+ - $detail}" ;;
            skipped) echo -e "  ${YELLOW}-${NC} $name 已跳过${detail:+ - $detail}" ;;
            planned) echo -e "  ${CYAN}•${NC} $name dry-run 已计划${detail:+ - $detail}" ;;
        esac
    done
    echo -e "${BOLD}========================================${NC}"
}

# ==================== 清理陷阱 ====================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warn "脚本被中断或出错 (exit code: $exit_code)，部分安装可能未完成"
        [[ ${#INSTALL_RESULTS[@]} -gt 0 ]] && print_summary
    fi
}
trap cleanup EXIT

# ==================== 日志初始化 ====================
init_log() {
    LOG_FILE="/tmp/ai-cli-installer-$(date +%Y%m%d-%H%M%S).log"
    info "日志文件: $LOG_FILE"
}
