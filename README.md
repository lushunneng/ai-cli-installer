# AI CLI Installer

AI CLI Installer 是一个插件式 AI CLI 工具安装器。入口脚本会自动加载 `lib/` 目录下的插件文件，所以新增工具通常只需要新增一个 `lib/*.sh` 文件，不需要改主安装器。

当前支持的工具：

- Node.js (NVM)
- Claude Code (Anthropic)
- Codex CLI (OpenAI)
- Grok CLI (xAI)
- Herdr
- OpenCode CLI
- Kimi Code CLI (Moonshot AI)
- Qoder CLI
- 常用系统工具（ripgrep、fd、bat、jq、tree、htop、tmux、mosh 等）

## 环境要求

脚本主要面向 Ubuntu 22.04 / 24.04。其他 Linux 发行版可能可以运行，但会有提示确认。

基础要求：

- `bash`
- `curl`
- `sudo`
- 可访问工具官方安装源、npm registry 或 GitHub releases

## 安装工具

进入项目目录：

```bash
cd ai-cli-installer
```

交互式安装：

```bash
./install.sh
```

脚本会显示可用工具列表。输入编号安装单个工具，也可以用逗号安装多个工具：

```text
1,3,5
```

安装全部工具：

```bash
./install.sh --all
```

自动确认并安装全部工具：

```bash
./install.sh --all --yes
```

只预览安装动作，不实际执行：

```bash
./install.sh --dry-run
```

指定 Node.js 版本，默认是 `22`：

```bash
./install.sh --node-version 22
```

常用组合：

```bash
./install.sh --all --yes --node-version 22
```

安装完成后，如果命令不可用，重新打开终端，或执行：

```bash
source ~/.bashrc
```

如果你使用 zsh，也可以执行：

```bash
source ~/.zshrc
```

## 卸载工具

交互式卸载：

```bash
./uninstall.sh
```

脚本会列出已检测到的工具。输入编号卸载单个工具，也可以用逗号卸载多个工具：

```text
2,5
```

也可以通过安装入口触发全部卸载：

```bash
./install.sh --uninstall
```

卸载逻辑由每个插件自己的 `uninstall_*` 函数负责。多数工具会在删除配置前先备份用户配置目录，例如：

- `~/.codex`
- `~/.claude`
- `~/.grok`
- `~/.opencode`
- `~/.config/opencode`
- `~/.config/herdr`
- `~/.herdr`

注意：卸载脚本只会删除插件明确处理的文件。对于不在用户目录下的二进制文件，插件通常会保留并提示，避免误删系统包管理器安装的文件。

## 更新工具

检查版本，不执行更新：

```bash
./update.sh --check-only
```

交互式检查并选择更新：

```bash
./update.sh
```

自动更新所有明确检测为“可更新”的工具：

```bash
./update.sh --all --yes
```

强制对所有已安装工具执行更新器：

```bash
./update.sh --all --force --yes
```

刷新 APT 仓库索引：

```bash
./update.sh --apt --yes
```

更新已安装的系统软件包：

```bash
./update.sh --system --yes
```

安装 Ubuntu 最新通用内核元包（完成后按提示重启）：

```bash
./update.sh --kernel --yes
```

只预览更新动作，不实际执行：

```bash
./update.sh --dry-run --all --force
```

更新脚本会先检测本地版本，再尝试查询远端最新版本。远端版本查询失败时会显示 `unknown`，但不会中断脚本。此时可以使用 `--force` 强制走各工具自己的更新逻辑。

各工具的更新方式：

- Claude Code：优先执行 `claude update`
- Codex CLI：优先执行 `codex update`
- Herdr：优先执行 `herdr update`
- OpenCode：优先执行 `opencode upgrade latest`
- Grok：复用现有安装器更新逻辑
- NVM：通过 GitHub releases 检查版本，并用官方安装脚本更新
- Kimi Code CLI：优先使用 `uv tool upgrade kimi-cli --no-cache`
- Qoder CLI：使用 npm 更新 `@qoder-ai/qodercli`
- 常用系统工具：通过 APT `--only-upgrade` 更新已安装的软件包

## 新增工具

新增工具只需要在 `lib/` 目录创建一个插件文件。文件名建议使用小写和短横线，例如：

```bash
lib/my-tool.sh
```

插件需要完成三件事：

1. 定义元数据。
2. 调用 `register_plugin` 注册工具。
3. 实现安装函数和卸载函数。

最小示例：

