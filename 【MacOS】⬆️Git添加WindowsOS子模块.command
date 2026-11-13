#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⬆️Git添加WindowsOS子模块.command
# - 核心用途：增量关联六个 Windows 子仓，登记 .gitmodules 与真实 gitlink。
# - 影响范围：仅新增子仓的工作区、父仓 .gitmodules / gitlink 索引及本地登记；不提交、不推送。
# - 运行提示：先读自述并按回车确认；添加前再次确认，回车跳过；--dry-run 只检查不写入。
# shell: zsh

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

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
  read -r "answer?$(jobs_prompt_render '已了解用途与影响，按回车继续；Ctrl+C 取消：')" || exit 1
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
    print -r -- "$*" | sanitize_stream | jobs_prompt_tee "$LOG_FILE"
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
  read -r "answer?$(jobs_prompt_render '输入任意字符后回车登记所列新增项；直接回车跳过：')" || exit 1
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
