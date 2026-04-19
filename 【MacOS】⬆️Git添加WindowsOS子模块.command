#!/usr/bin/env zsh
set -euo pipefail

# ================================== 聚合管理 WindowsOS 子仓库（可重复执行 / 可修复旧状态） ==================================
# 用途：
# 1) 在当前目录初始化一个聚合 Git 仓库（如果还不是 Git 仓库）
# 2) 把以下仓库作为 submodule 纳入统一管理：
#    - JobsKits/WindowsOS_10
#    - JobsKits/WindowsOS_8.1
#    - JobsKits/WindowsOS_7
#    - JobsKits/WindowsOS_XP
#    - JobsKits/WindowsOS_2003
# 3) 可重复执行：遇到半残 submodule / index 残留 / .git/modules 缓存都会自动修复

# 终端执行目录转向脚本所在目录
script_path="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
cd "$script_path"

info()  { print -P "%F{cyan}🔧 $*%f" }
ok()    { print -P "%F{green}✅ $*%f" }
warn()  { print -P "%F{yellow}⚠️  $*%f" }
err()   { print -P "%F{red}❌ $*%f" }

cpu_jobs() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null || echo 4
  elif command -v nproc >/dev/null 2>&1; then
    nproc 2>/dev/null || echo 4
  else
    echo 4
  fi
}

ensure_git_repo() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "当前目录已是 Git 仓库：$(pwd)"
  else
    info "初始化聚合 Git 仓库：$(pwd)"
    git init
    ok "Git init 完成"
  fi
}

ensure_first_commit_if_needed() {
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    ok "已存在提交：$(git rev-parse --short HEAD)"
    return
  fi

  warn "当前聚合仓库还没有任何提交，先做一次初始提交"
  if [[ ! -e .gitignore ]]; then
    cat > .gitignore <<'GITIGNORE'
.DS_Store
GITIGNORE
  fi

  if [[ ! -e README.md ]]; then
    cat > README.md <<'README'
# WindowsOS Aggregate

This repository aggregates and tracks these submodules:

- JobsKits/WindowsOS_10
- JobsKits/WindowsOS_8.1
- JobsKits/WindowsOS_7
- JobsKits/WindowsOS_XP
- JobsKits/WindowsOS_2003
README
  fi

  git add -A
  git commit -m "chore: initial commit for windows aggregate" || true
  ok "初始提交完成"
}

print_status() {
  info "Git 状态："
  git status
}

remove_existing_submodule() {
  local module_path="$1"

  if [[ -f .gitmodules ]]; then
    if git config -f .gitmodules --get-regexp "^submodule\..*\.path$" 2>/dev/null | awk '{print $2}' | grep -Fxq "$module_path"; then
      warn "发现 .gitmodules 中已有该子模块 path：$module_path，执行 deinit"
      git submodule deinit -f -- "$module_path" || true
    fi
  fi

  if git ls-files --stage -- "$module_path" | grep -q .; then
    warn "发现 index 已记录该 path：$module_path，执行 git rm 清理"
    git rm -f --cached -- "$module_path" || true
    git rm -f -- "$module_path" || true
  fi

  if [[ -d ".git/modules/$module_path" ]]; then
    warn "清理 .git/modules 缓存：.git/modules/$module_path"
    rm -rf ".git/modules/$module_path"
  fi

  if [[ -e "$module_path" ]]; then
    warn "清理工作区残留：$module_path"
    rm -rf "$module_path"
  fi

  ok "移除旧状态完成：$module_path"
}

ensure_submodule_url() {
  local module_path="$1"
  local url="$2"

  if [[ -f .gitmodules ]]; then
    local old_url
    old_url="$(git config -f .gitmodules --get-regexp "^submodule\..*\.path$" 2>/dev/null | awk -v p="$module_path" '$2==p {print $1}' | sed 's/\.path$/.url/' | head -n 1 || true)"
    if [[ -n "$old_url" ]]; then
      local configured_url
      configured_url="$(git config -f .gitmodules --get "$old_url" 2>/dev/null || true)"
      if [[ -n "$configured_url" && "$configured_url" != "$url" ]]; then
        warn "检测到 $module_path 的 URL 不一致，旧：$configured_url，新：$url，准备重建"
        remove_existing_submodule "$module_path"
      fi
    fi
  fi
}

