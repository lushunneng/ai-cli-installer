# Git 和 GitHub 操作记录

这个文件用于学习和追踪本仓库中的 Git、GitHub 操作。后续每次相关操作都在文末追加，失败的操作也要记录。

## 2026-09-06：初始化记录规则并首次推送

- 目的：建立仓库级记忆，要求今后所有 Git/GitHub 操作都记录在本文件中。
- 检查仓库：运行 `git status --short --branch`、`git remote -v`、`git log -5 --oneline --decorate`、`git branch --show-current`、`git diff --no-index /dev/null <新文件>`、`git config --get user.name` 和 `git config --get user.email`。
- 检查结果：仓库尚无提交，原分支名为 `master`，现有项目文件均未跟踪，最初未配置远端；提交身份为 `lushunneng <lushunneng@126.com>`。由于没有首个提交，`git log` 返回“当前分支没有提交”，这是正常现象。
- 探测 GitHub：运行 `git ls-remote git@github.com:lushunneng/ai-cli-installer.git`。命令成功但没有输出，表示 SSH 连接及仓库访问正常，远端目前没有任何分支或标签。
- 分支命名：运行 `git branch -m main`，把默认分支从 `master` 改为常用的 `main`。
- 配置远端：运行 `git remote add origin git@github.com:lushunneng/ai-cli-installer.git`，并用 `git remote -v` 验证拉取和推送地址一致。
- 权限学习：第一次修改分支和远端时，因 `.git` 元数据只读而失败；提升工作区权限后重试成功。失败没有改动项目文件。
- 暂存与检查：运行 `git add AGENTS.md README.md 'git和github记录.md' install.sh lib uninstall.sh update.sh`；`git diff --cached --check` 通过（仅提示 README 文件末尾存在空白行），暂存区统计为 14 个文件、2344 行新增内容。
- 创建提交：运行 `git commit -m "chore: initialize AI CLI installer"` 成功，提交为 `9ea5dc5`（root commit）。
- 日志同步提交：将本次暂存、检查和提交结果写入本文件后，运行 `git add 'git和github记录.md'` 及 `git commit -m "docs: record git workflow"`，把学习记录单独保存到历史中。
- 首次推送：运行 `git push -u origin main` 成功，输出显示 `main -> main`，并建立了本地 `main` 对 `origin/main` 的跟踪关系。
- 日志同步：本条推送结果会随下一次 `git add 'git和github记录.md'`、`git commit -m "docs: record push result"` 和 `git push` 一并同步到 GitHub。

### 这些命令的作用

- `git status` 查看工作区、暂存区和分支状态。
- `git add` 把准备提交的文件放进暂存区。
- `git commit` 在本地创建一个可追踪的历史节点。
- `git remote add origin <地址>` 给远端地址起一个常用别名 `origin`。
- `git push -u origin main` 首次推送 `main`；`-u` 建立跟踪关系，以后通常只需运行 `git push`。

## 2026-09-09：新增系统更新与 Kimi/Qoder CLI 支持

- 目的：修复安装器已确认问题，并增加 APT 仓库、系统软件包、Ubuntu 通用内核更新，以及 Kimi Code CLI、Qoder CLI 插件。
- 检查仓库：运行 `git status --short --branch`，结果为 `## main...origin/main`。
- 差异检查：运行 `git diff --check`，通过，无空白错误。
- 差异审阅：运行 `git diff --stat` 和针对修改文件的 `git diff`，确认变更集中在安装、更新、插件和文档范围。
- 工作区结果：修改了 `README.md`、`install.sh`、`lib/common.sh`、`lib/node.sh`、`uninstall.sh`、`update.sh`，新增 `lib/kimi.sh` 和 `lib/qoder.sh`。
- 验证：运行 `bash -n install.sh uninstall.sh update.sh lib/*.sh`、帮助命令、插件加载检查、安装器完整 dry-run 和 APT dry-run，均通过。
- 后续说明：本次未执行 commit、push 或实际 apt/CLI 安装；系统更新需用户显式运行 `update.sh --apt`、`--system` 或 `--kernel`。
- 最终检查：补充 README 中 Kimi/Qoder 更新方式后，再次运行 `git diff --check`，仍然通过。

## 2026-09-09：准备推送功能升级

- 目的：将 APT/系统/内核更新及 Kimi/Qoder CLI 功能升级推送到远端仓库。
- 检查仓库：运行 `git status --short --branch`。
- 检查结果：当前分支为 `main`，跟踪 `origin/main`；工作区有 6 个已修改文件和 2 个新增插件文件，另有本操作记录文件修改。
- 提交尝试：运行 `git commit -m "feat: add system and AI CLI updates"` 失败，原因是当前环境未配置 Git 用户身份（empty ident name）。
- 身份配置：运行 `git config --local user.name "lushunneng"` 和 `git config --local user.email "lushunneng@126.com"` 成功，仅写入本仓库配置。
- 创建提交：运行 `git commit -m "feat: add system and AI CLI updates"` 成功，提交哈希为 `df26584`。
- 首次推送：运行 `git push origin main` 成功，远端 `main` 从 `ac2ae49` 更新到 `5c52677`。
- 文档记录推送：运行 `git push origin main` 成功，远端 `main` 从 `5c52677` 更新到 `eb21def`。

## 2026-09-11：集成常用系统工具插件

- 目的：为安装器增加常用 Ubuntu 开发与运维工具的集中安装和更新能力。
- 检查仓库：运行 `git status --short --branch`，结果为 `## main...origin/main`；随后工作区包含 `README.md`、`update.sh` 和新增 `lib/system-tools.sh` 修改。
- 差异检查：运行 `git diff --check`，通过，无空白错误。
- 验证：运行 `bash -n install.sh uninstall.sh update.sh lib/*.sh`、插件加载检查和 `./install.sh --dry-run --all --yes`，均通过；插件总数为 9 个。
- 后续说明：本次未执行 commit 或 push；新增工具插件默认保留系统包，不自动卸载。

## 2026-09-11：新增 mosh 工具

- 目的：将 mosh 加入常用 Ubuntu 系统工具集合，纳入安装、更新和卸载提示。
- 差异检查：运行 `git diff --check`，通过，无空白错误。
- 验证：运行 `bash -n install.sh uninstall.sh update.sh lib/*.sh`、插件加载检查、安装器 dry-run 和更新器 dry-run，均通过；安装和更新命令均包含 `mosh`。
- 后续说明：本次未执行 commit 或 push；mosh 将随常用系统工具插件通过 APT 安装。

## 2026-09-11：准备推送 mosh 集成

- 目的：提交并推送常用系统工具集成及 mosh 工具改动。
- 检查仓库：运行 `git status --short --branch`。
- 检查结果：当前分支为 `main`，跟踪 `origin/main`；工作区包含 `README.md`、`update.sh`、新增 `lib/system-tools.sh` 以及本记录文件修改。
- 暂存检查：运行 `git add README.md update.sh lib/system-tools.sh git和github记录.md` 及 `git diff --cached --check`，检查通过；暂存差异统计为 4 个文件、71 行新增。
