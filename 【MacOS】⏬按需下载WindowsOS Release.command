#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬按需下载WindowsOS Release.command
# - 核心用途：选择 Windows 子仓、Release 和附件，自动补齐同组 ISO 分卷后按需下载。
# - 影响范围：写对应子仓 Releases、该仓本地忽略与临时日志；不修改受跟踪源码，不运行附件。
# - 运行提示：普通模式先回车确认；每次下载回车执行，输入任意字符后回车跳过；Ctrl+C 取消并保留断点。
# shell: zsh

SCRIPT_SOURCE="${(%):-%x}"
SCRIPT_DIR=""
SCRIPT_PATH=""
LOG_FILE=""
DOWNLOAD_ROOT=""
FROM_PARENT=0
PARENT_BACK=0
REPOS_FROM_OPTIONS=0
LIST_ONLY=0
API_RESPONSE=""
RELEASES_JSON="[]"
ASSETS_JSON="[]"
LOCK_DIR=""
SUCCESS_COUNT=0
FAILURE_COUNT=0
SKIP_COUNT=0
USER_SKIP_COUNT=0
EMPTY_COUNT=0
FZF_PICKED=""
typeset -a REPOSITORIES=(WindowsOS_8.1 WindowsOS_10 WindowsOS_11 WindowsOS_2003 WindowsOS_XP WindowsOS_7)
typeset -a SELECTED_REPOS=()
typeset -a SELECTED_NUMBERS=()
typeset -a SELECTED_ASSETS=()
typeset -a FZF_INITIAL_NUMBERS=()