add_submodule() {
  local branch="$1"
  local url="$2"
  local module_path="$3"

  ensure_submodule_url "$module_path" "$url"

  if [[ -d "$module_path/.git" || -f "$module_path/.git" ]]; then
    ok "子模块目录已存在，跳过 add：$module_path"
    return
  fi

  info "添加子模块：$url -> $module_path （branch=$branch）"
  git submodule add -b "$branch" "$url" "$module_path"
  ok "已添加：$module_path"
}

sync_and_update_submodules() {
  local jobs
  jobs="$(cpu_jobs)"

  info "同步 submodule url 记录"
  git submodule sync --recursive

  info "初始化并拉取子模块内容"
  git submodule update --init --recursive --jobs="$jobs"

  info "吸收子模块内部 .git 目录"
  git submodule absorbgitdirs

  info "让全部子模块按各自 branch 前移到远端最新"
  git submodule update --remote --merge --recursive --jobs="$jobs"

  info "再次吸收 .git 目录"
  git submodule absorbgitdirs

  ok "子模块同步/更新完成"
}

commit_changes_if_any() {
  info "提交聚合仓库变更（如有）"
  git add -A

  if git diff --cached --quiet; then
    warn "暂存区无变更，不需要提交"
    return
  fi

  git commit -m "chore: sync windows submodules"
  ok "已提交聚合仓库变更"
}

verify_gitfile_form() {
  local module_path="$1"
  if [[ -f "$module_path/.git" ]]; then
    ok "子模块 .git 为文件形式：$module_path/.git"
    return 0
  fi
  if [[ -d "$module_path/.git" ]]; then
    warn "子模块 .git 仍是目录：$module_path/.git"
    return 1
  fi
  warn "子模块缺少 .git：$module_path"
  return 1
}

show_submodule_summary() {
  info "当前 submodule 摘要："
  git submodule status --recursive || true
}

main() {
  ensure_git_repo
  ensure_first_commit_if_needed
  print_status

  local branch="main"

  local url_win10="https://github.com/JobsKits/WindowsOS_10.git"
  local url_win81="https://github.com/JobsKits/WindowsOS_8.1.git"
  local url_win7="https://github.com/JobsKits/WindowsOS_7.git"
  local url_winxp="https://github.com/JobsKits/WindowsOS_XP.git"
  local url_win2003="https://github.com/JobsKits/WindowsOS_2003.git"

  local path_win10="./WindowsOS_10"
  local path_win81="./WindowsOS_8.1"
  local path_win7="./WindowsOS_7"
  local path_winxp="./WindowsOS_XP"
  local path_win2003="./WindowsOS_2003"

  # 如需强制重建，把下面 5 行解除注释。
  # remove_existing_submodule "$path_win10"
  # remove_existing_submodule "$path_win81"
  # remove_existing_submodule "$path_win7"
  # remove_existing_submodule "$path_winxp"
  # remove_existing_submodule "$path_win2003"

  add_submodule "$branch" "$url_win10" "$path_win10"
  add_submodule "$branch" "$url_win81" "$path_win81"
  add_submodule "$branch" "$url_win7" "$path_win7"
  add_submodule "$branch" "$url_winxp" "$path_winxp"
  add_submodule "$branch" "$url_win2003" "$path_win2003"

  sync_and_update_submodules
  commit_changes_if_any

  info "验证子模块 .git 形态："
  verify_gitfile_form "$path_win10" || true
  verify_gitfile_form "$path_win81" || true
  verify_gitfile_form "$path_win7" || true
  verify_gitfile_form "$path_winxp" || true
  verify_gitfile_form "$path_win2003" || true

  show_submodule_summary

  ok "全部完成"
  print_status
}

main "$@"
