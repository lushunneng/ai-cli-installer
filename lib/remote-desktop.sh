#!/usr/bin/env bash
# remote-desktop.sh - XFCE + XRDP + Tailscale 轻量级远程桌面模块
# 仅通过 Tailscale 提供推荐访问路径，不自动开放公网 3389。

REMOTE_DESKTOP_PACKAGES=(xfce4 xfce4-goodies xfce4-session xrdp xorgxrdp dbus-x11)
CHROME_DOWNLOAD_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
CHROME_DESKTOP_FILE="google-chrome.desktop"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
RDP_USER="${RDP_USER:-}"
REMOTE_DESKTOP_BACKUP_ROOT="/var/backups/ai-cli-installer/remote-desktop"

register_plugin "remote-desktop" "xrdp" "轻量级远程桌面" "XFCE + XRDP + Tailscale 安全远程桌面"

remote_desktop_supported() {
    local os ver
    os=$(detect_os); ver=$(detect_version)
    { [[ "$os" == ubuntu && "$ver" == 22.04 ]] || [[ "$os" == ubuntu && "$ver" == 24.04 ]] ||
      [[ "$os" == ubuntu && "$ver" == 26.04 ]] || [[ "$os" == debian && "$ver" == 12 ]]; }
}

remote_desktop_require_root() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    fi
    if command_exists sudo; then
        return 0
    fi
    error "远程桌面安装和系统修复需要 root 或可用 sudo 权限"
    return 1
}

remote_desktop_backup_file() {
    local file="$1"
    [[ -e "$file" ]] || return 0
    local dir="$REMOTE_DESKTOP_BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    run_cmd sudo mkdir -p "$dir"
    run_cmd sudo cp -a "$file" "$dir/"
    info "已备份 $file 到 $dir"
}

remote_desktop_pick_user() {
    if [[ -n "$RDP_USER" ]] && id "$RDP_USER" &>/dev/null && [[ "$RDP_USER" != root ]]; then
        return 0
    fi
    local candidate
    candidate=$(who 2>/dev/null | awk '$1 != "root" {print $1; exit}' || true)
    if [[ -n "$candidate" ]] && id "$candidate" &>/dev/null; then
        RDP_USER="$candidate"
        return 0
    fi
    candidate=$(ps -eo user=,args= 2>/dev/null | awk '$2 ~ /(xrdp-sesman|Xorg)/ && $1 != "root" {print $1; exit}' || true)
    if [[ -n "$candidate" ]] && id "$candidate" &>/dev/null; then
        RDP_USER="$candidate"
        return 0
    fi
    candidate=$(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd 2>/dev/null || true)
    if [[ -n "$candidate" ]]; then
        RDP_USER="$candidate"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        RDP_USER="rdpuser"
        info "[DRY-RUN] 未检测到普通用户，将使用示例用户 $RDP_USER"
        return 0
    fi
    read -r -p "请输入用于 XRDP 的普通用户名（不会使用 root）: " RDP_USER
    [[ -n "$RDP_USER" && "$RDP_USER" != root ]] || { error "必须指定非 root 用户"; return 1; }
    if ! id "$RDP_USER" &>/dev/null; then
        if ! confirm "用户 $RDP_USER 不存在，创建该用户？" "N"; then return 1; fi
        run_cmd useradd -m -s /bin/bash "$RDP_USER" || return 1
        info "请在终端中为 $RDP_USER 设置密码（密码不会被脚本读取、记录或保存）"
        run_cmd passwd "$RDP_USER" || return 1
    fi
}

remote_desktop_user_home() {
    [[ -n "${RDP_USER:-}" ]] || return 1
    local home
    home=$(getent passwd "$RDP_USER" | cut -d: -f6 || true)
    if [[ -n "$home" ]]; then
        echo "$home"
    elif [[ "$DRY_RUN" == true ]]; then
        echo "/home/$RDP_USER"
    else
        return 1
    fi
}

remote_desktop_find_display() {
    local display
    [[ -n "${DISPLAY:-}" ]] && { echo "$DISPLAY"; return 0; }
    display=$(ps -u "$RDP_USER" -o args= 2>/dev/null \
        | sed -nE 's/.*X(org|wayland).*(:[0-9]+).*/\2/p' | head -n1 || true)
    [[ -n "$display" ]] && echo "$display"
}

