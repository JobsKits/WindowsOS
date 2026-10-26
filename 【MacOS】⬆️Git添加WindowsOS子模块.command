#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⬆️Git添加WindowsOS子模块.command
# - 核心用途：增量关联六个 Windows 子仓，登记 .gitmodules 与真实 gitlink。
# - 影响范围：仅新增子仓的工作区、父仓 .gitmodules / gitlink 索引及本地登记；不提交、不推送。
# - 运行提示：先读自述并按回车确认；添加前再次确认，回车跳过；--dry-run 只检查不写入。
# shell: zsh

ENTRY_PATH="$0"
SCRIPT_DIR=""
LOG_FILE=""
DRY_RUN=0
HELP_ONLY=0
SUBMODULE_NAMES=(WindowsOS_8.1 WindowsOS_10 WindowsOS_11 WindowsOS_2003 WindowsOS_XP WindowsOS_7)
MISSING_NAMES=()

# 准备展示路径并打印固定自述，写操作必须等用户确认后执行。
show_script_intro_and_wait() {
  SCRIPT_DIR="${ENTRY_PATH:A:h}"
  LOG_FILE="${TMPDIR:-/tmp}/${ENTRY_PATH:t:r}.$$.log"
  local arg answer=""
  for arg in "$@"; do
    [[ "$arg" == --dry-run ]] && DRY_RUN=1
    [[ "$arg" == --help || "$arg" == -h ]] && HELP_ONLY=1
  done
  intro_line title 'WindowsOS 增量添加 Git 子模块'
  intro_line body '1、关联 WindowsOS_8.1 / 10 / 11 / 2003 / XP / 7，保留已有登记和子仓。'
  intro_line body '2、新增项使用 git submodule add，暂存对应 .gitmodules 与 gitlink；不处理其它暂存文件。'
  intro_line body '3、不清理目录、不重置、不提交、不推送；Ctrl+C 取消。'
  intro_line body "4、日志：$LOG_FILE；--dry-run 只读预检，不下载、不创建日志。"
  (( DRY_RUN || HELP_ONLY )) && return 0
  [[ -t 0 ]] || { print -u2 -r -- '✖ 当前没有可交互输入，请在终端运行；只读可用 --dry-run。'; exit 1; }
  read -r 'answer?已了解用途与影响，按回车继续；Ctrl+C 取消：' || exit 1
}
# 自述标题红色加粗、正文蓝色，非彩色环境输出纯文本。
intro_line() {
  local code='0;34'
  [[ "$1" == title ]] && code='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && -z "${SOURCETREE:-}${SOURCE_TREE:-}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$2"
  else
    print -r -- "$2"
  fi
}
# 展示输出过滤 ANSI 和 URL 敏感字段，不改写实际地址。
sanitize_stream() {
  sed -E $'s/\033\\[[0-9;]*[[:alpha:]]//g; s#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\\1[REDACTED]@#g; s#(https?://)[^/@[:space:]]+@#\\1[REDACTED]@#g; s#(https?://[^?[:space:]]+)\\?[^[:space:]]*#\\1?[REDACTED]#g'
}
# 同步打印并保存脱敏纯文本日志。
log_message() {
  if (( DRY_RUN || HELP_ONLY )); then
    print -r -- "$*" | sanitize_stream
  else
    print -r -- "$*" | sanitize_stream | tee -a "$LOG_FILE"
  fi
}
# 明确报告失败阶段并停止，已完成项保留供审阅。
fail() {
  log_message "✖ $*"
  exit 1
}
# 记录外部命令输出，传播任何执行失败。
run_logged() {
  "$@" 2>&1 | sanitize_stream | tee -a "$LOG_FILE"
}
# 校验选项和分支，避免参数被解释为命令选项。
parse_options() {
  setopt NO_NOMATCH PIPE_FAIL
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run|--help|-h) ;;
      *) fail "未知参数：$arg" ;;
    esac
  done
  if (( HELP_ONLY )); then
    print -r -- '用法：/bin/zsh 脚本.command [--dry-run]'
    print -r -- 'SUBMODULE_BRANCH 默认 main；SUBMODULE_URL_PREFIX 默认 https://github.com/JobsKits。'
    print -r -- '环境参数只用于新登记，已有 section / URL / branch / gitlink 保留。'
    exit 0
  fi
  command -v git >/dev/null && git --version >/dev/null || fail 'Git 不可用，请先安装 Git / Command Line Tools。'
  git check-ref-format --branch "${SUBMODULE_BRANCH:-main}" >/dev/null || fail 'SUBMODULE_BRANCH 不是有效分支。'
  [[ "${SUBMODULE_URL_PREFIX:-https://github.com/JobsKits}" != *$'\n'* && "${SUBMODULE_URL_PREFIX:-https://github.com/JobsKits}" != -* ]] || fail '来源地址无效。'
}
# 验证仓库、锁与冲突，禁止在未结束操作期间登记。
check_environment() {
  [[ "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" == "$SCRIPT_DIR" ]] || fail '脚本必须位于已有父仓根目录。'
  git -C "$SCRIPT_DIR" rev-parse --verify HEAD >/dev/null || fail '父仓尚无提交；请由用户先建立初始提交。'
  local marker location
  for marker in index.lock HEAD.lock packed-refs.lock MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    location="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-path "$marker")" || fail '无法检查 Git 状态。'
    [[ ! -e "$location" ]] || fail "父仓有锁或未完成操作：$marker"
  done
  [[ -z "$(git -C "$SCRIPT_DIR" ls-files --unmerged)" ]] || fail '父仓有合并冲突。'
  [[ ! -L "$SCRIPT_DIR/.gitmodules" ]] || fail '拒绝符号链接 .gitmodules。'
  if [[ -e "$SCRIPT_DIR/.gitmodules" ]]; then
    [[ -f "$SCRIPT_DIR/.gitmodules" ]] || fail '.gitmodules 不是普通文件。'
    git -C "$SCRIPT_DIR" config -f .gitmodules --list >/dev/null || fail '.gitmodules 无法解析。'
  fi
}
# 完整预检六仓再写入；既有登记只核验，不覆盖 URL、branch 或索引指针。
prepare_registration_plan() {
  local name record key rel section existing item url
  local -a records=()
  if [[ -f "$SCRIPT_DIR/.gitmodules" ]]; then
    while IFS= read -r -d '' record; do
      records+=("$record")
    done < <(git -C "$SCRIPT_DIR" config -z -f .gitmodules --get-regexp '^submodule\..*\.path$')
  fi
  for name in "${SUBMODULE_NAMES[@]}"; do
    existing=""
    for record in "${records[@]}"; do
      key="${record%%$'\n'*}"
      rel="${record#*$'\n'}"
      if [[ "$rel" == "$name" ]]; then
        [[ -z "$existing" ]] || fail "重复登记同一路径：$name"
        existing="${${key#submodule.}%.path}"
      fi
    done
    [[ ! -L "$SCRIPT_DIR/$name" ]] || fail "拒绝符号链接子仓：$name"
    item="$(git -C "$SCRIPT_DIR" ls-files --stage -- "$name")" || fail "无法读取索引：$name"
    if [[ -n "$existing" ]]; then
      url="$(git -C "$SCRIPT_DIR" config -f .gitmodules --get "submodule.$existing.url")" || fail "已有子模块缺少 URL：$existing"
      [[ "$item" == '160000 '* && "$item" != *$'\n'* && "${${item#* }#* }" == "0"$'\t'"$name" ]] || fail "已有登记缺少有效 gitlink，保留并停止：$name"
      if [[ -e "$SCRIPT_DIR/$name/.git" ]]; then
        [[ "$(git -C "$SCRIPT_DIR/$name" rev-parse --show-toplevel 2>/dev/null)" == "$SCRIPT_DIR/$name" ]] || fail "已有子仓损坏：$name"
      elif [[ -e "$SCRIPT_DIR/$name" && ( ! -d "$SCRIPT_DIR/$name" || -n "$(ls -A "$SCRIPT_DIR/$name")" ) ]]; then
        fail "已有路径非空但不是 Git 仓：$name"
      fi
      log_message "ℹ 保留已有登记：$name | section=$existing | $url"
      continue
    fi
    [[ -z "$item" ]] || fail "目标已经被跟踪或暂存删除，保留并停止：$name"
    if git -C "$SCRIPT_DIR" cat-file -e "HEAD:$name" 2>/dev/null; then
      fail "目标在 HEAD 中已跟踪但索引缺失，可能有暂存删除：$name"
    fi
    if [[ -e "$SCRIPT_DIR/$name" ]]; then
      [[ -d "$SCRIPT_DIR/$name" && -z "$(ls -A "$SCRIPT_DIR/$name")" ]] || fail "新增目标已有内容，保留并停止：$name"
    fi
    if [[ -f "$SCRIPT_DIR/.gitmodules" ]] && git -C "$SCRIPT_DIR" config -f .gitmodules --get-regexp "^submodule\\.${name//./\\.}\\." >/dev/null 2>&1; then
      fail "同名 section 已用于其它路径：$name"
    fi
    MISSING_NAMES+=("$name")
    log_message "计划新增：$name | ${SUBMODULE_URL_PREFIX:-https://github.com/JobsKits}/$name.git | branch=${SUBMODULE_BRANCH:-main}"
  done
  if (( ${#MISSING_NAMES} )); then
    git -C "$SCRIPT_DIR" diff --quiet -- .gitmodules && git -C "$SCRIPT_DIR" diff --cached --quiet -- .gitmodules || fail '.gitmodules 已有工作区或暂存改动；请先审阅，避免新增操作一并暂存它们。'
  fi
}
# 确认后仅登记缺失项，使用 Git 官方命令生成关联与归集元数据。
apply_registration_plan() {
  local answer="" name url actual parent_remote parent_url backup_dir
  if (( DRY_RUN )); then
    log_message "✔ 只读预检完成，缺少 ${#MISSING_NAMES} 项；没有写入或下载。"
    return 0
  fi
  : >> "$LOG_FILE" || exit 1
  trap 'log_message "⚠ 已中断；已完成的登记保留供审阅。"; exit 130' INT TERM
  if (( ! ${#MISSING_NAMES} )); then
    log_message '✔ 六仓均已登记；不更新子仓、不修改已有配置或索引。'
    return 0
  fi
  read -r 'answer?输入任意字符后回车登记所列新增项；直接回车跳过：' || exit 1
  [[ -n "$answer" ]] || return 0
  backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/windowsos-registration.XXXXXX")" || fail '无法建立登记前备份。'
  if [[ -f "$SCRIPT_DIR/.gitmodules" ]]; then
    cp -p "$SCRIPT_DIR/.gitmodules" "$backup_dir/gitmodules.before" || fail '备份 .gitmodules 失败。'
  fi
  git -C "$SCRIPT_DIR" ls-files --stage > "$backup_dir/index-entries.before.txt" || fail '无法保存索引条目快照。'
  log_message "登记前清单与索引条目快照：$backup_dir"
  parent_remote="$(git -C "$SCRIPT_DIR" config --get "branch.$(git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD).remote" 2>/dev/null)"
  [[ -n "$parent_remote" && "$parent_remote" != . ]] || parent_remote=origin
  parent_url="$(git -C "$SCRIPT_DIR" config --get "remote.$parent_remote.url" 2>/dev/null)"
  for name in "${MISSING_NAMES[@]}"; do
    url="${SUBMODULE_URL_PREFIX:-https://github.com/JobsKits}/$name.git"
    actual="$(git -C / ls-remote --get-url "$url")" || fail "无法展开首次克隆来源：$name"
    log_message '━━━━━━━━━━ 来源｜添加 Git 子模块 ━━━━━━━━━━'
    log_message "📦 子仓：$name | 🌐 主机：${${actual#*://}%%/*}"
    log_message "父仓：$SCRIPT_DIR | remote=$parent_remote | $parent_url"
    log_message "登记地址：$url | 拉取地址（系统 / 全局 / 进程规则展开）：$actual"
    log_message "分支：${SUBMODULE_BRANCH:-main} | 目标：$SCRIPT_DIR/$name"
    run_logged git -C "$SCRIPT_DIR" submodule add -b "${SUBMODULE_BRANCH:-main}" -- "$url" "$name" || fail "添加失败：$name；来源：$actual；已完成项保留。"
    run_logged git -C "$SCRIPT_DIR" submodule absorbgitdirs -- "$name" || fail "元数据归集失败：$name"
    [[ -f "$SCRIPT_DIR/$name/.git" ]] || fail "子仓 .git 指针核验失败：$name"
    log_message "✔ 已登记：$name @ $(git -C "$SCRIPT_DIR/$name" rev-parse HEAD)；来源：$actual"
  done
  log_message "✔ 已添加 ${#MISSING_NAMES} 个子模块；仅相关 .gitmodules 与 gitlink 已暂存，请审阅；未提交、未推送。日志：$LOG_FILE"
}
# 集中编排说明、校验、完整预检与增量登记。
main() {
  show_script_intro_and_wait "$@" # 首先说明索引影响，普通运行等待回车。
  parse_options "$@" # 校验只读选项、来源前缀和目标分支。
  check_environment # 确认父仓与 Git 操作状态可安全登记。
  prepare_registration_plan # 预检全部目标，保留既有记录与内容。
  apply_registration_plan # 确认后仅新增缺项，并核验真实子模块关联。
}
main "$@"