# 按终端能力渲染内置说明，日志始终保留纯文本。
intro_line() {
  local role="$1" message="$2" color="0;34"
  [[ "$role" == title ]] && color="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  else
    print -r -- "$message"
  fi
}
# 打印参数说明，不触发网络或创建下载目录。
show_help() {
  print -r -- '用法：/bin/zsh "【MacOS】⏬按需下载WindowsOS Release.command" [--list] [--repo 仓名]…'
  print -r -- '  --help                 显示帮助并退出。'
  print -r -- '  --list                 只列 Release 和完整附件清单，允许非交互运行。'
  print -r -- '  --repo WindowsOS_7      预选一个仓库，可重复指定；未指定时交互多选。'
  print -r -- '  仓名：WindowsOS_8.1、WindowsOS_10、WindowsOS_11、WindowsOS_2003、WindowsOS_XP、WindowsOS_7。'
  print -r -- '依赖：zsh、Git、curl、jq、shasum；交互选择另需支持本入口按键的 fzf，只检查不自动安装。'
  print -r -- '缺少选择器时可自行运行 brew install fzf；--list 不需要 fzf 或已初始化子仓。'
  print -r -- '公开 GitHub API 匿名访问，限流或连接失败会报错。Release 不跟随父仓 Git remote 切换。'
  print -r -- '多选：Enter 勾选 / 取消，Space 确认，Ctrl-A 全选，Ctrl-D 清空，Esc 跳过；空选不会选中当前项。'
  print -r -- 'Release 单选：Enter 确认，Esc 跳过；选择一片 ISO 会补齐该组全部分卷。'
  print -r -- '子层按 ← 返回上一选择面板；附件返回 Release，Release 返回仓库或主入口；已完成的下载保留。'
  print -r -- '下载位置：对应已初始化子仓 Releases/<Release标签>/；通过该仓 info/exclude 仅在本地忽略。'
  print -r -- '  --from-parent          内部交接参数：由已确认的主入口调用，仍要求交互终端和 --repo。'
  print -r -- '  --parent-back          内部交接参数：允许 ← 返回主入口的上一选择面板。'
  print -r -- '文件按 API 大小及可用 SHA256 校验；.partial 内保留断点，正式同名文件不符时停止该文件。'
}
# 普通运行先展示内置自述并等待回车，明确的只读参数直接继续。
show_script_intro_and_wait() {
  local argument="" readonly_request=0 answer=""
  SCRIPT_PATH="${SCRIPT_SOURCE:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  for argument in "$@"; do
    [[ "$argument" == --from-parent ]] && FROM_PARENT=1
    [[ "$argument" == --help ]] && readonly_request=2
    [[ "$argument" == --list && "$readonly_request" != 2 ]] && readonly_request=1
  done
  intro_line title '【MacOS】⏬按需下载WindowsOS Release.command'
  intro_line body '1、核心用途：选择子仓、Release 和附件；自动补齐 ISO 分卷，可断点续传。'
  intro_line body '2、下载位置：对应子仓 Releases/<标签>/；写该仓本地忽略，不修改受跟踪源码，不执行附件。'
  intro_line body '3、运行策略：公开 GitHub API 匿名访问；最终下载确认直接回车执行，输入任意字符后回车跳过。'
  intro_line body '4、子层按 ← 返回上层；Ctrl+C 取消并保留断点；日志在临时目录 WindowsOS-Release.log.XXXXXX。'
  if (( readonly_request == 2 )); then
    show_help
    exit 0
  fi
  (( readonly_request == 1 )) && return 0
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '✖ 当前没有可交互输入；请在终端运行，或用 --list 只读查看。'
    exit 1
  fi
  if (( FROM_PARENT )); then
    intro_line body '已从主入口进入 Release 阶段；接下来用 fzf 选择版本和附件，最后确认下载。'
    return 0
  fi
  read -r 'answer?已了解用途与影响，按回车继续；Ctrl+C 取消：' || exit 1
}
# 输出纯文本到终端与本次日志。
log() {
  print -r -- "$*" | tee -a "$LOG_FILE"
}
# 退出时释放本次锁；不清理下载断点。
release_lock() {
  if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
    rmdir -- "$LOCK_DIR" 2>/dev/null || true
  fi
  LOCK_DIR=""
}
# 中断时返回非零，并保留可复用的分片。
handle_interrupt() {
  log '⚠ 已取消；已完成文件与 .partial 下载断点均保留。'
  exit 130
}
# 确认后建立独立日志并启用安全 Shell 选项。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/WindowsOS-Release.log.XXXXXX")" || exit 1
  DOWNLOAD_ROOT="$SCRIPT_DIR"
  trap release_lock EXIT
  trap handle_interrupt INT TERM
  log "➤ 日志：$LOG_FILE"
  if [[ -d "$SCRIPT_DIR/ReleaseDownloads" ]]; then
    log "ℹ 旧下载目录保留原状：$SCRIPT_DIR/ReleaseDownloads；本次下载将放入对应子仓 Releases/。"
  fi
}
# 校验仓名并去重，阻止参数被拼进任意 API 路径。
add_repository() {
  local repository="$1"
  if (( ${REPOSITORIES[(Ie)$repository]} == 0 )); then
    log "✖ 不支持的仓名：$repository"
    exit 2
  fi
  (( ${SELECTED_REPOS[(Ie)$repository]} > 0 )) || SELECTED_REPOS+=("$repository")
}
# 解析只读模式和预选仓库，不接受隐式免确认开关。
parse_arguments() {
  while (( $# )); do
    case "$1" in
      --list) LIST_ONLY=1; shift ;;
      --from-parent) FROM_PARENT=1; shift ;;
      --parent-back) PARENT_BACK=1; shift ;;
      --repo)
        if (( $# < 2 )); then
          log '✖ --repo 缺少仓名。'
          exit 2
        fi
        add_repository "$2"
        REPOS_FROM_OPTIONS=1
        shift 2
        ;;
      *) log "✖ 未知参数：$1"; exit 2 ;;
    esac
  done
  if (( FROM_PARENT && ! ${#SELECTED_REPOS} )); then
    log '✖ --from-parent 必须配合主入口明确传入的 --repo。'
    exit 2
  fi
  if (( PARENT_BACK && ! FROM_PARENT )); then
    log '✖ --parent-back 仅供主入口交接使用。'
    exit 2
  fi
}
# 只验证本次确实使用的依赖，不自动安装软件。
check_environment() {
  local tool=""
  for tool in curl jq shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log "✖ 缺少依赖：$tool；缺少 jq 时可自行运行 brew install jq。"
      exit 1
    fi
  done
  if ! curl --version >/dev/null 2>&1 || ! jq -n '1' >/dev/null 2>&1 ||
     ! shasum -a 256 </dev/null >/dev/null 2>&1; then
    log '✖ curl、jq 或 shasum 不可用，请修复对应命令后重试。'
    exit 1
  fi
  if (( ! LIST_ONLY )); then
    command -v git >/dev/null && git --version >/dev/null 2>&1 || {
      log '✖ Git 不可用，无法核验对应子仓及本地忽略。'
      exit 1
    }
    check_fzf
  fi
}
# 验证选择器真实可用及所需交互能力，不降级为数字菜单。
check_fzf() {
  local version="" help=""
  if ! command -v fzf >/dev/null 2>&1 ||
     ! version="$(FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --version 2>/dev/null)"; then
    log '✖ fzf 不可用，请先运行 brew install fzf，再重新执行；没有进入选择或下载。'
    exit 1
  fi
  help="$(FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --help)" || exit 1
  [[ "$help" == *--footer* ]] || { log '✖ fzf 缺少 footer 能力，请更新 fzf。'; exit 1; }
  if ! print -r -- 'check' | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --filter=check --footer=check \
      --bind 'space:transform:if [ "$FZF_SELECT_COUNT" -gt 0 ]; then printf accept; else printf abort; fi' >/dev/null 2>&1; then
    log "✖ fzf 缺少本入口所需的按键能力：$version；请更新 fzf 后重试。"
    exit 1
  fi
}
# 以 fzf 选择稳定编号；多选为空时取消，避免隐式采用光标所在项。
choose_with_fzf() {
  local kind="$1" title="$2" rows="$3" back_title="${4:-}" result=0 hint="" record="" number="" key="" start_action="" position=0 initial_number=""
  local -a options=(--sync --layout=reverse --border --height=80% --delimiter=$'\t' --with-nth=2.. --prompt="$title > ")
  SELECTED_NUMBERS=()
  if [[ "$kind" == multi ]]; then
    hint=$'Enter 勾选/取消；Space 确认；空选不执行\nCtrl-A 全选；Ctrl-D 清空；Esc / Ctrl-C 跳过'
    options+=(--multi --bind 'enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,esc:abort,space:transform:if [ "$FZF_SELECT_COUNT" -gt 0 ]; then printf accept; else printf abort; fi')
  else
    hint='↑↓ 或输入搜索；Enter 确认；Esc / Ctrl-C 跳过此仓'
    options+=(--bind 'enter:accept,esc:abort')
  fi
  if [[ -n "$back_title" ]]; then
    hint+=$'\n'"← 返回$back_title"
    options+=(--expect=left)
  fi
  for record in "${(@f)rows}"; do
    (( position++ ))
    number="${record%%$'\t'*}"
    for initial_number in "${FZF_INITIAL_NUMBERS[@]}"; do
      if [[ "$number" == "$initial_number" ]]; then
        [[ -n "$start_action" ]] && start_action+='+'
        start_action+="pos($position)"
        [[ "$kind" == multi ]] && start_action+='+select'
        break
      fi
    done
  done
  [[ -n "$start_action" ]] && options+=(--bind="start:$start_action")
  options+=(--header="$title｜$hint" --footer="$hint")
  FZF_PICKED="$(print -r -- "$rows" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf "${options[@]}")" || result=$?
  if [[ -n "$back_title" && "${FZF_PICKED%%$'\n'*}" == left && ( "$result" == 0 || "$result" == 1 ) ]]; then
    FZF_PICKED=""
    return 10
  fi
  if (( result == 1 || result == 130 )); then
    FZF_PICKED=""
    return 0
  fi
  if (( result != 0 )); then
    log "✖ fzf 选择器失败（退出码 $result），未执行所选业务。"
    return 1
  fi
  if [[ -n "$back_title" ]]; then
    key="${FZF_PICKED%%$'\n'*}"
    [[ "$FZF_PICKED" == *$'\n'* ]] || return 0
    FZF_PICKED="${FZF_PICKED#*$'\n'}"
  fi
  [[ -n "$FZF_PICKED" ]] || return 0
  for record in "${(@f)FZF_PICKED}"; do
    number="${record%%$'\t'*}"
    [[ "$number" == <-> && ${#number} -le 8 ]] || { log '✖ 选择器返回了无效编号。'; return 1; }
    SELECTED_NUMBERS+=("$number")
  done
  return 0
}
# 无预选时选择 Windows 版本；只读清单默认显示全部仓。
select_repositories() {
  local number="" rows=""
  (( ${#SELECTED_REPOS} > 0 && ! ${1:-0} )) && return 0
  if (( LIST_ONLY )); then
    SELECTED_REPOS=("${REPOSITORIES[@]}")
    return 0
  fi
  FZF_INITIAL_NUMBERS=()
  for (( number=1; number<=${#REPOSITORIES}; number++ )); do
    rows+="$number"$'\t'"${REPOSITORIES[$number]}"$'\n'
    (( ${SELECTED_REPOS[(Ie)${REPOSITORIES[$number]}]} > 0 )) && FZF_INITIAL_NUMBERS+=("$number")
  done
  choose_with_fzf multi '选择 Windows 子仓' "${rows%$'\n'}" || exit 1
  if (( ! ${#SELECTED_NUMBERS} )); then
    log 'ℹ 未选择 Windows 子仓，已取消 Release 下载。'
    (( USER_SKIP_COUNT++ ))
  fi
  SELECTED_REPOS=()
  for number in "${SELECTED_NUMBERS[@]}"; do
    (( number >= 1 && number <= ${#REPOSITORIES} )) || { log '✖ 选择器仓库编号超出范围。'; exit 1; }
    SELECTED_REPOS+=("${REPOSITORIES[$number]}")
  done
}
# 发起公开只读 API 请求；地址固定为 GitHub，不传入或记录凭据。
fetch_api() {
  local endpoint="$1" address="https://api.github.com/$1"
  log "➤ 清单来源｜GitHub / api.github.com｜${address%%\?*}（分页参数：${endpoint#*\?}）"
  if ! API_RESPONSE="$(curl --fail --silent --show-error --location \
      --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 \
      --retry 2 -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' "$address" 2> >(tee -a "$LOG_FILE" >&2))"; then
    log "✖ 清单请求失败：${address%%\?*}；请检查网络、GitHub API 限流或仓库访问权限。"
    return 1
  fi
  if ! print -r -- "$API_RESPONSE" | jq -e 'type == "array"' >/dev/null 2>&1; then
    log "✖ 清单响应不是 JSON 数组：${address%%\?*}"
    return 1
  fi
}
# 分页取得发布版本，不把最新版本当成唯一版本。
fetch_releases() {
  local repository="$1" page=1 length=0
  RELEASES_JSON='[]'
  while (( page <= 100 )); do
    fetch_api "repos/JobsKits/$repository/releases?per_page=100&page=$page" || return 1
    if ! print -r -- "$API_RESPONSE" | jq -e 'all(.[]; (.id | type == "number" and . >= 0 and floor == .) and (.tag_name | type == "string") and (.draft | type == "boolean"))' >/dev/null; then
      log "✖ $repository 的 Release 字段不完整。"
      return 1
    fi
    length="$(print -r -- "$API_RESPONSE" | jq 'length')"
    RELEASES_JSON="$(printf '%s\n%s\n' "$RELEASES_JSON" "$API_RESPONSE" | jq -cs 'add | map(select(.draft == false))')" || return 1
    (( length < 100 )) && return 0
    (( page++ ))
  done
  log "✖ $repository 超过 100 页，已停止以避免不完整清单。"
  return 1
}
# 分页读取某一版的完整附件列表，避免内嵌 assets 数量受限。
fetch_assets() {
  local repository="$1" release_id="$2" page=1 length=0
  ASSETS_JSON='[]'
  [[ "$release_id" == <-> ]] || return 1
  while (( page <= 100 )); do
    fetch_api "repos/JobsKits/$repository/releases/$release_id/assets?per_page=100&page=$page" || return 1
    if ! print -r -- "$API_RESPONSE" | jq -e 'all(.[]; (.id | type == "number" and . >= 0 and floor == .) and (.name | type == "string") and (.size | type == "number" and . >= 0 and floor == .) and (.browser_download_url | type == "string"))' >/dev/null; then
      log "✖ $repository 的附件字段不完整。"
      return 1
    fi
    length="$(print -r -- "$API_RESPONSE" | jq 'length')"
    ASSETS_JSON="$(printf '%s\n%s\n' "$ASSETS_JSON" "$API_RESPONSE" | jq -cs 'add')" || return 1
    (( length < 100 )) && return 0
    (( page++ ))
  done
  log "✖ $repository 的附件超过 100 页，已停止。"
  return 1
}
# 清除 API 展示文字中的控制字符，避免远端标题改变终端状态。
display_text() {
  print -rn -- "$1" | tr '\000-\037\177' ' '
}
# 将字节数显示为 GiB，同时保留用于精确核对的原始字节数。
format_bytes() {
  awk -v bytes="$1" 'BEGIN { printf "%.3f GiB（%.0f 字节）", bytes / 1073741824, bytes }'
}
# 输出附件清单，并提醒极小分卷是 API 原始大小。
show_assets() {
  local count=0 number=0 asset="" name="" bytes=""
  count="$(print -r -- "$ASSETS_JSON" | jq 'length')"
  for (( number=1; number<=count; number++ )); do
    asset="$(print -r -- "$ASSETS_JSON" | jq -c ".[$((number-1))]")"
    name="$(print -r -- "$asset" | jq -r '.name')"
    bytes="$(print -r -- "$asset" | jq -r '.size')"
    log "$number、$(display_text "$name")｜$(format_bytes "$bytes")"
    if [[ "$name" == *.iso@*of* ]] && (( bytes < 1024 )); then
      log '⚠ 此分卷的 API 声明大小不足 1 KiB，将按原始大小校验；完整镜像是否可用需另外核对。'
    fi
  done
}
# 验证单个路径组成部分，拒绝目录穿越和控制字符。
validate_filename() {
  local value="$1"
  [[ -n "$value" && "$value" != . && "$value" != .. && "$value" != */* && "$value" != *\\* && "$value" != .partial && "$value" != .download-lock ]] || return 1
  [[ "$value" == *[[:cntrl:]]* ]] && return 1
  return 0
}
# 将附件选择补齐为完整 ISO 分卷组；缺片时阻止下载。
expand_split_groups() {
  local number="" asset="" name="" base="" total=0 part=0 group="" found=0 candidate=""
  local pattern='^(.*\.iso)@([0-9]+)of([0-9]+)$'
  typeset -a expanded=("${SELECTED_NUMBERS[@]}")
  for number in "${SELECTED_NUMBERS[@]}"; do
    name="$(print -r -- "$ASSETS_JSON" | jq -r ".[$((number-1))].name")"
    if [[ "$name" =~ "$pattern" ]]; then
      base="$match[1]"
      total=$(( 10#$match[3] ))
      (( total >= 1 && total <= 10000 )) || return 1
      for (( part=1; part<=total; part++ )); do
        candidate="$base@${part}of${total}"
        group="$(print -r -- "$ASSETS_JSON" | jq -c --arg name "$candidate" '[to_entries[] | select(.value.name == $name) | .key + 1]')"
        found="$(print -r -- "$group" | jq 'length')"
        if (( found != 1 )); then
          log "✖ 分卷缺失或重名：$(display_text "$candidate")；本版尚未下载。"
          return 1
        fi
        asset="$(print -r -- "$group" | jq -r '.[0]')"
        (( ${expanded[(Ie)$asset]} > 0 )) || expanded+=("$asset")
      done
      log "➤ 已补齐同组全部 $total 片：$(display_text "$base")；不会自动运行 merge.command。"
    fi
  done
  SELECTED_ASSETS=("${(@on)expanded}")
}
# 核对下载归属是真实子仓，拒绝把附件混入受跟踪目录。
validate_repository_destination() {
  local repository="$1" directory="$SCRIPT_DIR/$1" tracked=""
  if [[ -L "$directory" || ! -d "$directory" || -L "$directory/.git" || ! -e "$directory/.git" ||
        "$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null)" != "$directory" ]]; then
    log "✖ 对应子仓尚未有效初始化或路径不安全：$directory；请先从主入口同步该 Git 子仓。"
    return 1
  fi
  if [[ -L "$directory/Releases" || ( -e "$directory/Releases" && ! -d "$directory/Releases" ) ]]; then
    log "✖ 子仓 Releases 不是普通目录，保留原状：$directory/Releases"
    return 1
  fi
  tracked="$(git -C "$directory" ls-files -- Releases)" || return 1
  if [[ -n "$tracked" || -n "$(git -C "$directory" ls-tree -r --name-only HEAD -- Releases)" ]]; then
    log "✖ 子仓已跟踪 Releases 内容，拒绝把下载附件混入源码：$directory/Releases"
    return 1
  fi
}
# 只向本仓实际 Git 目录追加精确本地排除，保护已有规则和受跟踪文件。
ensure_local_download_ignore() {
  local repository="$1" directory="$SCRIPT_DIR/$1" exclude="" info_directory=""
  validate_repository_destination "$repository" || return 1
  exclude="$(git -C "$directory" rev-parse --path-format=absolute --git-path info/exclude)" || return 1
  info_directory="${exclude:h}"
  if [[ -L "$info_directory" || -L "$exclude" || ( -e "$exclude" && ! -f "$exclude" ) ]]; then
    log "✖ 子仓本地忽略路径不安全，保留原状：$exclude"
    return 1
  fi
  mkdir -p -- "$info_directory" || return 1
  if [[ ! -f "$exclude" ]] || ! grep -Fxq '/Releases/' "$exclude"; then
    printf '\n# WindowsOS Release downloads (local only)\n/Releases/\n' >> "$exclude" || return 1
    log "➤ 已添加本地忽略：$repository /Releases/（不修改子仓 .gitignore）"
  fi
  if ! git -C "$directory" check-ignore --no-index --quiet -- Releases/.windowsos-download-check; then
    log "✖ 子仓更高优先级规则取消了 Releases 忽略；请核对后重试：$directory"
    return 1
  fi
}
# 检查目录链不含符号链接，逐层建立所选子仓的下载目录。
ensure_download_directory() {
  local repository="$1" tag_directory="$2" component="" directory="$SCRIPT_DIR" repository_root="$SCRIPT_DIR/$1"
  validate_repository_destination "$repository" || return 1
  for component in "$repository" Releases "$tag_directory" .partial; do
    directory="$directory/$component"
    if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
      log "✖ 下载目录不是普通目录或是符号链接：$directory"
      return 1
    fi
    if [[ -d "$directory" && "$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null)" != "$repository_root" ]]; then
      log "✖ 下载路径进入了其它 Git 工作树，保留原状：$directory"
      return 1
    fi
    mkdir -p -- "$directory" || return 1
  done
}
# 校验文件大小和发布方提供的 SHA256；无 digest 时明确只校验大小。
verify_asset_file() {
  local filename="$1" expected_size="$2" digest="$3" actual_size="" checksum=""
  [[ -f "$filename" && ! -L "$filename" ]] || return 1
  actual_size="$(stat -f '%z' "$filename")" || return 1
  [[ "$actual_size" == "$expected_size" ]] || return 1
  if [[ "$digest" == sha256:* ]]; then
    checksum="$(shasum -a 256 "$filename")" || return 1
    [[ "${checksum%% *}" == "${digest#sha256:}" ]] || return 1
  elif [[ -n "$digest" ]]; then
    log "✖ 不支持的摘要算法：${digest%%:*}；文件保留，未发布为完成文件。"
    return 1
  fi
}
# 下载单个附件到按 asset ID 区分的断点文件，校验成功后才生成正式文件。
download_asset() {
  local repository="$1" tag="$2" directory="$3" asset="$4"
  local name="" bytes="" digest="" address="" transfer_address="" asset_id="" destination="" partial="" metadata="" identity="" actual_size=0 result=0
  name="$(print -r -- "$asset" | jq -r '.name')"
  bytes="$(print -r -- "$asset" | jq -r '.size')"
  digest="$(print -r -- "$asset" | jq -r '.digest // ""')"
  address="$(print -r -- "$asset" | jq -r '.browser_download_url')"
  asset_id="$(print -r -- "$asset" | jq -r '.id')"
  if ! validate_filename "$name" || [[ "$asset_id" != <-> || "$bytes" != <-> || "$address" != "https://github.com/JobsKits/$repository/releases/download/"* || "$address" == *\?* || "$address" == *\#* || "$address" == *[[:cntrl:]]* ]]; then
    log '✖ 附件名称、ID、大小或来源地址不安全；该附件已跳过。'
    return 1
  fi
  destination="$directory/$name"
  partial="$directory/.partial/$asset_id.part"
  metadata="$directory/.partial/$asset_id.json"
  identity="$(print -r -- "$asset" | jq -cS '{id,name,size,digest,updated_at,browser_download_url}')"
  transfer_address="https://api.github.com/repos/JobsKits/$repository/releases/assets/$asset_id"
  log '━━━━━━━━━━ 来源｜Release 附件 ━━━━━━━━━━'
  log "📦 对象：$repository / $(display_text "$tag") / $name"
  log "🌐 平台 / 主机：GitHub / github.com"
  log "📥 来源地址：$address"
  log "📡 传输地址：$transfer_address（application/octet-stream；HTTPS 重定向由 curl 跟随）"
  log "📂 目标位置：$destination"
  log "➤ 大小：$(format_bytes "$bytes")；SHA256：${digest:-API 未提供，仅核对大小}"
  if [[ -L "$destination" || -L "$partial" || -L "$metadata" || ( -e "$destination" && ! -f "$destination" ) || ( -e "$partial" && ! -f "$partial" ) || ( -e "$metadata" && ! -f "$metadata" ) ]]; then
    log '✖ 同名目标或断点不是普通文件；保留原状。'
    return 1
  fi
  if [[ -e "$destination" ]]; then
    if verify_asset_file "$destination" "$bytes" "$digest"; then
      log "✔ 已存在且验证通过，跳过：$name｜来源：$address"
      (( SKIP_COUNT++ ))
      return 0
    fi
    log "✖ 已存在同名文件但校验不符，未覆盖：$destination"
    return 1
  fi
  if [[ -e "$partial" ]]; then
    if [[ ! -f "$metadata" || "$(cat "$metadata")" != "$identity" ]]; then
      log "✖ 断点元数据缺失或远端附件已变化；保留 $partial，请移到其它位置后重试。"
      return 1
    fi
    actual_size="$(stat -f '%z' "$partial")" || return 1
    if (( actual_size > bytes )); then
      log "✖ 断点超过 API 声明大小，保留：$partial"
      return 1
    fi
  else
    print -r -- "$identity" > "$metadata" || return 1
  fi
  if (( actual_size < bytes )); then
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
      --connect-timeout 15 --speed-time 60 --speed-limit 1024 --retry 2 \
      -H 'Accept: application/octet-stream' --continue-at - --output "$partial" \
      "$transfer_address" 2> >(tee -a "$LOG_FILE" >&2)
    result=$?
    if (( result )); then
      log "✖ 下载失败（curl=$result）；断点保留：$partial｜来源：$address"
      return 1
    fi
  elif [[ ! -e "$partial" ]]; then
    : > "$partial" || return 1
  fi
  if ! verify_asset_file "$partial" "$bytes" "$digest"; then
    log "✖ 大小或摘要校验失败；断点保留：$partial｜来源：$address"
    return 1
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    log "✖ 目标在下载期间出现，保留断点并停止：$destination"
    return 1
  fi
  mv -n -- "$partial" "$destination" || return 1
  if [[ -e "$partial" ]]; then
    log "✖ 目标发生并发冲突，断点保留：$partial"
    return 1
  fi
  log "✔ 下载并校验完成：$name｜来源：$address"
  (( SUCCESS_COUNT++ ))
  return 0
}
# 展示最终计划并确认；只锁定本版下载，不锁 Git 工作树。
confirm_and_download() {
  local repository="$1" tag="$2" tag_directory="" directory="" number="" asset="" total_bytes=0 answer="" count=0 failures=0
  if (( ! ${#SELECTED_ASSETS} )); then
    log "ℹ 未选择附件，跳过：$repository / $(display_text "$tag")"
    (( USER_SKIP_COUNT++ ))
    return 0
  fi
  tag_directory="$(print -rn -- "$tag" | jq -sRr '@uri')" || return 1
  [[ "$tag_directory" == . || "$tag_directory" == .. || -z "$tag_directory" ]] && tag_directory="tag-$tag_directory"
  directory="$DOWNLOAD_ROOT/$repository/Releases/$tag_directory"
  validate_repository_destination "$repository" || return 1
  for number in "${SELECTED_ASSETS[@]}"; do
    asset="$(print -r -- "$ASSETS_JSON" | jq -c ".[$((number-1))]")"
    total_bytes=$(( total_bytes + $(print -r -- "$asset" | jq -r '.size') ))
    log "➤ 计划：$(print -r -- "$asset" | jq -r '.name' | tr '\000-\037\177' ' ')"
  done
  log "➤ 共 ${#SELECTED_ASSETS} 个附件，声明总量 $(format_bytes "$total_bytes")；完整正确文件会跳过。"
  log "➤ 下载位置：$directory"
  IFS= read -r 'answer?开始本版下载？直接回车执行；输入任意字符后回车跳过：' || exit 1
  if [[ -n "$answer" ]]; then
    log "ℹ 用户跳过本版下载：$repository / $(display_text "$tag")；没有下载附件。"
    (( USER_SKIP_COUNT++ ))
    return 0
  fi
  ensure_local_download_ignore "$repository" || return 1
  ensure_download_directory "$repository" "$tag_directory" || return 1
  LOCK_DIR="$directory/.download-lock"
  if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
    LOCK_DIR=""
    log "✖ 此版正在下载或有遗留锁：$directory/.download-lock；确认没有下载进程后可手工 rmdir 该空目录。"
    return 1
  fi
  for number in "${SELECTED_ASSETS[@]}"; do
    asset="$(print -r -- "$ASSETS_JSON" | jq -c ".[$((number-1))]")"
    if ! download_asset "$repository" "$tag" "$directory" "$asset"; then
      (( FAILURE_COUNT++ ))
      (( failures++ ))
    fi
  done
  release_lock
  (( failures == 0 ))
}
# 对某一仓库逐版展示清单，或在 Release 与附件选择层之间往返。
process_repository() {
  local repository="$1" count=0 number=0 release="" release_id="" tag="" release_number="" rows="" name="" bytes="" release_rows="" back_title="" result_code=0
  log "━━━━━━━━━━ 仓库｜JobsKits/$repository ━━━━━━━━━━"
  fetch_releases "$repository" || return 1
  count="$(print -r -- "$RELEASES_JSON" | jq 'length')"
  if (( count == 0 )); then
    log "⚠ $repository 暂无已发布 Release，可稍后重新运行此入口加载。"
    (( EMPTY_COUNT++ ))
    return 0
  fi
  for (( number=1; number<=count; number++ )); do
    release="$(print -r -- "$RELEASES_JSON" | jq -c ".[$((number-1))]")"
    name="$(display_text "$(print -r -- "$release" | jq -r '.tag_name')")｜$(display_text "$(print -r -- "$release" | jq -r '.name // ""')")"
    rows+="$number"$'\t'"$name"$'\n'
    if (( LIST_ONLY )); then
      log "$number、$name"
      release_id="$(print -r -- "$release" | jq -r '.id')"
      fetch_assets "$repository" "$release_id" || return 1
      show_assets
    fi
  done
  (( LIST_ONLY )) && return 0
  release_rows="${rows%$'\n'}"
  if (( PARENT_BACK )); then
    back_title='主入口选择'
  elif (( ! REPOS_FROM_OPTIONS )); then
    back_title='Windows 子仓'
  fi
  while true; do
    FZF_INITIAL_NUMBERS=()
    [[ -n "$release_number" ]] && FZF_INITIAL_NUMBERS=("$release_number")
    result_code=0
    choose_with_fzf single "$repository：选择 Release" "$release_rows" "$back_title" || result_code=$?
    (( result_code == 10 )) && return 10
    (( result_code == 0 )) || return 1
    if (( ! ${#SELECTED_NUMBERS} )); then
      log "ℹ 未选择 Release，跳过仓库：$repository；没有下载附件。"
      (( USER_SKIP_COUNT++ ))
      return 0
    fi
    release_number="${SELECTED_NUMBERS[1]}"
    count="$(print -r -- "$RELEASES_JSON" | jq 'length')"
    (( release_number >= 1 && release_number <= count )) || return 1
    release="$(print -r -- "$RELEASES_JSON" | jq -c ".[$((release_number-1))]")"
    release_id="$(print -r -- "$release" | jq -r '.id')"
    tag="$(print -r -- "$release" | jq -r '.tag_name')"
    fetch_assets "$repository" "$release_id" || return 1
    count="$(print -r -- "$ASSETS_JSON" | jq 'length')"
    if (( count == 0 )); then
      log '⚠ 本版没有可下载附件，可选择其它 Release，或按 ← 返回上层。'
      (( EMPTY_COUNT++ ))
      continue
    fi
    show_assets
    rows=""
    for (( number=1; number<=count; number++ )); do
      release="$(print -r -- "$ASSETS_JSON" | jq -c ".[$((number-1))]")"
      name="$(display_text "$(print -r -- "$release" | jq -r '.name')")"
      bytes="$(print -r -- "$release" | jq -r '.size')"
      rows+="$number"$'\t'"$name｜$(format_bytes "$bytes")"$'\n'
    done
    FZF_INITIAL_NUMBERS=()
    result_code=0
    choose_with_fzf multi "$repository：选择附件（分卷将补齐）" "${rows%$'\n'}" 'Release' || result_code=$?
    if (( result_code == 10 )); then
      continue
    fi
    (( result_code == 0 )) || return 1
    for number in "${SELECTED_NUMBERS[@]}"; do
      (( number >= 1 && number <= count )) || return 1
    done
    expand_split_groups || return 1
    confirm_and_download "$repository" "$tag"
    return $?
  done
}
# 逐仓处理并承接上层返回；已完成的下载保留，错误与导航信号分别传播。
process_selected_repositories() {
  local repository="" failed_repositories=0 repository_index=1 result_code=0
  while (( repository_index <= ${#SELECTED_REPOS} )); do
    repository="${SELECTED_REPOS[$repository_index]}"
    result_code=0
    process_repository "$repository" || result_code=$?
    if (( result_code == 10 )); then
      (( PARENT_BACK )) && exit 10
      select_repositories 1
      repository_index=1
      continue
    elif (( result_code != 0 )); then
      log "✖ 该仓处理失败：$repository"
      (( failed_repositories++ ))
    fi
    (( repository_index++ ))
  done
  if (( LIST_ONLY )); then
    log "➤ 清单查询结束：仓库失败 $failed_repositories；未下载附件或修改本地忽略。"
  else
    log "➤ Release 结果：实际下载 $SUCCESS_COUNT，已存在且校验通过 $SKIP_COUNT，用户跳过 $USER_SKIP_COUNT，无可下载内容 $EMPTY_COUNT，附件失败 $FAILURE_COUNT，仓库失败 $failed_repositories。"
    if (( SUCCESS_COUNT == 0 && SKIP_COUNT == 0 )); then
      log 'ℹ 本次没有取得任何 Release 附件；请查看上方跳过、空清单或失败原因。'
    else
      log '➤ 附件位置：所选子仓 Releases/<Release标签>/。'
    fi
  fi
  log "➤ 日志：$LOG_FILE"
  (( failed_repositories == 0 )) || exit 1
}
# 编排内置说明、环境检查、选择与下载。
main() {
  show_script_intro_and_wait "$@" # 先说明下载范围，并在普通运行中等待回车确认。
  initialize_runtime # 确认后创建本次临时日志并注册中断清理。
  parse_arguments "$@" # 校验只读模式和预选仓库，拒绝未知参数。
  check_environment # 确认下载工具和交互所需 fzf 真实可用。
  select_repositories # 用 fzf 选择 Windows 子仓，空选明确取消。
  process_selected_repositories # 分页列出版本和附件，按确认后的计划下载并汇总结果。
}
main "$@"