remote_desktop_user_exec() {
    local home display
    home=$(remote_desktop_user_home) || return 1
    display=$(remote_desktop_find_display || true)
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] 以 $RDP_USER 身份执行: $*"
        return 0
    fi
    local -a env_args=(HOME="$home" USER="$RDP_USER" LOGNAME="$RDP_USER")
    [[ -n "$display" ]] && env_args+=(DISPLAY="$display")
    [[ -n "${XAUTHORITY:-}" ]] && env_args+=(XAUTHORITY="$XAUTHORITY")
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && env_args+=(DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS")
    [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] && env_args+=(XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP")
    [[ -n "${XDG_SESSION_TYPE:-}" ]] && env_args+=(XDG_SESSION_TYPE="$XDG_SESSION_TYPE")
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] && env_args+=(XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR")
    if [[ $EUID -eq 0 ]]; then
        if command_exists sudo; then
            sudo -u "$RDP_USER" env "${env_args[@]}" "$@"
        else
            runuser -u "$RDP_USER" -- env "${env_args[@]}" "$@"
        fi
    else
        sudo -u "$RDP_USER" env "${env_args[@]}" "$@"
    fi
}

chrome_installed() {
    command_exists google-chrome || command_exists google-chrome-stable
}

chrome_command() {
    if command_exists google-chrome; then
        command -v google-chrome
    elif command_exists google-chrome-stable; then
        command -v google-chrome-stable
    else
        return 1
    fi
}

install_chrome() {
    remote_desktop_require_root || return 1
    remote_desktop_supported || { error "Chrome 远程桌面集成支持 Debian 12、Ubuntu 22.04、24.04、26.04"; return 1; }
    [[ "$(detect_arch)" == amd64 ]] || {
        error "Google Chrome 官方 stable .deb 当前仅支持 amd64/x86_64；检测到 $(detect_arch)，已停止安装"
        return 1
    }

    if chrome_installed; then
        success "Google Chrome is already installed."
        local installed_bin
        installed_bin=$(chrome_command)
        "$installed_bin" --version 2>/dev/null || true
    else
        step "安装 Google Chrome"
        local tmp
        tmp=$(mktemp --suffix=.deb)
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] 下载官方 Google Chrome Stable .deb: $CHROME_DOWNLOAD_URL"
            info "[DRY-RUN] apt install -y $tmp"
            rm -f "$tmp"
            return 0
        fi
        command_exists apt || { rm -f "$tmp"; error "系统缺少 apt，无法安装本地 Chrome .deb"; return 1; }
        if ! curl_install "$CHROME_DOWNLOAD_URL" -o "$tmp"; then
            rm -f "$tmp"
            error "Google Chrome .deb 下载失败: $CHROME_DOWNLOAD_URL"
            return 1
        fi
        if ! run_cmd sudo apt install -y "$tmp"; then
            rm -f "$tmp"
            error "Google Chrome 本地 .deb 安装失败"
            return 1
        fi
        rm -f "$tmp"
        chrome_installed || { error "Chrome 安装命令完成，但未找到 google-chrome 可执行文件"; return 1; }
        success "Chrome installed"
        local installed_bin
        installed_bin=$(chrome_command)
        "$installed_bin" --version 2>/dev/null || true
    fi
    if [[ -n "${RDP_USER:-}" ]] || RDP_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd 2>/dev/null); then
        set_default_browser || warn "Chrome 已安装，但默认浏览器配置未完成；请执行 --remote-desktop repair-browser"
    else
        warn "未找到普通桌面用户；Chrome 已安装，请在 XRDP 用户准备好后执行 --remote-desktop set-default-browser"
    fi
}

