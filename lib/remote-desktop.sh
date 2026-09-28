#!/usr/bin/env bash
# remote-desktop.sh - XFCE + XRDP + Tailscale 轻量级远程桌面模块
# 仅通过 Tailscale 提供推荐访问路径，不自动开放公网 3389。

REMOTE_DESKTOP_PACKAGES=(xfce4 xfce4-goodies xfce4-session xrdp xorgxrdp dbus-x11)
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
    check_xrdp
    check_tailscale || true
    remote_desktop_pick_user && configure_xsession || true
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
        status) show_remote_desktop_status ;;
        repair) repair_xrdp; repair_tailscale ;;
        optimize) optimize_remote_desktop ;;
        uninstall) uninstall_remote_desktop ;;
        uninstall-tailscale) uninstall_tailscale ;;
        info|connection) show_remote_desktop_connection_info ;;
        *) error "未知远程桌面动作: $1"; return 1 ;;
    esac
}
