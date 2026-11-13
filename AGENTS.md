# 沙箱内 git 规范（DSH）

本仓库 `.git/hooks` 装有 Git LFS 钩子，LFS 的 clean/smudge filter 也依赖 msys2；msys2 在 DSH 沙箱内无法启动
（`NtCreateDirectoryObject ... 0xC0000022`）。后果是：钩子崩溃、`git add *.png` 失败、`ssh.exe` 起不来。
因此 DSH 会话内只做本地文本操作，规则如下。**不要改动仓库的 git 配置**（不要用 `git config` 写入任何设置）。

## 1. 本地命令一律带前缀

    git -c core.hooksPath=.git/no-hooks -c core.fsmonitor=false <子命令> ...

适用于 status / diff / log / add / commit / switch / merge / restore / stash 等一切本地命令。

- `-c` 必须写在子命令**之前**；写成 `git commit -c ...` 会报错（那是"复用提交信息"的意思）。
- `.git/no-hooks` 不需要创建；目录不存在时 git 视为"没有钩子"。
- 只影响本次命令，仓库配置保持不变，用户在沙箱外手动操作不受影响。

## 2. 远程命令不得带这两个 `-c`

push / fetch / pull / `git lfs push`·`fetch`·`pull` 保持原样执行。
`pre-push` 钩子负责上传 LFS 对象，跳过它会让远端只拿到指针、配图损坏且**不产生任何报错**。
沙箱内 `ssh.exe` 同样起不来，这些命令必然失败——不要反复重试，直接告知用户需在沙箱外同步。

## 3. 涉及 LFS 文件（*.png）时必须提权

沙箱内 msys2 起不来 → LFS filter 失效：`git add` 任何 `.png` 会 exit 128 且 index 不变；
工作区只要有一个 `.png` 变动，`git add -A` / `-u` / `commit -a` 会**整体失败**（`.md` 也进不去）。因此：

- `add` 一律写明确路径；禁止 `-A`、`-u`、`commit -a`。
- 需要新增/更新图片时：用 pwsh 工具带 `sandbox_permissions: danger-full-access`，在一条命令内完成 add + commit；
  执行前说明用途并等待用户批准；执行后用 `git cat-file -p :<path>` 或 `git lfs ls-files` 确认写成了 pointer。
  （已实测：放开沙箱后 msys2 正常，`.png` 会正确写成 LFS pointer。）
- 不要 checkout/switch 到改动过图片的提交（如 `702c1e8` 及更早），需要时走提权或沙箱外。

## 4. 失败判读

- commit/switch 后出现 `msys2 ... NtCreateDirectoryObject ... 0xC0000022` 堆栈：这是 post-commit /
  post-checkout 钩子崩溃，**命令本身成功**（exit 0）。按第 1 条执行时不会出现。
- `error: fsmonitor_ipc__send_query`：未带 `core.fsmonitor=false` 的噪声，不影响结果。
- `add` 报 `external filter ... failed` 或 exit 128：几乎都是路径里含 `.png`，按第 3 条处理。

## 5. 提交前自检

    git -c core.fsmonitor=false status --short

若输出里出现 `.png` 改动而本次任务并非处理图片，停下并向用户报告，不要顺手提交。

提交信息沿用仓库既有约定（`[ds]` 开头的说明性 message，见各子项目 AGENTS.md）。