set_default_browser() {
    remote_desktop_require_root || return 1
    remote_desktop_pick_user || return 1
    local home mime_file desktop_dir
    home=$(remote_desktop_user_home) || { error "无法找到 $RDP_USER 的 Home 目录"; return 1; }
    mime_file="$home/.config/mimeapps.list"
    desktop_dir="$home/.local/share/applications"
    remote_desktop_backup_file "$mime_file"
    remote_desktop_backup_file "$home/.config/xfce4/helpers.rc"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] 为 $RDP_USER 设置 HTTP/HTTPS/HTML 默认处理器为 $CHROME_DESKTOP_FILE"
        return 0
    fi
    chrome_installed || { error "Chrome 未安装，无法设置默认浏览器"; return 1; }
    command_exists xdg-settings || { error "缺少 xdg-settings，无法设置 XFCE 默认浏览器"; return 1; }
    command_exists xdg-mime || { error "缺少 xdg-mime，无法设置 MIME handler"; return 1; }
    if [[ $EUID -eq 0 ]]; then
        mkdir -p "$home/.config" "$desktop_dir"
    else
        sudo mkdir -p "$home/.config" "$desktop_dir"
    fi
    if [[ -f "$mime_file" ]]; then
        if [[ $EUID -eq 0 ]]; then
            sed -i -E '/^(x-scheme-handler\/http|x-scheme-handler\/https|text\/html)=/d' "$mime_file"
        else
            sudo sed -i -E '/^(x-scheme-handler\/http|x-scheme-handler\/https|text\/html)=/d' "$mime_file"
        fi
    fi
    local mime_tmp
    mime_tmp=$(mktemp)
    {
        [[ -s "$mime_file" ]] && cat "$mime_file"
        printf '%s\n' \
            "x-scheme-handler/http=$CHROME_DESKTOP_FILE" \
            "x-scheme-handler/https=$CHROME_DESKTOP_FILE" \
            "text/html=$CHROME_DESKTOP_FILE"
    } > "$mime_tmp"
    if [[ $EUID -eq 0 ]]; then
        mv "$mime_tmp" "$mime_file"
        chown "$RDP_USER:$RDP_USER" "$mime_file"
    else
        sudo mv "$mime_tmp" "$mime_file"
        sudo chown "$RDP_USER:$RDP_USER" "$mime_file"
    fi

    remote_desktop_user_exec xdg-settings set default-web-browser "$CHROME_DESKTOP_FILE" || \
        warn "xdg-settings 设置失败，将继续验证并使用 mimeapps.list 配置"
    remote_desktop_user_exec xdg-mime default "$CHROME_DESKTOP_FILE" x-scheme-handler/http || return 1
    remote_desktop_user_exec xdg-mime default "$CHROME_DESKTOP_FILE" x-scheme-handler/https || return 1
    remote_desktop_user_exec xdg-mime default "$CHROME_DESKTOP_FILE" text/html || return 1
    success "Default browser configured for $RDP_USER"
    verify_default_browser "$RDP_USER"
}

verify_default_browser() {
    local user="${1:-$RDP_USER}"
    local home
    [[ -n "$user" ]] || return 1
    home=$(getent passwd "$user" | cut -d: -f6) || return 1
    local mime_file="$home/.config/mimeapps.list"
    local value
    value=$(grep -E '^x-scheme-handler/http=' "$mime_file" 2>/dev/null | tail -n1 | cut -d= -f2- || true)
    [[ "$value" == "$CHROME_DESKTOP_FILE" ]] && success "HTTP handler: $value" || warn "HTTP handler: ${value:-missing}"
    value=$(grep -E '^x-scheme-handler/https=' "$mime_file" 2>/dev/null | tail -n1 | cut -d= -f2- || true)
    [[ "$value" == "$CHROME_DESKTOP_FILE" ]] && success "HTTPS handler: $value" || warn "HTTPS handler: ${value:-missing}"
    value=$(grep -E '^text/html=' "$mime_file" 2>/dev/null | tail -n1 | cut -d= -f2- || true)
    [[ "$value" == "$CHROME_DESKTOP_FILE" ]] && success "HTML handler: $value" || warn "HTML handler: ${value:-missing}"
    if command_exists xdg-settings; then
        value=$(remote_desktop_user_exec xdg-settings get default-web-browser 2>/dev/null || true)
        [[ "$value" == "$CHROME_DESKTOP_FILE" ]] && success "XFCE/default browser: $value" || warn "XFCE/default browser: ${value:-unknown}"
    fi
    if command_exists xdg-mime; then
        local mime_type mime_value
        for mime_type in x-scheme-handler/http x-scheme-handler/https text/html; do
            mime_value=$(remote_desktop_user_exec xdg-mime query default "$mime_type" 2>/dev/null || true)
            [[ "$mime_value" == "$CHROME_DESKTOP_FILE" ]] && success "xdg-mime $mime_type: $mime_value" || warn "xdg-mime $mime_type: ${mime_value:-unknown}"
        done
    fi
    if [[ -f "$home/.config/xfce4/helpers.rc" ]]; then
        value=$(grep -E '^WebBrowser=' "$home/.config/xfce4/helpers.rc" | tail -n1 | cut -d= -f2- || true)
        [[ "$value" == *google-chrome* ]] && success "XFCE preferred WebBrowser: $value" || warn "XFCE preferred WebBrowser: ${value:-missing}"
    fi
}