```bash
#!/usr/bin/env bash
# my-tool.sh - My Tool 安装模块
# PLUGIN_ID: my-tool
# PLUGIN_CMD: my-tool
# PLUGIN_NAME: My Tool
# PLUGIN_DESC: 示例 AI CLI 工具

MY_TOOL_INSTALL_URL="https://example.com/install.sh"

register_plugin "my-tool" "my-tool" "My Tool" "示例 AI CLI 工具"

install_my_tool() {
    step "安装 My Tool"

    if is_installed my-tool; then
        if confirm "  是否更新到最新版本？" "Y"; then
            info "正在更新..."
        else
            record_result "my-tool" "skipped"
            return 0
        fi
    fi

    if download_and_run "My Tool" "$MY_TOOL_INSTALL_URL" bash; then
        success "My Tool 已安装"
    else
        error "My Tool 下载或安装失败"
        record_result "my-tool" "failed" "官方安装器失败"
        return 1
    fi

    local tool_dir
    tool_dir=$(dirname "$(which my-tool 2>/dev/null || echo "/dev/null")")
    if [[ -n "$tool_dir" && "$tool_dir" != "." && "$tool_dir" != "/dev/null" ]]; then
        ensure_in_path "$tool_dir"
    fi

    if command_exists my-tool; then
        success "My Tool $(my-tool --version 2>/dev/null | head -n1) 可用"
        record_result "my-tool" "ok"
    else
        warn "安装完成但 my-tool 命令不可用，可能需要重新打开终端"
        record_result "my-tool" "failed"
    fi
}

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
            if confirm "  是否删除 ~/.my-tool 目录？" "Y"; then
                rm -rf "$HOME/.my-tool"
            fi
        fi

        if [[ -f "$tool_bin" || -L "$tool_bin" ]] && [[ "$tool_bin" == "$HOME"* ]]; then
            rm -f "$tool_bin"
            success "已删除 $tool_bin"
        fi

        clean_path_from_profiles "$(dirname "$tool_bin")"
        success "My Tool 已卸载"
    else
        info "My Tool 未安装，跳过"
    fi
}
```

### 注册格式

```bash
register_plugin "插件 ID" "命令名" "菜单名称" "菜单描述"
```

例如：

```bash
register_plugin "herdr" "herdr" "Herdr" "终端里的 AI 编程智能体复用器"
```

默认函数命名规则：

- 安装函数：`install_${PLUGIN_ID//-/_}`
- 卸载函数：`uninstall_${PLUGIN_ID//-/_}`

例如 `PLUGIN_ID` 是 `claude-code`，默认函数就是：

```bash
install_claude_code
uninstall_claude_code
```

如果需要自定义函数名，可以给 `register_plugin` 传第 5 和第 6 个参数：

```bash
register_plugin "my-tool" "my-tool" "My Tool" "示例工具" "custom_install" "custom_uninstall"
```

### 插件加载规则

`install.sh`、`uninstall.sh`、`update.sh` 都会调用 `load_plugins` 自动加载 `lib/` 下的插件。

加载规则：

- `lib/node.sh` 会优先加载，因为其他工具可能依赖 Node.js / npm。
- `lib/common.sh` 不会作为插件加载。
- 文件名以下划线开头的脚本不会自动加载，例如 `lib/_example.sh`。
- 其他 `lib/*.sh` 文件会按 shell glob 顺序加载。

### 常用公共函数

插件可以直接使用 `lib/common.sh` 中的公共函数：

- `step "标题"`：输出步骤标题。
- `info "消息"`：输出信息。
- `success "消息"`：输出成功消息。
- `warn "消息"`：输出警告。
- `error "消息"`：输出错误。
- `confirm "问题" "Y"`：询问确认。
- `command_exists cmd`：检查命令是否存在。
- `is_installed cmd`：检查命令是否存在并输出版本。
- `download_and_run "名称" "URL" bash`：下载并执行官方安装器。
- `run_cmd cmd args...`：支持 dry-run 的命令执行。
- `ensure_in_path dir`：把目录写入 shell profile 的 PATH。
- `clean_path_from_profiles dir`：从 shell profile 清理安装器写入的 PATH 片段。
- `record_result id status detail`：记录安装结果。
- `load_nvm`：加载 `~/.nvm/nvm.sh`。

### 新增工具后的检查

新增插件后，先做语法检查：

```bash
bash -n install.sh uninstall.sh update.sh lib/common.sh lib/*.sh
```

确认插件已经注册：

```bash
bash -c 'source lib/common.sh; load_plugins lib; printf "%s\n" "${PLUGIN_LIST[@]}"'
```

预览安装动作：

```bash
./install.sh --dry-run
```

预览更新动作：

```bash
./update.sh --dry-run --all --force
```

## 日志

脚本运行时会在 `/tmp` 下生成日志文件，格式类似：

```text
/tmp/ai-cli-installer-YYYYMMDD-HHMMSS.log
```

安装器结束时会打印日志路径。

