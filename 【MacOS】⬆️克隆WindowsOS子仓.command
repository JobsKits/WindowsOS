#!/usr/bin/env zsh
# 脚本自述：
# - 脚本名称：【MacOS】⬆️克隆WindowsOS子仓.command
# - 核心用途：克隆WindowsOS子仓。
# - 影响范围：Git 工作区、子模块或仓库状态；脚本指定文件或缓存的删除 / 清理。
# - 运行提示：先阅读自述并按回车确认，按 Ctrl+C 取消。
JOBS_COMMAND_ENTRY_ARG0="$0"
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
# 打印固定自述，确认后才进入原有脚本流程。
show_script_intro_and_wait() {
  printf '%s\n' '【MacOS】⬆️克隆WindowsOS子仓.command' | jobs_intro_style title
  printf '%s\n' '1、核心用途：克隆WindowsOS子仓。' | jobs_intro_style body
  printf '%s\n' '2、影响范围：Git 工作区、子模块或仓库状态；脚本指定文件或缓存的删除 / 清理。' | jobs_intro_style body
  printf '%s\n' '3、运行策略：确认后执行原有流程；后续危险操作的确认保持原样。' | jobs_intro_style body
  printf '%s\n' '4、取消方式：按 Ctrl+C 终止；确认前不执行真实业务。' | jobs_intro_style body
  if [ ! -t 0 ]; then
    printf '%s\n' '当前没有可交互输入，请在终端中重新运行。' >&2
    exit 1
  fi
  printf '%s' '已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：'
  IFS= read -r jobs_intro_answer || exit 1
}
# 确认后执行原有业务，保留原来的参数、交互和退出策略。
jobs_run_original_script() {
  0="$JOBS_COMMAND_ENTRY_ARG0"
# 作用：在父仓库中一键同步 .gitmodules → 初始化并下载所有子模块
# 行为：默认仅把子模块检出到“父仓记录的提交”（不改 gitlink、不推送）
# 可选：设置 TRACK_BRANCH=1 时，切到各子模块的 main 分支并 pull（会让父仓变脏）

set -euo pipefail

# ===== 可调参数 =====
DEPTH="${DEPTH:-0}"            # 0=完整克隆；>0 则浅克隆（如 1）
TRACK_BRANCH="${TRACK_BRANCH:-1}"  # 1=把子模块切到 main 并拉最新；0=保持父仓记录的提交
PARALLEL="${PARALLEL:-4}"      # 并行作业数（仅在 foreach 简单并行时使用）

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
cd "$script_dir"

# ===== 清理：删除脚本同级的空目录（不递归） =====
cleanup_empty_dirs_in_script_dir() {
  local base_dir="$1"
  local deleted_count=0
  local d

  # 只检查同级目录：maxdepth=1；不递归子目录
  while IFS= read -r -d '' d; do
    # 空目录判断：目录内（含隐藏文件）没有任何条目
    if [[ -z "$(ls -A "$d" 2>/dev/null || true)" ]]; then
      rm -rf "$d"
      echo "🧹 删除空目录：$(basename "$d")"
      ((deleted_count++)) || true
    fi
  done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  if (( deleted_count > 0 )); then
    echo "✅ 已清理 ${deleted_count} 个空目录"
  else
    echo "ℹ️  未发现需要清理的空目录"
  fi
}

cleanup_empty_dirs_in_script_dir "$script_dir"

# ===== 基础检查 =====
command -v git >/dev/null || { echo "❌ 未找到 git"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ 当前不在 Git 仓库内"; exit 1; }
[[ -f .gitmodules ]] || { echo "❌ 未发现 .gitmodules，确认脚本放在父仓根目录"; exit 1; }

echo "ℹ️  同步子模块 URL（.gitmodules → .git/config）"
git submodule sync --recursive

echo "⏬ 初始化并下载所有子模块（可能耗时）"
if [[ "$DEPTH" != "0" ]]; then
  git submodule update --init --recursive --depth "$DEPTH"
else
  git submodule update --init --recursive
fi

# 显示一下状态
echo "📋 子模块状态："
git submodule status --recursive || true

if [[ "$TRACK_BRANCH" == "1" ]]; then
  echo "🔀 将子模块切到 main 分支并拉取最新（父仓 gitlink 将变化）"
  # 如果子模块配置了别的分支，可以改成 set-branch
  git submodule foreach --recursive '
    set -e

    # 1) 优先读取父仓 .gitmodules 为该子模块指定的分支（如果有）
    branch="$(git config -f "$toplevel/.gitmodules" "submodule.$name.branch" 2>/dev/null || true)"
    branch="${branch:-main}"

    # 2) 兜底：main 不存在则尝试 master
    pick_branch() {
      local b="$1"
      if git show-ref --verify --quiet "refs/remotes/origin/$b"; then
        echo "$b"; return 0
      fi
      if git show-ref --verify --quiet "refs/heads/$b"; then
        echo "$b"; return 0
      fi
      return 1
    }

    git fetch --all --tags --prune

    if ! pick_branch "$branch" >/dev/null 2>&1; then
      if pick_branch "main" >/dev/null 2>&1; then
        branch="main"
      elif pick_branch "master" >/dev/null 2>&1; then
        branch="master"
      else
        echo "⚠️  [$name] 未找到可用分支（main/master 或 .gitmodules 指定分支均不存在），跳过追分支，仅保持当前检出：$(git rev-parse --short HEAD)"
        exit 0
      fi
    fi

    echo "➡️  [$name] 使用分支: $branch"

    # 3) 从 origin/<branch> 创建/切换到本地分支，避免 detached HEAD
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git checkout "$branch"
    else
      if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        git checkout -b "$branch" "origin/$branch"
      else
        # 极端兜底：远端也没有（理论上上面 pick_branch 已拦住）
        git checkout "$branch" || true
      fi
    fi

    # 4) 拉取最新（严格快进）
    git pull --ff-only origin "$branch" || true

    echo "✅ $(basename "$name"): on $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
  '
  echo "⚠️  父仓现在可能处于“已修改的子模块指针”状态："
  echo "    若要固化到父仓，请手动： git add . && git commit -m 'chore(submodules): bump'"
fi

echo "✅ 完成"

# 常见故障提示
cat <<'EOF'

🩺 如果仍为空/拉取失败，按顺序排查：
1) 权限：子模块是否私有？HTTPS 需要 Token；SSH 需要配置公钥（ssh -T git@github.com）。
2) URL：检查 .gitmodules 中地址是否正确；改过后记得运行：git submodule sync --recursive
3) 网络：公司代理/防火墙；必要时切换 HTTPS/SSH 协议。
4) 浅克隆过深：尝试删除该子模块目录后重新执行，或把 DEPTH=0。
EOF
}
# 编排自述确认与原有业务。
main() {
  show_script_intro_and_wait # 展示用途与影响，并等待回车确认。
  jobs_run_original_script "$@" # 继续执行原有脚本流程。
}
main "$@"