repair_chrome_browser() {
    remote_desktop_require_root || return 1
    remote_desktop_pick_user || return 1
    step "修复 XFCE 默认浏览器"
    chrome_installed || { error "Chrome 未安装；请先执行 --remote-desktop chrome-install"; return 1; }
    [[ -f /usr/share/applications/google-chrome.desktop ]] || {
        error "Chrome desktop 文件缺失: /usr/share/applications/google-chrome.desktop"
        return 1
    }
    command_exists xdg-settings || { error "缺少 xdg-settings"; return 1; }
    command_exists xdg-mime || { error "缺少 xdg-mime"; return 1; }
    set_default_browser || return 1
    success "Browser repair completed"
}

test_chrome() {
    remote_desktop_pick_user || return 1
    step "检测 Chrome/XFCE/DBus"
    chrome_installed || { error "Chrome 未安装"; return 1; }
    local chrome_bin version display output
    chrome_bin=$(chrome_command)
    version=$("$chrome_bin" --version 2>&1) || { error "Chrome 版本检测失败: $version"; return 1; }
    info "Chrome: $version"
    display=$(remote_desktop_find_display || true)
    [[ -n "$display" ]] && info "DISPLAY: $display" || warn "未检测到 DISPLAY；请从 XRDP XFCE 会话执行测试"
    if command_exists xdpyinfo; then
        remote_desktop_user_exec xdpyinfo >/dev/null 2>&1 && success "X11: available" || warn "X11: xdpyinfo 连接失败"
    else
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] 将通过 apt 安装 x11-utils 以提供 xdpyinfo"
        elif apt_install x11-utils && command_exists xdpyinfo; then
            remote_desktop_user_exec xdpyinfo >/dev/null 2>&1 && success "X11: available" || warn "X11: xdpyinfo 连接失败"
        else
            error "xdpyinfo 未安装且 x11-utils 安装失败"
            return 1
        fi
    fi
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        info "DBus session: available"
    else
        info "DBus session: 未从当前 shell 继承（XRDP session 可能在登录后提供）"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] 将以 $RDP_USER 身份启动 Chrome（不使用 --no-sandbox）"
        return 0
    fi
    output=$(remote_desktop_user_exec timeout 12 "$chrome_bin" --no-first-run --disable-background-networking about:blank 2>&1) || true
    if [[ -n "$output" ]]; then
        warn "Chrome 启动输出: $output"
        grep -qiE 'display|x11|dbus|sandbox|user namespace|permission|/tmp|/dev/shm|xfce|xrdp' <<< "$output" && \
            info "诊断提示：请确认 XRDP XFCE 会话的 DISPLAY、X11 权限、DBus、sandbox、/tmp 和 /dev/shm。"
    else
        success "Chrome 启动命令已执行"
    fi
}

uninstall_chrome() {
    remote_desktop_require_root || return 1
    chrome_installed || { info "Google Chrome 未安装，跳过"; return 0; }
    if ! confirm "卸载 Google Chrome（保留用户浏览器数据）？" "N"; then return 0; fi
    run_cmd sudo apt-get remove -y google-chrome-stable || return 1
    success "Google Chrome 已卸载（用户数据保留）"
}

