#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⬆️克隆WindowsOS子仓.command
# - 核心用途：选择 Windows 子仓，安全同步分支最新，可向下递归，并可另选 Release 附件。
# - 影响范围：仅所选子树的工作区、跟踪分支与本地子模块登记；不暂存、不提交、不推送。
# - 运行提示：先阅读自述并按回车确认；执行前再次确认，回车执行，任意字符后回车跳过，Ctrl+C 取消。
# shell: zsh

ENTRY_PATH="$0"
SCRIPT_DIR=""
LOG_FILE=""
MODE=""
RECURSIVE=1
READ_ONLY=0
HELP_ONLY=0
SELECTED=()
REQUESTED=()
MODULE_NAMES=()
MODULE_PATHS=()
FZF_BIN=""
FZF_RESULTS=()
FZF_INITIAL_KEYS=()
MODE_FIXED=0
SCOPE_FIXED=0
SCOPE_STEP=""
LAST_SCOPE_STEP=""
CURRENT_STAGE="准备"

# 准备无副作用的展示信息，并打印固定自述。
show_script_intro_and_wait() {
  SCRIPT_DIR="${ENTRY_PATH:A:h}"
  LOG_FILE="${TMPDIR:-/tmp}/${ENTRY_PATH:t:r}.$$.log"
  local arg answer=""
  for arg in "$@"; do
    [[ "$arg" == --help || "$arg" == -h ]] && HELP_ONLY=1
    [[ "$arg" == --list ]] && READ_ONLY=1
  done
  intro_line title 'WindowsOS 子仓与 Release 可选拉取'
  intro_line body '1、选择 Git 更新、Release 附件，或两者；再多选 Windows 版本。'
  intro_line body '2、Git 仅安全快进所选子树到目标分支最新；保留本地源码、暂存和独有提交。'
  intro_line body '3、模式、子仓与同步范围使用 fzf；子层按 ← 返回上层；附件存放到对应子仓 Releases/<标签>/。'
  intro_line body "4、不提交、不推送；日志：$LOG_FILE；Ctrl+C 取消。"
  if (( HELP_ONLY || READ_ONLY )); then
    return 0
  fi
  [[ -t 0 ]] || { print -u2 -r -- '✖ 当前没有可交互输入，请在终端运行；只读可用 --help / --list。'; exit 1; }
  read -r 'answer?已了解用途与影响，按回车继续；Ctrl+C 取消：' || exit 1
}
# 在支持颜色的终端显示自述层级，其它环境降级为纯文本。
intro_line() {
  local role="$1" message="$2" code='0;34'
  [[ "$role" == title ]] && code='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && -z "${SOURCETREE:-}${SOURCE_TREE:-}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 删除展示中的 ANSI、URL 认证和查询内容；不改写业务地址。
sanitize_stream() {
  sed -E $'s/\033\\[[0-9;]*[[:alpha:]]//g; s#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\\1[REDACTED]@#g; s#(https?://)[^/@[:space:]]+@#\\1[REDACTED]@#g; s#(https?://[^?[:space:]]+)\\?[^[:space:]]*#\\1?[REDACTED]#g'
}
# 同步显示和保存可搜索的纯文本日志。
log_message() {
  if [[ -n "$LOG_FILE" && "$READ_ONLY" == 0 && "$HELP_ONLY" == 0 ]]; then
    print -r -- "$*" | sanitize_stream | tee -a "$LOG_FILE"
  else
    print -r -- "$*" | sanitize_stream
  fi
}
# 报告当前失败并停止，避免后续步骤输出假成功。
fail() {
  log_message "✖ [$CURRENT_STAGE] $*"
  if [[ "$MODE" == both && "$CURRENT_STAGE" == Git ]]; then
    log_message 'ℹ Git 阶段未完成，尚未进入 Release 选择和下载。'
  fi
  exit 1
}
# 显示命令输出并传播失败状态，所有输出均脱敏落盘。
run_logged() {
  "$@" 2>&1 | sanitize_stream | tee -a "$LOG_FILE"
}
# 校验参数；只读入口不创建日志或更改 Git 状态。
parse_options() {
  setopt NO_NOMATCH PIPE_FAIL
  while (( $# )); do
    case "$1" in
      --help|-h) HELP_ONLY=1; shift ;;
      --list) READ_ONLY=1; shift ;;
      --repo)
        (( $# >= 2 )) || fail '--repo 缺少仓名。'
        REQUESTED+=("$2"); shift 2 ;;
      --mode)
        (( $# >= 2 )) || fail '--mode 缺少 git / release / both。'
        MODE="$2"; MODE_FIXED=1; shift 2 ;;
      --direct) RECURSIVE=0; SCOPE_FIXED=1; shift ;;
      *) fail "未知参数：$1" ;;
    esac
  done
  [[ -z "$MODE" || "$MODE" == git || "$MODE" == release || "$MODE" == both ]] || fail '模式必须为 git / release / both。'
  if (( HELP_ONLY )); then
    print -r -- '用法：/bin/zsh 脚本.command [--repo WindowsOS_7 ...] [--mode git|release|both] [--direct]'
    print -r -- '默认使用 fzf 选择模式、子仓与递归范围；--direct 仅直属，--list 只列本地登记。'
    print -r -- 'fzf 多选：Enter 勾选/取消，Space 确认；Ctrl-A 全选、Ctrl-D 清空、Esc 取消；空选不执行。'
    print -r -- '子层按 ← 返回上一选择面板并保留已选项；Release 可返回主入口，已完成操作保留，重新执行仍需确认。'
    print -r -- '需要可用的 fzf（支持 --footer）；缺失时可自行运行 brew install fzf，不回退数字菜单。'
    print -r -- '普通运行始终需要终端确认；不提供静默覆盖、提交或推送选项。'
    exit 0
  fi
}
# 检查 Git 和入口归属，读出当前真实子模块清单。
check_environment() {
  command -v git >/dev/null && git --version >/dev/null || fail 'Git 不可用，请先安装 Command Line Tools / Git。'
  [[ "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" == "$SCRIPT_DIR" ]] || fail '脚本必须位于父仓根目录。'
  [[ -f "$SCRIPT_DIR/.gitmodules" && ! -L "$SCRIPT_DIR/.gitmodules" ]] || fail '未发现普通 .gitmodules 文件，请先运行添加子模块入口。'
  load_modules "$SCRIPT_DIR"
  (( ${#MODULE_NAMES} )) || fail '.gitmodules 中没有子模块。'
  if (( READ_ONLY )); then
    local i
    for (( i=1; i<=${#MODULE_NAMES}; ++i )); do
      log_message "$i、${MODULE_NAMES[$i]} → ${MODULE_PATHS[$i]} | $(git -C "$SCRIPT_DIR" config -f .gitmodules --get "submodule.${MODULE_NAMES[$i]}.url")"
    done
    exit 0
  fi
  : > "$LOG_FILE" || exit 1
  trap 'log_message "⚠ 已中断；已有工作区和下载记录保留。"; exit 130' INT TERM
  check_git_state "$SCRIPT_DIR"
}
# 验证当前选择器可执行并支持固定的按键提示，不静默退回编号输入。
check_fzf_environment() {
  FZF_BIN="$(command -v fzf 2>/dev/null)"
  [[ -n "$FZF_BIN" ]] && FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= FZF_DEFAULT_COMMAND= "$FZF_BIN" --version >/dev/null 2>&1 || fail 'fzf 未安装或不可用；请先运行 brew install fzf 后重试。'
  local help_text
  help_text="$(FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= FZF_DEFAULT_COMMAND= "$FZF_BIN" --help)" || fail '无法读取 fzf 能力。'
  [[ "$help_text" == *--footer* ]] || fail 'fzf 版本过旧，缺少 --footer；请更新 fzf 后重试。'
}
# 使用隔离的 fzf 配置收集选择；多选空集不会隐式返回高亮行。
choose_with_fzf() {
  local title="$1" multiple="$2" back_title="$3" result="" result_code=0 hint="" row key initial_key start_action="" position=0
  shift 3
  local -a candidates=("$@")
  [[ -n "$FZF_BIN" ]] || check_fzf_environment
  local -a options=(--sync --height=~70% --min-height=12 --layout=reverse --border --no-sort --delimiter=$'\t' --with-nth=2.. --prompt='搜索 > ' --border-label="$title")
  FZF_RESULTS=()
  if [[ "$multiple" == 1 ]]; then
    hint=$'Enter 勾选/取消；Space 确认；空选不执行\nCtrl-A 全选；Ctrl-D 清空；Esc / Ctrl-C 取消'
    options+=(--multi --bind 'enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,esc:abort,space:transform:if [ "$FZF_SELECT_COUNT" -gt 0 ]; then printf accept; else printf abort; fi')
  else
    hint='↑↓ 移动或输入搜索；Enter 确认；Esc / Ctrl-C 取消'
    options+=(--no-multi --bind 'enter:accept,esc:abort')
  fi
  if [[ -n "$back_title" ]]; then
    hint+=$'\n'"← 返回$back_title"
    options+=(--expect=left)
  fi
  for row in "${candidates[@]}"; do
    (( position++ ))
    key="${row%%$'\t'*}"
    for initial_key in "${FZF_INITIAL_KEYS[@]}"; do
      if [[ "$key" == "$initial_key" ]]; then
        [[ -n "$start_action" ]] && start_action+='+'
        start_action+="pos($position)"
        [[ "$multiple" == 1 ]] && start_action+='+select'
        break
      fi
    done
  done
  [[ -n "$start_action" ]] && options+=(--bind="start:$start_action")
  options+=(--header="$hint" --footer="$hint")
  result="$(printf '%s\n' "$@" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= FZF_DEFAULT_COMMAND= "$FZF_BIN" "${options[@]}")" || result_code=$?
  if [[ -n "$back_title" && "${result%%$'\n'*}" == left && ( "$result_code" == 0 || "$result_code" == 1 ) ]]; then
    return 10
  fi
  case "$result_code" in
    0) ;;
    1|130)
      log_message "ℹ $title：取消或空选，本次没有执行所选任务。"
      return 1
      ;;
    *) fail "fzf 选择失败（退出码 $result_code）：$title" ;;
  esac
  if [[ -n "$back_title" ]]; then
    key="${result%%$'\n'*}"
    [[ "$result" == *$'\n'* ]] || return 1
    result="${result#*$'\n'}"
  fi
  if [[ -z "$result" ]]; then
    log_message "ℹ $title：没有选中条目，本次没有执行所选任务。"
    return 1
  fi
  FZF_RESULTS=("${(@f)result}")
  for row in "${FZF_RESULTS[@]}"; do
    (( ${candidates[(Ie)$row]} > 0 )) || fail "fzf 返回清单之外的条目：$title"
  done
}
# 读取 NUL 分隔清单，兼容目录中的空格与中文。
load_modules() {
  local repo="$1" record key
  MODULE_NAMES=()
  MODULE_PATHS=()
  git -C "$repo" config -f .gitmodules --list >/dev/null || fail "清单解析失败：$repo/.gitmodules"
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"
    MODULE_NAMES+=("${${key#submodule.}%.path}")
    MODULE_PATHS+=("${record#*$'\n'}")
  done < <(git -C "$repo" config -z -f .gitmodules --get-regexp '^submodule\..*\.path$')
}
# 拒绝冲突、未结束操作和 Git 锁，保护已有索引。
check_git_state() {
  local repo="$1" marker location
  for marker in index.lock HEAD.lock packed-refs.lock shallow.lock MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD sequencer rebase-merge rebase-apply BISECT_LOG; do
    location="$(git -C "$repo" rev-parse --path-format=absolute --git-path "$marker")" || fail "无法解析 Git 状态：$repo"
    [[ ! -e "$location" ]] || fail "仓库有锁或未完成 Git 操作：$repo ($marker)"
  done
  [[ -z "$(git -C "$repo" ls-files --unmerged)" ]] || fail "仓库存在合并冲突：$repo"
}
# 仅在仓库有效启用目录过滤器时恢复当前 Markdown 并验证。
restore_configured_toc() {
  local repo="$1" smudge process
  check_git_state "$repo"
  smudge="$(git -C "$repo" config --get filter.jobs-markdown-toc.smudge 2>/dev/null)"
  if [[ -z "$smudge" ]]; then
    log_message "ℹ Markdown 无有效 smudge，跳过：$repo"
    return 0
  fi
  process="$(git -C "$repo" config --get filter.jobs-markdown-toc.process 2>/dev/null)"
  [[ -z "$process" ]] || fail "Markdown process 与安全还原入口冲突：$repo"
  [[ -f "$repo/.jobs-markdown-toc/MarkdownToc.mjs" ]] || fail "已配置过滤器但缺少本仓还原工具：$repo"
  command -v node >/dev/null && node --version >/dev/null || fail "已配置过滤器但 Node.js 不可用：$repo"
  run_logged node "$repo/.jobs-markdown-toc/MarkdownToc.mjs" restore || fail "Markdown 还原失败：$repo"
  run_logged node "$repo/.jobs-markdown-toc/MarkdownToc.mjs" verify || fail "Markdown 验证失败：$repo"
}
# 检查当前仓自己的源码；后代子模块的 HEAD 漂移不当作源码脏改动。
assert_clean_source() {
  local repo="$1" changes entry
  check_git_state "$repo"
  git -C "$repo" diff --cached --quiet --ignore-submodules=none || fail "仓库已有暂存内容（含 gitlink），保留并停止：$repo"
  while IFS= read -r -d '' entry; do
    case "${entry[1]}" in
      S|[a-z]) fail "仓库有 skip-worktree / assume-unchanged 条目，需先人工核对：$repo (${entry#??})" ;;
    esac
  done < <(git -C "$repo" ls-files -v -z)
  changes="$(git -C "$repo" status --porcelain --ignore-submodules=all --untracked-files=normal)" || fail "无法读取工作区状态：$repo"
  if [[ -n "$changes" ]]; then
    intro_line title "✖ 未提交源码，保留并停止：$repo"
    log_message "$changes"
    fail '请在外部处理该仓暂存、未暂存或未跟踪文件后重新运行；脚本不会舍弃内容。'
  fi
}
# 循环选择模式、子仓和范围；返回仅调整待执行计划，不启动业务。
select_scope() {
  local answer="" i found name row back_step="" back_title="" result_code=0
  local -a choices=()
  if (( ${#REQUESTED} && ! ${#SELECTED} )); then
    for name in "${REQUESTED[@]}"; do
      found=0
      for (( i=1; i<=${#MODULE_NAMES}; ++i )); do
        if [[ "$name" == "${MODULE_NAMES[$i]}" || "$name" == "${MODULE_PATHS[$i]}" ]]; then
          SELECTED+=("${MODULE_NAMES[$i]}"); found=1; break
        fi
      done
      (( found )) || fail "未登记的子仓：$name"
    done
  fi
  [[ -n "$SCOPE_STEP" ]] || SCOPE_STEP=mode
  while [[ "$SCOPE_STEP" != confirm ]]; do
    case "$SCOPE_STEP" in
      mode)
        if (( ! MODE_FIXED )); then
          choices=($'git\t只更新 Git 子仓' $'release\t只下载 Release 附件' $'both\tGit + Release：先同步，再选择附件下载')
          FZF_INITIAL_KEYS=("$MODE")
          choose_with_fzf '选择操作模式' 0 '' "${choices[@]}" || exit 0
          MODE="${FZF_RESULTS[1]%%$'\t'*}"
          LAST_SCOPE_STEP=mode
        fi
        SCOPE_STEP=repositories
        ;;
      repositories)
        if (( ! ${#REQUESTED} )); then
          choices=()
          FZF_INITIAL_KEYS=()
          for (( i=1; i<=${#MODULE_NAMES}; ++i )); do
            choices+=("$i"$'\t'"${MODULE_NAMES[$i]} (${MODULE_PATHS[$i]})")
            (( ${SELECTED[(Ie)${MODULE_NAMES[$i]}]} > 0 )) && FZF_INITIAL_KEYS+=("$i")
          done
          back_title=""
          (( ! MODE_FIXED )) && back_title='操作模式'
          result_code=0
          choose_with_fzf '选择 Windows 子仓' 1 "$back_title" "${choices[@]}" || result_code=$?
          if (( result_code == 10 )); then
            SCOPE_STEP=mode
            continue
          fi
          (( result_code == 0 )) || exit 0
          SELECTED=()
          for row in "${FZF_RESULTS[@]}"; do
            i="${row%%$'\t'*}"
            SELECTED+=("${MODULE_NAMES[$i]}")
          done
          SELECTED=("${(@u)SELECTED}")
          LAST_SCOPE_STEP=repositories
        fi
        SCOPE_STEP=scope
        ;;
      scope)
        if [[ "$MODE" != release && "$SCOPE_FIXED" == 0 ]]; then
          choices=($'recursive\t向下递归：同步所选子仓及其后代' $'direct\t仅直属一层：同步所选子仓')
          FZF_INITIAL_KEYS=(recursive)
          (( ! RECURSIVE )) && FZF_INITIAL_KEYS=(direct)
          back_step=""; back_title=""
          if (( ! ${#REQUESTED} )); then
            back_step=repositories; back_title='Windows 子仓'
          elif (( ! MODE_FIXED )); then
            back_step=mode; back_title='操作模式'
          fi
          result_code=0
          choose_with_fzf '选择 Git 同步范围' 0 "$back_title" "${choices[@]}" || result_code=$?
          if (( result_code == 10 )); then
            SCOPE_STEP="$back_step"
            continue
          fi
          (( result_code == 0 )) || exit 0
          RECURSIVE=1
          [[ "${FZF_RESULTS[1]%%$'\t'*}" == direct ]] && RECURSIVE=0
          LAST_SCOPE_STEP=scope
        fi
        SCOPE_STEP=confirm
        ;;
    esac
  done
  log_message "计划：mode=$MODE，向下递归=$RECURSIVE，子仓=${(j:, :)SELECTED}"
  IFS= read -r 'answer?直接回车执行所选任务；输入任意字符后回车跳过：' || exit 1
  [[ -z "$answer" ]] || { log_message 'ℹ 已跳过所选任务，Git 和 Release 均未执行。'; exit 0; }
}
# 解析父仓默认下载 remote，与 Git 子模块的相对地址规则一致。
default_remote() {
  local repo="$1" branch remote
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)"
  remote="$(git -C "$repo" config --get "branch.$branch.remote" 2>/dev/null)"
  [[ -n "$remote" && "$remote" != . ]] || remote=origin
  git -C "$repo" config --get "remote.$remote.url" >/dev/null || fail "父仓缺少明确的下载 remote：$repo ($remote)"
  print -r -- "$remote"
}
# 校验子模块路径和真实 gitlink，拒绝越界、符号链接及普通目录误接管。
validate_module_path() {
  local parent="$1" rel="$2" part cursor="$1" item
  [[ -n "$rel" && "$rel" != /* && "$rel" != *$'\n'* && "$rel" != *$'\r'* ]] || fail "不安全的子模块路径：$rel"
  case "/$rel/" in
    *'/../'*|*'/./'*|*'//'*) fail "子模块路径不可包含 . / .. / 空段：$rel" ;;
  esac
  for part in "${(@s:/:)rel}"; do
    cursor="$cursor/$part"
    [[ ! -L "$cursor" ]] || fail "子模块路径经过符号链接：$cursor"
  done
  item="$(git -C "$parent" -c core.quotePath=false ls-files --stage -- "$rel")" || fail "无法检查 gitlink：$parent/$rel"
  [[ "$item" == '160000 '* && "$item" != *$'\n'* && "${${item#* }#* }" == "0"$'\t'"$rel" ]] || fail "缺失或冲突的 gitlink：$parent/$rel"
}
# 在传输前突出本次仓库、父仓线路、真实来源和目标分支。
show_source() {
  local parent="$1" child="$2" configured="$3" actual="$4" branch="$5" scope="$6" parent_remote parent_url host
  parent_remote="$(default_remote "$parent")" || exit 1
  parent_url="$(git -C "$parent" config --get "remote.$parent_remote.url")"
  host="${actual#*://}"; host="${host#*@}"; host="${host%%[/:]*}"
  [[ -n "$host" ]] || host="本地文件系统"
  log_message '━━━━━━━━━━ 来源｜Git 子仓 ━━━━━━━━━━'
  log_message "📦 子仓：${child:t} | 🌐 平台 / 主机：$host"
  log_message "父仓：$parent | remote=$parent_remote | $parent_url"
  log_message "登记地址：$configured"
  log_message "拉取地址（本地规则展开）：$actual | $scope"
  log_message "目标分支：$branch | 目标位置：$child"
}
# 对一个已登记子仓恢复跟踪分支并安全快进，再处理所选后代。
sync_one_module() {
  local parent="$1" section="$2" rel="$3" depth="$4"
  (( depth <= 64 )) || fail "递归层数超过 64，可能存在子模块循环；停止：$parent/$rel"
  local child="$parent/$rel" configured url remote branch actual old_head="" old_ref="" target local_target new_clone=0
  local record child_section child_rel default_ref
  validate_module_path "$parent" "$rel"
  configured="$(git -C "$parent" config -f .gitmodules --get "submodule.$section.url")" || fail "子模块缺少 URL：$section"
  branch="$(git -C "$parent" config -f .gitmodules --get "submodule.$section.branch" 2>/dev/null)"
  if [[ "$branch" == . ]]; then
    branch="$(git -C "$parent" symbolic-ref --quiet --short HEAD)" || fail "branch=. 但直接父仓没有本地分支：$parent"
  fi
  if [[ -e "$child/.git" ]]; then
    [[ "$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" == "$child" ]] || fail "子仓 Git 元数据无效：$child"
    restore_configured_toc "$child"
    assert_clean_source "$child"
    remote=origin
    if [[ -n "$branch" ]]; then
      remote="$(git -C "$child" config --get "branch.$branch.remote" 2>/dev/null)"
      [[ -n "$remote" && "$remote" != . ]] || remote=origin
    fi
    url="$(git -C "$child" config --get "remote.$remote.url")" || fail "子仓没有 remote=$remote：$child"
    actual="$(git -C "$child" remote get-url "$remote")" || fail "无法展开子仓来源：$child"
    old_head="$(git -C "$child" rev-parse HEAD)" || fail "子仓没有有效 HEAD：$child"
    old_ref="$(git -C "$child" symbolic-ref --quiet HEAD 2>/dev/null)"
    show_source "$parent" "$child" "$configured" "$actual" "${branch:-待查询远端默认分支}" "已有仓 $remote 配置作用域"
  else
    [[ ! -e "$child" || ( -d "$child" && -z "$(ls -A "$child")" ) ]] || fail "非空或非 Git 目录，保留并停止：$child"
    run_logged git -C "$parent" submodule init -- "$rel" || fail "初始化子模块登记失败：$child"
    url="$(git -C "$parent" config --get "submodule.$section.url")" || fail "无法解析子模块地址：$child"
    actual="$(git -C / ls-remote --get-url "$url")" || fail "无法展开首次克隆地址：$child"
    show_source "$parent" "$child" "$configured" "$actual" "${branch:-远端默认分支（克隆后确认）}" '首次克隆：系统 / 全局 / 进程配置，不读取父仓 local 重写'
    local -a clone_args=(--no-checkout --no-recurse-submodules)
    if [[ -n "$branch" ]]; then
      git check-ref-format --branch "$branch" >/dev/null || fail "无效分支：$branch"
      clone_args+=(--branch "$branch")
    fi
    run_logged git -C / clone "${clone_args[@]}" -- "$url" "$child" || fail "克隆失败：$child；来源：$actual"
    remote=origin
    new_clone=1
    if [[ -z "$branch" ]]; then
      default_ref="$(git -C "$child" symbolic-ref --quiet refs/remotes/origin/HEAD)" || fail "远端没有明确默认分支：$child"
      branch="${default_ref#refs/remotes/origin/}"
    fi
  fi
  if [[ -z "$branch" ]]; then
    default_ref="$(git -C "$child" ls-remote --symref "$remote" HEAD 2>&1)" || fail "查询远端默认分支失败：$child；来源：$actual"
    branch="$(print -r -- "$default_ref" | sed -n 's/^ref: refs\/heads\/\([^[:space:]]*\)[[:space:]]*HEAD$/\1/p')"
    [[ -n "$branch" ]] || fail "远端没有明确默认分支：$child"
  fi
  git check-ref-format --branch "$branch" >/dev/null || fail "无效分支：$branch"
  show_source "$parent" "$child" "$configured" "$actual" "$branch" "fetch 使用 $remote 自身配置作用域"
  run_logged git -C "$child" -c fetch.recurseSubmodules=false fetch --no-tags "$remote" "+refs/heads/${branch}:refs/remotes/${remote}/${branch}" || fail "分支获取失败：$child ($branch)；来源：$actual"
  target="$(git -C "$child" rev-parse --verify "refs/remotes/$remote/$branch^{commit}")" || fail "目标分支不存在：$child ($branch)"
  if (( ! new_clone )); then
    [[ "$(git -C "$child" rev-parse HEAD)" == "$old_head" && "$(git -C "$child" symbolic-ref --quiet HEAD 2>/dev/null)" == "$old_ref" ]] || fail "传输期间子仓 HEAD / 分支被修改：$child"
    assert_clean_source "$child"
    git -C "$child" merge-base --is-ancestor "$old_head" "$target" || fail "存在本地独有提交、领先或分叉；保留并停止：$child"
    local_target="$(git -C "$child" rev-parse --verify "refs/heads/$branch^{commit}" 2>/dev/null)"
    if [[ -n "$local_target" ]]; then
      git -C "$child" merge-base --is-ancestor "$local_target" "$target" || fail "目标本地分支有独有提交；保留并停止：$child ($branch)"
    fi
  fi
  if git -C "$child" show-ref --verify --quiet "refs/heads/$branch"; then
    run_logged git -C "$child" -c submodule.recurse=false checkout --no-overwrite-ignore "$branch" || fail "无法安全切换分支：$child"
    run_logged git -C "$child" -c submodule.recurse=false merge --ff-only --no-autostash --no-overwrite-ignore --no-edit "$target" || fail "无法安全快进：$child"
  else
    run_logged git -C "$child" -c submodule.recurse=false checkout --no-overwrite-ignore -b "$branch" "$target" || fail "无法安全建立分支：$child"
  fi
  run_logged git -C "$child" branch --set-upstream-to="$remote/$branch" "$branch" || fail "无法配置跟踪分支：$child"
  run_logged git -C "$parent" submodule absorbgitdirs -- "$rel" || fail "无法归集子仓 Git 元数据：$child"
  [[ -f "$child/.git" && "$(git -C "$child" rev-parse HEAD)" == "$target" && "$(git -C "$child" symbolic-ref --quiet --short HEAD)" == "$branch" ]] || fail "子仓最终状态核验失败：$child"
  restore_configured_toc "$child"
  log_message "✔ 已同步：$child → $remote/$branch @ $target；来源：$actual"
  if (( RECURSIVE )) && [[ -f "$child/.gitmodules" ]]; then
    [[ ! -L "$child/.gitmodules" ]] || fail "拒绝符号链接清单：$child/.gitmodules"
    git -C "$child" config -f .gitmodules --list >/dev/null || fail "后代清单损坏：$child"
    while IFS= read -r -d '' record; do
      child_section="${${${record%%$'\n'*}#submodule.}%.path}"
      child_rel="${record#*$'\n'}"
      sync_one_module "$child" "$child_section" "$child_rel" "$((depth + 1))"
    done < <(git -C "$child" config -z -f .gitmodules --get-regexp '^submodule\..*\.path$')
  fi
}
# 执行所选树并按需转交 Release 入口，失败立即停止。
execute_plan() {
  local name i result_code=0 release_entry="$SCRIPT_DIR/【MacOS】⏬按需下载WindowsOS Release.command"
  local -a release_args=()
  if [[ "$MODE" != release ]]; then
    CURRENT_STAGE=Git
    log_message '━━━━━━━━━━ 阶段 1｜Git 子仓同步 ━━━━━━━━━━'
    restore_configured_toc "$SCRIPT_DIR"
    for name in "${SELECTED[@]}"; do
      for (( i=1; i<=${#MODULE_NAMES}; ++i )); do
        if [[ "$name" == "${MODULE_NAMES[$i]}" ]]; then
          sync_one_module "$SCRIPT_DIR" "$name" "${MODULE_PATHS[$i]}" 1
          break
        fi
      done
    done
    restore_configured_toc "$SCRIPT_DIR"
  fi
  if [[ "$MODE" != git ]]; then
    CURRENT_STAGE=Release
    log_message '━━━━━━━━━━ Release 阶段｜选择版本和附件并下载 ━━━━━━━━━━'
    [[ -f "$release_entry" && ! -L "$release_entry" ]] || fail "缺少同级 Release 下载入口：$release_entry"
    for name in "${SELECTED[@]}"; do
      case "$name" in
        WindowsOS_8.1|WindowsOS_10|WindowsOS_11|WindowsOS_2003|WindowsOS_XP|WindowsOS_7) release_args+=(--repo "$name") ;;
        *) fail "此子仓未配置 GitHub Release 来源：$name" ;;
      esac
    done
    log_message "Release 目标：对应子仓 / Releases / <标签>；即将选择版本与附件。"
    [[ -n "$LAST_SCOPE_STEP" ]] && release_args+=(--parent-back)
    /bin/zsh "$release_entry" --from-parent "${release_args[@]}" || result_code=$?
    (( result_code == 10 )) && return 10
    (( result_code == 0 )) || fail 'Release 阶段失败；查看该入口日志，已经下载的文件和断点保留。'
  fi
  if [[ "$MODE" == git ]]; then
    log_message "✔ Git 子仓同步完成。父仓 gitlink 差异留待审阅，不提交、不推送。日志：$LOG_FILE"
  else
    log_message "ℹ 流程结束；Release 实际下载、已存在与跳过数量见该阶段汇总。父仓 gitlink 差异留待审阅，不提交、不推送。日志：$LOG_FILE"
  fi
}
# 承接 Release 的返回信号，回到上一选择层，已有结果保留且重新执行仍需确认。
select_and_execute_plan() {
  local result_code=0
  while true; do
    select_scope
    result_code=0
    execute_plan || result_code=$?
    (( result_code == 10 )) || return "$result_code"
    log_message 'ℹ 已返回主入口选择；已完成的 Git 更新和附件保留，重新执行仍需确认。'
    SCOPE_STEP="$LAST_SCOPE_STEP"
  done
}
# 集中编排自述、检查、选择与同步。
main() {
  show_script_intro_and_wait "$@" # 首先展示用途和影响，普通运行等待回车。
  parse_options "$@" # 校验明确参数，帮助模式只读退出。
  check_environment # 检查 Git、入口和真实子模块登记。
  select_and_execute_plan # 往返选择模式、子仓和范围，确认后安全同步并按需下载附件。
}
main "$@"
