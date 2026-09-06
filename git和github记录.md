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