show_chrome_status() {
    echo "Chrome:"
    local chrome_bin version desktop_file user home value
    if chrome_installed; then
        chrome_bin=$(chrome_command)
        version=$("$chrome_bin" --version 2>/dev/null | head -n1 || echo unknown)
        echo "  Installed: yes"
        echo "  Version: ${version#Google Chrome }"
        echo "  Executable: $chrome_bin"
    else
        echo "  Installed: no"
        echo "  Version: -"
        echo "  Executable: -"
    fi
    desktop_file="/usr/share/applications/$CHROME_DESKTOP_FILE"
    [[ -f "$desktop_file" ]] && echo "  Desktop file: present" || echo "  Desktop file: missing"
    user="${RDP_USER:-}"
    if [[ -z "$user" ]]; then
        user=$(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd 2>/dev/null || true)
    fi
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)"
    value="$(grep -E '^x-scheme-handler/http=' "$home/.config/mimeapps.list" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
    [[ "$value" == "$CHROME_DESKTOP_FILE" ]] && echo "  Default browser: yes" || echo "  Default browser: no"
    value="$(grep -E '^x-scheme-handler/http=' "$home/.config/mimeapps.list" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
    echo "  HTTP handler: ${value:--}"
    value="$(grep -E '^x-scheme-handler/https=' "$home/.config/mimeapps.list" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
    echo "  HTTPS handler: ${value:--}"
    value="$(grep -E '^text/html=' "$home/.config/mimeapps.list" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
    echo "  HTML handler: ${value:--}"
}

configure_xsession() {
    remote_desktop_pick_user || return 1
    local home xsession
    home=$(getent passwd "$RDP_USER" | cut -d: -f6)
    [[ -n "$home" && -d "$home" ]] || { error "无法找到用户 $RDP_USER 的 Home 目录"; return 1; }
    xsession="$home/.xsession"
    if [[ -e "$xsession" ]] && ! grep -qxF 'xfce4-session' "$xsession"; then
        remote_desktop_backup_file "$xsession"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] 写入 $xsession: xfce4-session"
        return 0
    fi
    if [[ $EUID -eq 0 ]]; then
        printf '%s\n' 'xfce4-session' > "$xsession"
        chmod 644 "$xsession"
        chown "$RDP_USER:$RDP_USER" "$xsession"
    else
        printf '%s\n' 'xfce4-session' | sudo tee "$xsession" >/dev/null
        sudo chmod 644 "$xsession"
        sudo chown "$RDP_USER:$RDP_USER" "$xsession"
    fi
}

install_tailscale() {
    if command_exists tailscale && command_exists tailscaled; then
        info "Tailscale 已安装，跳过软件源配置"
    else
        step "安装 Tailscale"
        if ! download_and_run "Tailscale 官方安装器" "https://tailscale.com/install.sh" sh; then
            error "Tailscale 官方安装器失败"
            return 1
        fi
    fi
    run_cmd sudo systemctl enable --now tailscaled
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    command_exists tailscale || { error "tailscale 命令未找到"; return 1; }
}

configure_tailscale() {
    install_tailscale || return 1
    if tailscale status >/dev/null 2>&1; then
        success "Tailscale 已认证"
        return 0
    fi
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        info "使用 Tailscale Auth Key 认证（密钥不会输出）"
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] tailscale up --auth-key <已隐藏>"
        else
            if ! tailscale up --auth-key="$TAILSCALE_AUTH_KEY" >/dev/null 2>&1; then
                unset TAILSCALE_AUTH_KEY
                error "Tailscale Auth Key 认证失败（密钥未记录）"
                return 1
            fi
        fi
        unset TAILSCALE_AUTH_KEY
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] tailscale up（浏览器认证 URL 将在真实执行时显示）"
        return 0
    fi
    step "Tailscale 登录"
    local output
    output=$(timeout 120 tailscale up 2>&1) || true
    if grep -Eo 'https://[^[:space:]]+' <<< "$output" | head -n1; then
        warn "请打开上面的 URL 完成 Tailscale 认证；等待最多 120 秒。"
    fi
    tailscale status >/dev/null 2>&1 || { warn "Tailscale 尚未认证，请稍后运行 --remote-desktop repair"; return 1; }
}

configure_tailscale_firewall() {
    command_exists ufw || return 0
    sudo ufw status 2>/dev/null | grep -q 'Status: active' || return 0
    if ip link show tailscale0 >/dev/null 2>&1; then
        if ! sudo ufw status 2>/dev/null | grep -q '3389.*tailscale0'; then
            run_cmd sudo ufw allow in on tailscale0 to any port 3389 proto tcp
            info "已允许 tailscale0 访问 XRDP 3389"
        fi
    else
        warn "tailscale0 尚未出现，暂不添加 UFW 规则"
    fi
    if sudo ufw status 2>/dev/null | grep -Eq '(^|[[:space:]])3389(/tcp)?([[:space:]]|$)'; then
        warn "检测到可能的公网 3389 规则；远程桌面建议仅通过 Tailscale 访问。"
        if confirm "删除明确的公网 3389 规则？" "N"; then
            run_cmd sudo ufw delete allow 3389/tcp || true
            run_cmd sudo ufw delete allow 3389 || true
        fi
    fi
}

check_xrdp() {
    local active enabled listening
    active=$(systemctl is-active xrdp 2>/dev/null || true)
    enabled=$(systemctl is-enabled xrdp 2>/dev/null || true)
    listening=$(ss -ltn 2>/dev/null | awk '$4 ~ /:3389$/ {print "yes"; exit}')
    [[ "$active" == active ]] && success "xrdp.service active" || warn "xrdp.service: ${active:-inactive}"
    [[ "$enabled" == enabled ]] && success "xrdp.service enabled" || warn "xrdp.service: ${enabled:-disabled}"
    [[ "$listening" == yes ]] && success "3389 正在监听" || warn "3389 未监听"
}

check_tailscale() {
    command_exists tailscale && success "Tailscale installed" || { warn "Tailscale 未安装"; return 1; }
    systemctl is-active --quiet tailscaled && success "tailscaled running" || warn "tailscaled 未运行"
    ip link show tailscale0 >/dev/null 2>&1 && success "tailscale0 available" || warn "tailscale0 不可用"
    if tailscale status >/dev/null 2>&1; then
        success "Tailnet connected"
        local ipv4 ipv6
        ipv4=$(tailscale ip -4 2>/dev/null | head -n1 || true)
        ipv6=$(tailscale ip -6 2>/dev/null | head -n1 || true)
        [[ -n "$ipv4" ]] && success "Tailscale IPv4: $ipv4" || warn "Tailscale IPv4 不可用"
        [[ -n "$ipv6" ]] && info "Tailscale IPv6: $ipv6" || info "Tailscale IPv6 未分配"
    else
        warn "Tailscale 已安装但尚未认证"
    fi
}

show_remote_desktop_status() {
    step "远程桌面状态"
    local pkg
    for pkg in xfce4 xrdp xorgxrdp dbus-x11; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' && success "$pkg installed" || warn "$pkg 未安装"
    done
    if dpkg-query -W -f='${Status}' xfce4 2>/dev/null | grep -q 'install ok installed'; then
        echo "XFCE: Installed: yes"
    else
        echo "XFCE: Installed: no"
    fi
    if systemctl is-active --quiet xrdp 2>/dev/null; then
        echo "XRDP: Installed: yes"
        echo "  Running: yes"
    else
        echo "XRDP: Installed: $(dpkg-query -W -f='${Status}' xrdp 2>/dev/null | grep -q 'install ok installed' && echo yes || echo no)"
        echo "  Running: no"
    fi
    check_xrdp
    check_tailscale || true
    remote_desktop_pick_user && configure_xsession || true
    show_chrome_status
    local swap
    swap=$(swapon --show --noheadings 2>/dev/null | head -n1 || true)
    [[ -n "$swap" ]] && info "Swap 已启用" || warn "未检测到 Swap；1-2GB RAM 建议配置 1-2GB Swap"
}

install_xrdp_stack() {
    step "安装 XFCE + XRDP"
    apt_install "${REMOTE_DESKTOP_PACKAGES[@]}" || return 1
    run_cmd sudo systemctl enable xrdp
    run_cmd sudo systemctl restart xrdp
    configure_xsession || return 1
    id "$RDP_USER" &>/dev/null && run_cmd sudo adduser "$RDP_USER" ssl-cert 2>/dev/null || true
}

install_remote_desktop() {
    remote_desktop_require_root || return 1
    remote_desktop_supported || { error "远程桌面支持 Debian 12、Ubuntu 22.04、24.04、26.04"; return 1; }
    install_xrdp_stack || return 1
    configure_tailscale || true
    configure_tailscale_firewall
    show_remote_desktop_connection_info
    record_result "remote-desktop" "ok"
}

repair_xrdp() {
    remote_desktop_require_root || return 1
    apt_install xrdp xorgxrdp dbus-x11 || return 1
    run_cmd sudo systemctl enable xrdp
    run_cmd sudo systemctl restart xrdp
    configure_xsession || return 1
    id "$RDP_USER" &>/dev/null && run_cmd sudo adduser "$RDP_USER" ssl-cert 2>/dev/null || true
    check_xrdp
}

repair_tailscale() {
    remote_desktop_require_root || return 1
    install_tailscale || return 1
    configure_tailscale || true
    configure_tailscale_firewall
    check_tailscale || true
}

optimize_remote_desktop() {
    remote_desktop_pick_user || return 1
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] 将为 $RDP_USER 关闭 XFCE compositor 和动画"
        return 0
    fi
    local home
    home=$(getent passwd "$RDP_USER" | cut -d: -f6)
    if command_exists xfconf-query; then
        sudo -u "$RDP_USER" xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
        sudo -u "$RDP_USER" xfconf-query -c xfwm4 -p /general/frame_opacity -s 100 2>/dev/null || true
    fi
    info "已应用保守的 XFCE 低资源优化（未禁用 SSH、dbus、NetworkManager、systemd 或 Tailscale）"
    [[ -n "$home" ]] || return 0
}

show_remote_desktop_connection_info() {
    local ip user
    user="${RDP_USER:-未配置}"
    ip=$(tailscale ip -4 2>/dev/null | head -n1 || true)
    echo "========================================"
    echo "远程桌面连接"
    echo "========================================"
    echo "Protocol: RDP"
    echo "VPN: Tailscale"
    echo "Tailscale IP: ${ip:-未认证}"
    echo "RDP Address: ${ip:-<Tailscale IPv4>}:3389"
    echo "Username: $user"
    echo "Session: Xorg"
    echo "Public 3389: 不自动开放"
    echo "========================================"
    info "客户端需加入同一 Tailnet，再使用 mstsc、Microsoft Remote Desktop 或 Remmina 连接。"
    info "RDP 密码不会显示；请使用 RDP 用户自己的系统密码。"
}

uninstall_remote_desktop() {
    remote_desktop_require_root || return 1
    if ! confirm "卸载 XFCE、XRDP、xorgxrdp、dbus-x11（保留用户和 Home）？" "N"; then return 0; fi
    remote_desktop_backup_file /etc/xrdp
    run_cmd sudo apt-get remove -y xfce4 xfce4-goodies xfce4-session xrdp xorgxrdp dbus-x11
    run_cmd sudo systemctl disable --now xrdp 2>/dev/null || true
    info "已卸载远程桌面软件，用户、Home 和 SSH 保留"
}

uninstall_tailscale() {
    remote_desktop_require_root || return 1
    if ! confirm "卸载 Tailscale（不删除其他系统配置）？" "N"; then return 0; fi
    remote_desktop_backup_file /etc/tailscale
    run_cmd sudo systemctl disable --now tailscaled 2>/dev/null || true
    run_cmd sudo apt-get remove -y tailscale
    info "Tailscale 已卸载"
}

remote_desktop_dispatch() {
    case "${1:-}" in
        install) install_remote_desktop ;;
        chrome-install|install-chrome) install_chrome ;;
        set-default-browser) set_default_browser ;;
        repair-browser|repair-default-browser) repair_chrome_browser ;;
        test-chrome) test_chrome ;;
        status) show_remote_desktop_status ;;
        repair)
            repair_xrdp
            repair_tailscale
            chrome_installed && repair_chrome_browser || true
            ;;
        optimize) optimize_remote_desktop ;;
        uninstall) uninstall_remote_desktop ;;
        uninstall-chrome) uninstall_chrome ;;
        uninstall-tailscale) uninstall_tailscale ;;
        info|connection) show_remote_desktop_connection_info ;;
        *) error "未知远程桌面动作: $1"; return 1 ;;
    esac
}
