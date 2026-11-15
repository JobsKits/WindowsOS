#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬按需下载WindowsOS Release.command
# - 核心用途：选择 Windows 子仓、Release 和附件，自动补齐同组 ISO 分卷后按需下载。
# - 影响范围：写对应子仓 Releases、该仓本地忽略与临时日志；多卷校验通过后调用对应子仓 MacOS 合并功能包。
# - 运行提示：普通模式先回车确认；下载失败持续重试至校验成功；Ctrl+C 取消并保留断点。
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
API_RETRY_DELAY=0
API_ERROR_DETAIL=""
RECORDED_TAG=""
RELEASES_JSON="[]"
ASSETS_JSON="[]"
LOCK_DIR=""
LOCK_FD=""
DOWNLOAD_CONFIRM_STTY=""
SUCCESS_COUNT=0
FAILURE_COUNT=0
SKIP_COUNT=0
USER_SKIP_COUNT=0
EMPTY_COUNT=0
PENDING_COUNT=0
MERGE_RUN_COUNT=0
MERGE_FAILURE_COUNT=0
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
  print -r -- '下载互斥与遗留传输核验使用 macOS 自带的 zsh/system、ps、lsof。'
  print -r -- '缺少选择器时可自行运行 brew install fzf；--list 不需要 fzf 或已初始化子仓。'
  print -r -- '公开 GitHub API 匿名读取清单，附件使用官方直链；清单明确限流时自动等到恢复，Ctrl+C 或关窗可结束。'
  jobs_prompt_output print -r -- '仓库多选：Enter 勾选 / 取消；Space 确认（多项空选时先勾选）；Ctrl-A 全选，Ctrl-D 清空，Esc 跳过。'
  jobs_prompt_output print -r -- '附件下载列表：取完整数据后显示；一项只显示该项，多项首行为全选；全选行 Enter / Space 选择全部并进入下载确认，不再用 Ctrl-A 全选。'
  jobs_prompt_output print -r -- 'Release 单选：Enter 确认；仅剩一项时 Space 同样确认；Esc 跳过；选择一片 ISO 会补齐该组全部分卷。'
  print -r -- '子层按 ← 返回上一选择面板；附件返回 Release，Release 返回仓库或主入口；已完成的下载保留。'
  print -r -- '下载位置：对应已初始化子仓 Releases/<Release标签>/；通过该仓 info/exclude 仅在本地忽略。'
  print -r -- '  --from-parent          内部交接参数：由已确认的主入口调用，仍要求交互终端和 --repo。'
  print -r -- '  --parent-back          内部交接参数：允许 ← 返回主入口的上一选择面板。'
  print -r -- '文件按 API 大小及可用 SHA256 校验；.partial 内保留断点，正式同名文件不符时停止该文件。'
  print -r -- '下载实时显示当前附件序号、curl 百分比、传输速度与预计剩余时间；续传从已有断点继续。'
  print -r -- '多卷 ISO 全部校验通过后自动进入对应子仓 MacOS/merge.command/merge.command；保留分组选择与删除确认。'
  print -r -- '合并扫描和输出均为本次 Release 目录；单文件不合并，不执行下载所得的合并脚本。'
  print -r -- '附件传输失败持续重试，不限次数或总时长；成功并校验后才继续下一片，Ctrl+C 或关窗可结束。'
  print -r -- '优先遵守服务器等待时间；普通退避 1→2→4→…→300 秒，访问拒绝或限流从 60 秒起退避。'
  print -r -- '坏摘要或不支持续传时保留首份问题断点，再从零重取；正式同名冲突、路径不安全和本地写入错误仍明确报错。'
  print -r -- '清单限流自动显示恢复时刻、剩余分秒并原页重试，无需确认；其它清单错误保留重试 / 本地计划 / 返回入口。'
  print -r -- '--list 只读查询遇限流直接返回失败，不自动等待或弹菜单。'
  print -r -- '本地历史计划来自子仓 Releases/<标签>/.partial 的附件身份记录，不代表当前线上完整清单。'
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
  intro_line body '2、下载位置：对应子仓 Releases/<标签>/；多卷校验成功后调用子仓 MacOS 合并功能包，输出留在本版目录。'
  jobs_prompt_output intro_line body '3、运行策略：附件失败持续续传至校验成功；API 限流自动等待，Ctrl+C 或关窗结束；最终回车或空格后回车执行，非空白内容则不执行。'
  intro_line body '4、子层按 ← 返回上层；Ctrl+C 取消并保留断点；日志在临时目录 WindowsOS-Release.log.XXXXXX。'
  intro_line body '5、下载显示附件序号、百分比、速度与剩余时间；自动进入合并脚本后，按其自述选择分卷组，默认保留分卷。'
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
  read -r "answer?$(jobs_prompt_render '已了解用途与影响，按回车继续；Ctrl+C 取消：')" || exit 1
}
# 输出纯文本到终端与本次日志。
log() {
  print -r -- "$*" | jobs_prompt_tee "$LOG_FILE"
}
# 下载完成提示在彩色终端显示绿色，日志及纯文本环境保留原文。
success_echo() {
  print -r -- "$*" >> "$LOG_FILE" || return 1
  if [[ -t 1 ]] && jobs_prompt_color_ready; then
    printf '\033[1;32m%s\033[0m\n' "$*"
  else
    print -r -- "$*"
  fi
}
# 释放本进程持有的系统文件锁；锁文件和下载断点均保留。
release_lock() {
  (( ZSH_SUBSHELL == 0 )) || return 0
  if [[ -n "$LOCK_FD" ]]; then
    zsystem flock -u "$LOCK_FD" 2>/dev/null || true
  fi
  LOCK_FD=""
  LOCK_DIR=""
}
# 全局退出清理避免 zsh 在初始化函数返回时提前执行 EXIT 陷阱。
TRAPEXIT() {
  local exit_code=$?
  if ! restore_download_confirmation_input; then
    (( exit_code == 0 )) && exit_code=1
  fi
  release_lock
  return "$exit_code"
}
# 防止只强杀父脚本后遗留的 curl 继续写入同一版断点。
release_has_active_transfer() {
  local directory="$1" processes="" record="" pid="" command_name="" result=0
  processes="$(ps -axo pid=,args=)" || return 2
  for record in "${(@f)processes}"; do
    [[ "$record" == *"$directory/.partial/"* ]] || continue
    IFS=$' \t' read -r pid command_name <<< "$record"
    [[ "$pid" == <-> && "$pid" != "$$" ]] || continue
    command_name="$(ps -p "$pid" -o comm= 2>/dev/null)" || continue
    if [[ "${command_name:t}" == curl ]]; then
      log "⚠ 此版仍有下载传输进程 $pid，未开始重复写入。"
      return 0
    fi
  done
  if [[ -d "$directory/.partial" ]]; then
    command -v lsof >/dev/null 2>&1 || return 2
    processes="$(lsof -w -nP -t +D "$directory/.partial" 2>/dev/null)" || result=$?
    (( result <= 1 )) || return 2
    if [[ -n "$processes" ]]; then
      log "⚠ 此版断点仍被进程使用：${(j:、:)${(f)processes}}；已保留文件。"
      return 0
    fi
  fi
  return 1
}
# 系统锁随持有进程结束自动释放，锁文件存在本身不代表正在下载。
acquire_release_lock() {
  local directory="$1" lock_file="$1/.download-lock" result=0 identity=""
  if [[ -n "$LOCK_FD" ]]; then
    log '✖ 本进程已有下载锁，未开始新的下载。'
    return 1
  fi
  if [[ -L "$lock_file" || ( -e "$lock_file" && ! -f "$lock_file" ) ]]; then
    log "✖ 下载锁不是普通文件（可能为旧版锁目录）；已保留：$lock_file"
    return 1
  fi
  if [[ -s "$lock_file" ]]; then
    log "✖ 下载锁文件包含未知内容，已保留：$lock_file"
    return 1
  fi
  if ! zmodload zsh/system 2>/dev/null || ! zsystem supports flock; then
    log '✖ 当前 zsh 不支持系统文件锁，请使用 macOS 自带的 /bin/zsh；没有开始下载。'
    return 1
  fi
  if [[ ! -e "$lock_file" ]]; then
    (setopt NO_CLOBBER; : > "$lock_file") 2>/dev/null || {
      [[ -f "$lock_file" && ! -L "$lock_file" ]] || return 1
    }
  fi
  identity="$(stat -f '%d:%i' "$lock_file")" || return 1
  zsystem flock -t 0 -f LOCK_FD "$lock_file" 2>/dev/null || result=$?
  if (( result != 0 )); then
    LOCK_FD=""
    log "✖ 此版正由另一个进程下载，或锁文件无法使用；未开始重复下载：$directory"
    return 1
  fi
  if [[ -L "$lock_file" || ! -f "$lock_file" || -s "$lock_file" || "$(stat -f '%d:%i' "$lock_file")" != "$identity" ]]; then
    release_lock
    log '✖ 下载锁在取得期间发生变化，已停止，保留现有文件。'
    return 1
  fi
  result=0
  release_has_active_transfer "$directory" || result=$?
  if (( result != 1 )); then
    release_lock
    (( result == 2 )) && log '✖ 无法核验遗留传输进程，已停止本次下载。'
    return 1
  fi
  LOCK_DIR="$lock_file"
  return 0
}
# 中断时返回非零，并保留可复用的分片。
handle_interrupt() {
  log '⚠ 已取消；已完成文件与 .partial 下载断点均保留。'
  exit 130
}
# 关闭终端窗口时显式退出，确保临时清单和本轮锁进入清理流程。
handle_hangup() {
  log '⚠ 终端窗口已关闭；已停止本轮任务，完成文件与下载断点保留。'
  exit 129
}
# 确认后建立独立日志并启用安全 Shell 选项。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/WindowsOS-Release.log.XXXXXX")" || exit 1
  DOWNLOAD_ROOT="$SCRIPT_DIR"
  trap handle_interrupt INT TERM
  trap handle_hangup HUP
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
      --bind 'space:transform:if [ "$FZF_SELECT_COUNT" -gt 0 ]; then printf accept; else printf select; fi' >/dev/null 2>&1; then
    log "✖ fzf 缺少本入口所需的按键能力：$version；请更新 fzf 后重试。"
    exit 1
  fi
}
# 选择稳定编号；下载附件列表单独提供全选操作行，其它菜单保持原有按键。
choose_with_fzf() {
  local kind="$1" title="$2" rows="$3" back_title="${4:-}" scope="${5:-general}" result=0 hint="" record="" number="" key="" start_action="" position=0 initial_number=""
  local all_available=0 all_requested=0
  local -a source_records=("${(@f)rows}")
  local -a options=(--sync --layout=reverse --border --height=80% --delimiter=$'\t' --with-nth=2.. --prompt="$title > ")
  SELECTED_NUMBERS=()
  if [[ "$kind" == multi ]]; then
    if [[ "$scope" == download ]]; then
      [[ -n "$rows" ]] || return 0
      hint=$'Enter 勾选/取消；Space 确认（唯一项直接确认，多项空选先勾选）\nCtrl-D 清空；Esc / Ctrl-C 跳过'
      options+=(--multi --bind 'ctrl-a:beginning-of-line,ctrl-d:deselect-all,esc:abort,tab:down,shift-tab:up')
      if (( ${#source_records} > 1 )); then
        all_available=1
        rows=$'__download_all__\t'"全选（全部 ${#source_records} 个附件）"$'\n'"$rows"
        hint=$'首行全选：Enter / Space 选择全部并进入下载确认\n'"$hint"
        options+=(--bind 'enter:transform:if [ {1} = __download_all__ ]; then printf "deselect-all+select+accept"; else printf toggle; fi')
        options+=(--bind 'space:transform:if [ {1} = __download_all__ ]; then printf "deselect-all+select+accept"; elif [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then printf accept; elif [ "$(grep -cv "^__download_all__$" {*f1})" -eq 1 ]; then printf "select+accept"; else printf select; fi')
      else
        options+=(--bind 'enter:toggle,space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then printf accept; elif [ "${FZF_MATCH_COUNT:-0}" -eq 1 ]; then printf "select+accept"; else printf select; fi')
      fi
    else
      hint=$'Enter 勾选/取消；Space 仅剩一项时直接确认，多项空选时先勾选，已有勾选时确认\nCtrl-A 全选；Ctrl-D 清空；Esc / Ctrl-C 跳过'
      options+=(--multi --bind 'enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,esc:abort,space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then printf accept; elif [ "${FZF_MATCH_COUNT:-0}" -eq 1 ]; then printf "select+accept"; else printf select; fi')
    fi
  else
    hint='↑↓ 或输入搜索；Enter 确认；仅剩一项时 Space 同样确认；Esc / Ctrl-C 跳过此仓'
    options+=(--bind 'enter:accept,esc:abort,space:transform:if [ "${FZF_MATCH_COUNT:-0}" -eq 1 ]; then printf accept; else printf "put( )"; fi')
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
    if (( all_available )) && [[ "$number" == __download_all__ ]]; then
      all_requested=1
      continue
    fi
    [[ "$number" == <-> && ${#number} -le 8 ]] || { log '✖ 选择器返回了无效编号。'; return 1; }
    SELECTED_NUMBERS+=("$number")
  done
  if (( all_requested )); then
    SELECTED_NUMBERS=()
    for record in "${source_records[@]}"; do
      number="${record%%$'\t'*}"
      [[ "$number" == <-> && ${#number} -le 8 ]] || { log '✖ 下载列表包含无效编号。'; return 1; }
      SELECTED_NUMBERS+=("$number")
    done
  fi
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
# 从已有下载身份记录恢复历史计划，整版验证通过后才发布附件清单。
load_recorded_assets() {
  local repository="$1" tag="$2" quiet="${3:-0}" encoded="" directory="" partial_directory="" record="" identity="" records_json="" snapshot="" prefix="" name=""
  local -a records=()
  ASSETS_JSON='[]'
  (( ${REPOSITORIES[(Ie)$repository]} > 0 )) || return 1
  [[ -n "$tag" && "$tag" != *\\* && "$tag" != *[[:cntrl:]]* ]] || return 1
  if (( quiet )); then
    validate_repository_destination "$repository" >/dev/null 2>&1 || return 1
  else
    validate_repository_destination "$repository" || return 1
  fi
  encoded="$(print -rn -- "$tag" | jq -sRr '@uri')" || return 1
  prefix="https://github.com/JobsKits/$repository/releases/download/$encoded/"
  [[ "$encoded" == . || "$encoded" == .. ]] && encoded="tag-$encoded"
  directory="$SCRIPT_DIR/$repository/Releases/$encoded"
  partial_directory="$directory/.partial"
  [[ -d "$directory" && ! -L "$directory" && -d "$partial_directory" && ! -L "$partial_directory" ]] || return 1
  [[ "$(git -C "$partial_directory" rev-parse --show-toplevel 2>/dev/null)" == "$SCRIPT_DIR/$repository" ]] || return 1
  records=("$partial_directory"/*.json(N))
  (( ${#records} > 0 && ${#records} <= 10000 )) || return 1
  for record in "${records[@]}"; do
    [[ -f "$record" && ! -L "$record" && "${record:t:r}" == <-> ]] || return 1
    identity="$(jq -ceS --arg id "${record:t:r}" --arg prefix "$prefix" '
      select(type == "object") |
      select((keys | sort) == ["browser_download_url", "digest", "id", "name", "size", "updated_at"]) |
      select((.id | type == "number" and . >= 0 and floor == . and tostring == $id) and
        (.name | type == "string" and length > 0 and
          (. != "." and . != ".." and . != ".partial" and . != ".download-lock") and
          (explode | all(.[]; . >= 32 and . != 127 and . != 47 and . != 92))) and
        (.size | type == "number" and . >= 0 and floor == .) and
        (.digest == null or .digest == "" or (.digest | type == "string" and test("^sha256:[0-9a-fA-F]{64}$"))) and
        (.updated_at | type == "string" and length > 0)) |
      select(.browser_download_url == ($prefix + (.name | @uri)))
    ' "$record" 2>/dev/null)" || return 1
    [[ "$(< "$record")" == "$identity" ]] || return 1
    records_json+="$identity"$'\n'
  done
  snapshot="$(print -rn -- "$records_json" | jq -cse '
    select((map(.id) | unique | length) == length and (map(.name) | unique | length) == length) |
    . as $assets | [.[].name | capture("^(?<base>.*\\.iso)@(?<part>[0-9]+)of(?<total>[0-9]+)$")? |
      {base, part:(.part | tonumber), total:(.total | tonumber)}] | group_by(.base) |
    select(all(.[]; . as $parts | .[0].total as $total |
      $total >= 1 and $total <= 10000 and length == $total and
      all(.[]; .total == $total and .part >= 1 and .part <= $total) and
      (map(.part) | unique | length) == $total)) |
    $assets | sort_by(.name)
  ' 2>/dev/null)" || return 1
  for name in "${(@f)$(print -r -- "$snapshot" | jq -r '.[].name')}"; do
    validate_filename "$name" || return 1
  done
  ASSETS_JSON="$snapshot"
  (( quiet )) || log "⚠ 已读取 ${#records} 个本地历史计划记录，非实时线上清单；下载时仍核验文件大小与摘要。"
  return 0
}
# 只展示校验通过的本地历史版本，返回和跳过分别传递给恢复流程。
choose_recorded_release() {
  local repository="$1" back_title="$2" directory="" encoded="" tag="" roundtrip="" rows="" result_code=0 number=0 picked=0
  local -a tags=()
  typeset -g RECORDED_TAG=''
  ASSETS_JSON='[]'
  (( ${REPOSITORIES[(Ie)$repository]} > 0 )) || return 1
  validate_repository_destination "$repository" >/dev/null 2>&1 || return 1
  for directory in "$SCRIPT_DIR/$repository/Releases"/*(N/); do
    [[ ! -L "$directory" ]] || continue
    encoded="${directory:t}"
    [[ "$encoded" != *\\* && "$encoded" != *[[:cntrl:]]* ]] || continue
    tag="$(printf '%b' "${encoded//\%/\\x}" 2>/dev/null)" || continue
    [[ -n "$tag" && "$tag" != *\\* && "$tag" != *[[:cntrl:]]* ]] || continue
    roundtrip="$(print -rn -- "$tag" | jq -sRr '@uri')" || continue
    [[ "$roundtrip" == "$encoded" ]] || continue
    load_recorded_assets "$repository" "$tag" 1 || continue
    tags+=("$tag")
    (( number++ ))
    rows+="$number"$'\t'"$(display_text "$tag")｜$(print -r -- "$ASSETS_JSON" | jq 'length') 个附件｜本地历史计划，非实时线上清单"$'\n'
  done
  ASSETS_JSON='[]'
  if (( ! ${#tags} )); then
    log 'ℹ 没有校验通过的本地历史计划，可返回后重试线上清单。'
    return 10
  fi
  FZF_INITIAL_NUMBERS=()
  choose_with_fzf single "$repository：本地历史计划，非实时线上清单" "${rows%$'\n'}" "$back_title" || result_code=$?
  (( result_code == 10 || result_code == 130 )) && return "$result_code"
  (( result_code == 0 )) || return 1
  (( ${#SELECTED_NUMBERS} )) || return 20
  picked="${SELECTED_NUMBERS[1]}"
  (( picked >= 1 && picked <= ${#tags} )) || return 1
  tag="${tags[$picked]}"
  load_recorded_assets "$repository" "$tag" || return 1
  RECORDED_TAG="$tag"
}
# 同一清单请求限流时原地等待恢复，保留分页进度；其它失败交给恢复面板。
fetch_api() {
  local endpoint="$1" address="https://api.github.com/$1" work_directory="" metrics="" result=0 http_code=0 connect_code=0 remaining="" reset="" recovery_time="" retry_after="" rate=0 fallback=60 retry_at=0
  API_RESPONSE=""
  API_RETRY_DELAY=0
  API_ERROR_DETAIL=""
  log "➤ 清单来源｜GitHub / api.github.com｜${address%%\?*}（分页参数：${endpoint#*\?}）"
  work_directory="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/WindowsOS-API.XXXXXX")" || return 1
  {
    while true; do
      result=0
      metrics=""
      API_RETRY_DELAY=0
      API_ERROR_DETAIL=""
      : > "$work_directory/headers" || return 1
      : > "$work_directory/body" || return 1
      metrics="$(curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 \
        --dump-header "$work_directory/headers" --output "$work_directory/body" \
        --write-out '%{http_code} %{http_connect}' -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' "$address" 2> >(tee -a "$LOG_FILE" >&2))" || result=$?
      (( result == 130 || result == 143 )) && return 130
      http_code="${metrics%% *}"
      connect_code="${metrics##* }"
      [[ "$http_code" == [0-9][0-9][0-9] ]] || http_code=0
      [[ "$connect_code" == [0-9][0-9][0-9] ]] || connect_code=0
      http_code=$(( 10#$http_code )); connect_code=$(( 10#$connect_code ))
      (( connect_code >= 400 )) && http_code="$connect_code"
      if (( result == 0 && http_code >= 200 && http_code < 300 )); then
        if jq -e 'type == "array"' "$work_directory/body" >/dev/null 2>&1; then
          API_RESPONSE="$(cat "$work_directory/body")"
          return 0
        fi
        API_ERROR_DETAIL='清单响应不是有效 JSON 数组'
        log "✖ $API_ERROR_DETAIL：${address%%\?*}"
        return 1
      fi
      remaining="$(download_response_header "$work_directory/headers" x-ratelimit-remaining)"
      reset="$(download_response_header "$work_directory/headers" x-ratelimit-reset)"
      retry_after="$(download_response_header "$work_directory/headers" retry-after)"
      API_ERROR_DETAIL="清单请求失败（curl=$result，HTTP=$http_code）"
      case "$result" in
        0|5|6|7|16|18|22|28|35|52|55|56|92) ;;
        *)
          log "✖ $API_ERROR_DETAIL；本地写入或证书等错误不自动等待。"
          return 1 ;;
      esac
      rate=0
      if (( http_code == 429 )) ||
         [[ "$http_code" == 403 && ( "$remaining" == 0 || -n "$retry_after" ) ]]; then
        rate=1
        API_RETRY_DELAY="$(download_retry_delay "$work_directory/headers" "$fallback")" || return 1
        (( API_RETRY_DELAY < 1 )) && API_RETRY_DELAY="$fallback"
        if [[ "$remaining" == 0 && "$reset" == <-> && ${#reset} -le 10 ]]; then
          recovery_time="$(date -r "$reset" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
          API_ERROR_DETAIL+="；API 剩余额度 0，恢复时间 $recovery_time"
        fi
      elif (( http_code == 408 || http_code >= 500 || http_code == 0 )); then
        API_RETRY_DELAY=2
      fi
      if (( rate )); then
        log "⚠ $API_ERROR_DETAIL。"
        (( LIST_ONLY )) && return 75
        retry_at=$(( $(date -u '+%s') + API_RETRY_DELAY ))
        log "➤ API 调用限流，自动等待 $((API_RETRY_DELAY / 60)) 分 $((API_RETRY_DELAY % 60)) 秒；预计于 $(date -r "$retry_at" '+%Y-%m-%d %H:%M:%S %Z') 重新请求当前页。"
        log 'ℹ 保持窗口打开即可自动继续，无需确认；Ctrl+C 或关闭窗口可结束，已完成文件与断点保留。'
        wait_download_retry "$API_RETRY_DELAY" || return 130
        fallback=$(( fallback < 150 ? fallback * 2 : 300 ))
        continue
      fi
      log "⚠ $API_ERROR_DETAIL；可等待重试、使用本地历史计划或返回上层。"
      return 75
    done
  } always {
    rm -f -- "$work_directory/headers" "$work_directory/body"
    rmdir -- "$work_directory" 2>/dev/null || true
  }
}
# 分页取得发布版本，不把最新版本当成唯一版本。
fetch_releases() {
  local repository="$1" page=1 length=0 collected='[]'
  RELEASES_JSON='[]'
  while (( page <= 100 )); do
    fetch_api "repos/JobsKits/$repository/releases?per_page=100&page=$page" || return $?
    if ! print -r -- "$API_RESPONSE" | jq -e 'all(.[]; (.id | type == "number" and . >= 0 and floor == .) and (.tag_name | type == "string") and (.draft | type == "boolean"))' >/dev/null; then
      log "✖ $repository 的 Release 字段不完整。"
      return 1
    fi
    length="$(print -r -- "$API_RESPONSE" | jq 'length')"
    collected="$(printf '%s\n%s\n' "$collected" "$API_RESPONSE" | jq -cs 'add | map(select(.draft == false))')" || return 1
    if (( length < 100 )); then
      RELEASES_JSON="$collected"
      return 0
    fi
    (( page++ ))
  done
  log "✖ $repository 超过 100 页，已停止以避免不完整清单。"
  return 1
}
# 分页读取某一版的完整附件列表，避免内嵌 assets 数量受限。
fetch_assets() {
  local repository="$1" release_id="$2" page=1 length=0 collected='[]'
  ASSETS_JSON='[]'
  [[ "$release_id" == <-> ]] || return 1
  while (( page <= 100 )); do
    fetch_api "repos/JobsKits/$repository/releases/$release_id/assets?per_page=100&page=$page" || return $?
    if ! print -r -- "$API_RESPONSE" | jq -e 'all(.[]; (.id | type == "number" and . >= 0 and floor == .) and (.name | type == "string") and (.size | type == "number" and . >= 0 and floor == .) and (.browser_download_url | type == "string"))' >/dev/null; then
      log "✖ $repository 的附件字段不完整。"
      return 1
    fi
    length="$(print -r -- "$API_RESPONSE" | jq 'length')"
    collected="$(printf '%s\n%s\n' "$collected" "$API_RESPONSE" | jq -cs 'add')" || return 1
    if (( length < 100 )); then
      ASSETS_JSON="$collected"
      return 0
    fi
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
  local number="" asset="" name="" base="" total=0 group="" reason=""
  local pattern='^(.*\.iso)@([0-9]+)of([0-9]+)$'
  typeset -a expanded=("${SELECTED_NUMBERS[@]}")
  typeset -a processed_bases=()
  SELECTED_ASSETS=()
  for number in "${SELECTED_NUMBERS[@]}"; do
    name="$(print -r -- "$ASSETS_JSON" | jq -r ".[$((number-1))].name")" || return 1
    if [[ "$name" =~ "$pattern" ]]; then
      base="$match[1]"
      (( ${processed_bases[(Ie)$base]} > 0 )) && continue
      # 编号按数字核对，文件名和附件索引仍以 API 原文为准，兼容 001 等补零命名。
      group="$(print -r -- "$ASSETS_JSON" | jq -c --arg base "$base" '
        [to_entries[] | . as $entry |
          (.value.name | capture("^(?<base>.*\\.iso)@(?<part>[0-9]+)of(?<total>[0-9]+)$")?) as $split |
          select($split.base == $base) |
          {number: ($entry.key + 1), part: ($split.part | tonumber), total: ($split.total | tonumber)}
        ] | sort_by(.part) | (.[0].total // 0) as $total |
        if $total < 1 or $total > 10000 then {error: "分卷总数无效"}
        elif any(.[]; .total != $total) then {error: "同组分卷总数不一致"}
        elif any(.[]; .part < 1 or .part > $total) then {error: "分卷编号越界"}
        elif (group_by(.part) | any(.[]; length != 1)) then {error: "分卷编号重复"}
        elif length != $total then {error: "分卷缺失"}
        else {total: $total, numbers: map(.number)} end
      ')" || return 1
      reason="$(print -r -- "$group" | jq -r '.error // ""')" || return 1
      if [[ -n "$reason" ]]; then
        log "✖ $reason：$(display_text "$base")；本版尚未下载。"
        return 1
      fi
      total="$(print -r -- "$group" | jq -r '.total')" || return 1
      while IFS= read -r asset; do
        (( ${expanded[(Ie)$asset]} > 0 )) || expanded+=("$asset")
      done <<< "$(print -r -- "$group" | jq -r '.numbers[]')"
      processed_bases+=("$base")
      log "➤ 已补齐同组全部 $total 片：$(display_text "$base")；全部下载并校验通过后，有同版合并脚本就运行。"
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
  local filename="$1" expected_size="$2" digest="$3" actual_size="" checksum="" expected_checksum=""
  [[ -f "$filename" && ! -L "$filename" ]] || return 1
  actual_size="$(stat -f '%z' "$filename")" || {
    log "✖ 无法读取文件大小，保留文件：$filename"
    return 75
  }
  [[ "$actual_size" == "$expected_size" ]] || return 1
  if [[ "$digest" == sha256:* ]]; then
    checksum="$(shasum -a 256 "$filename")" || {
      log "✖ 摘要校验命令未能完成，保留文件：$filename"
      return 75
    }
    expected_checksum="${digest#sha256:}"
    [[ "${checksum%% *}" == "${expected_checksum:l}" ]] || return 1
  elif [[ -n "$digest" ]]; then
    log "✖ 不支持的摘要算法：${digest%%:*}；文件保留，未发布为完成文件。"
    return 1
  fi
}
# 只读取最后一段 HTTP 响应的指定头，避免混用重定向或 CONNECT 的旧字段。
download_response_header() {
  LC_ALL=C awk -v key="$2" '
    /^HTTP\// {value=""}
    index(tolower($0), tolower(key) ":") == 1 {
      value=substr($0, index($0, ":") + 1); sub(/^[ \t]+/, "", value); sub(/[ \t\r]+$/, "", value)
    }
    END {print value}
  ' "$1"
}
# 优先遵守 Retry-After 和额度重置时间，没有有效服务端提示时才采用退避时间。
download_retry_delay() {
  local headers="$1" fallback="$2" retry_after="" remaining="" reset="" now="" epoch="" format="" delay=-1
  now="$(date -u '+%s')" || return 1
  retry_after="$(download_response_header "$headers" retry-after)"
  remaining="$(download_response_header "$headers" x-ratelimit-remaining)"
  reset="$(download_response_header "$headers" x-ratelimit-reset)"
  if [[ "$retry_after" == <-> && ${#retry_after} -le 10 ]]; then
    delay=$(( 10#$retry_after ))
  elif [[ -n "$retry_after" ]]; then
    for format in '%a, %d %b %Y %H:%M:%S GMT' '%A, %d-%b-%y %H:%M:%S GMT' '%a %b %e %H:%M:%S %Y'; do
      epoch="$(LC_ALL=C date -j -u -f "$format" "$retry_after" '+%s' 2>/dev/null)" || continue
      delay=$(( epoch > now ? epoch - now : 0 ))
      break
    done
  fi
  if [[ "$remaining" == 0 && "$reset" == <-> && ${#reset} -le 10 ]]; then
    epoch=$(( 10#$reset > now ? 10#$reset - now : 0 ))
    (( epoch > delay )) && delay="$epoch"
  fi
  (( delay < 0 )) && delay="$fallback"
  print -r -- "$delay"
}
# 分段等待并每分钟报告剩余时间，取消时保留已有断点。
wait_download_retry() {
  local remaining="$1" interval=0 now=0 deadline=0 next_report=0
  now="$(date -u '+%s')" || return 1
  deadline=$(( now + remaining ))
  next_report=$(( now + 60 ))
  while (( remaining > 0 )); do
    interval=$(( remaining > 30 ? 30 : remaining ))
    sleep "$interval" || return 130
    now="$(date -u '+%s')" || return 1
    remaining=$(( deadline > now ? deadline - now : 0 ))
    if (( remaining > 0 && now >= next_report )); then
      log "ℹ 等待恢复中：还需 $((remaining / 60)) 分 $((remaining % 60)) 秒；到点自动继续，Ctrl+C 可取消。"
      next_report=$(( now + 60 ))
    fi
  done
  return 0
}
# 即时转发 curl 的回车进度，终端单行刷新，日志按行追加且不混入机器可读状态。
download_progress_stream() {
  local record="" read_code=0 terminal=0
  [[ -t 2 ]] && terminal=1
  while true; do
    record=""
    IFS= read -r -d $'\r' record
    read_code=$?
    if [[ -n "$record" ]]; then
      print -r -- "$record" >> "$LOG_FILE" || return 1
      if (( terminal )); then
        printf '%s\r' "$record" >&2
      else
        print -u2 -r -- "$record"
      fi
    fi
    (( read_code == 0 )) || break
  done
  (( ! terminal )) || printf '\n' >&2
  return 0
}
# 当前附件持续传输并校验，退避封顶但不限制次数；问题断点保留一份后重取。
download_with_retry() (
  local address="$1" partial="$2" expected_bytes="$3" digest="${4:-}" headers="" metrics="" rejected_directory="" reason=""
  local http_code=0 connect_code=0 result=0 verification=0 attempt=0 actual_size=0 delay=0 rate=0 restart=0 network_backoff=1 rate_backoff=60 fallback=0
  [[ "$expected_bytes" == <-> ]] || return 1
  if [[ -n "$digest" && ! "$digest" =~ '^sha256:[0-9a-fA-F]{64}$' ]]; then
    log '✖ 附件摘要格式或算法不受支持，未开始传输。'
    return 1
  fi
  trap '[[ -z "$headers" ]] || rm -f -- "$headers"' EXIT
  trap 'exit 130' INT TERM
  trap 'exit 129' HUP
  headers="$(umask 077; mktemp "${TMPDIR:-/tmp}/WindowsOS-Release.headers.XXXXXX")" || return 75
  while true; do
    (( attempt++ ))
    if [[ -L "$partial" || ( -e "$partial" && ! -f "$partial" ) ]]; then
      log "✖ 断点路径不是普通文件，已保留：$partial"
      return 1
    fi
    actual_size=0
    [[ ! -f "$partial" ]] || actual_size="$(stat -f '%z' "$partial")" || return 75
    if (( expected_bytes == 0 )) && [[ ! -e "$partial" ]]; then
      : > "$partial" || return 75
    fi
    if (( actual_size == expected_bytes )); then
      verification=0
      verify_asset_file "$partial" "$expected_bytes" "$digest" || verification=$?
      (( verification == 0 || verification == 75 )) && return "$verification"
    fi
    log "➤ 传输尝试第 $attempt 次（持续重试）；已有断点：$(format_bytes "$actual_size") / $(format_bytes "$expected_bytes")。"
    result=0
    restart=0
    reason=""
    metrics='000 000'
    : > "$headers" || return 75
    if (( actual_size < expected_bytes )); then
      metrics="$(curl --fail --location --no-silent --show-error --progress-meter --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --speed-time 60 --speed-limit 1024 --continue-at - --output "$partial" \
        --dump-header "$headers" --write-out '%{http_code} %{http_connect}' \
        "$address" 2> >(download_progress_stream))" || result=$?
    fi
    (( result == 129 )) && return 129
    (( result == 130 || result == 143 )) && return 130
    if [[ -L "$partial" || ( -e "$partial" && ! -f "$partial" ) ]]; then
      log "✖ 传输期间断点路径发生变化，已停止：$partial"
      return 1
    fi
    [[ ! -f "$partial" ]] || actual_size="$(stat -f '%z' "$partial")" || return 75
    if (( actual_size == expected_bytes )); then
      verification=0
      verify_asset_file "$partial" "$expected_bytes" "$digest" || verification=$?
      (( verification == 0 || verification == 75 )) && return "$verification"
    fi
    case "$result" in
      1|2|3|4|23|26|27|43|48|63|77)
        log "✖ 本地写入、配置或工具错误（curl=$result），保留断点，请处理本地原因后继续：$partial"
        return 75 ;;
    esac
    http_code="${metrics%% *}"
    connect_code="${metrics##* }"
    [[ "$http_code" == [0-9][0-9][0-9] ]] || http_code=0
    [[ "$connect_code" == [0-9][0-9][0-9] ]] || connect_code=0
    http_code=$(( 10#$http_code )); connect_code=$(( 10#$connect_code ))
    (( connect_code >= 400 )) && http_code="$connect_code"
    if (( actual_size > expected_bytes )); then
      restart=1
      reason='断点大小超过声明大小'
    elif (( actual_size == expected_bytes )); then
      restart=1
      reason='完整候选的摘要校验不符'
    elif (( result == 33 || http_code == 416 )); then
      restart=1
      reason='服务器拒绝从当前断点续传'
    fi
    if (( restart )) && [[ -f "$partial" ]]; then
      if [[ -z "$rejected_directory" ]]; then
        rejected_directory="$(umask 077; mktemp -d "${partial}.rejected.XXXXXX")" || return 75
        mv -n -- "$partial" "$rejected_directory/${partial:t}" || return 75
        if [[ -e "$partial" || ! -f "$rejected_directory/${partial:t}" ]]; then
          log '✖ 问题断点未能安全保存，停止重取并保留现状。'
          return 75
        fi
        log "⚠ $reason；首份问题断点已保留：$rejected_directory/${partial:t}"
      else
        # 原断点已隔离保存，此处只重置本轮重新获取的候选，避免坏响应无限占用磁盘。
        : > "$partial" || return 75
        log "⚠ $reason；重置本轮重取候选，首份问题断点仍保留在：$rejected_directory"
      fi
    fi
    rate=0
    if (( http_code == 401 || http_code == 403 || http_code == 404 || http_code == 429 || http_code == 503 )); then
      rate=1
    fi
    if (( rate )); then
      fallback="$rate_backoff"
      rate_backoff=$(( rate_backoff < 150 ? rate_backoff * 2 : 300 ))
    else
      fallback="$network_backoff"
      network_backoff=$(( network_backoff < 150 ? network_backoff * 2 : 300 ))
    fi
    delay="$(download_retry_delay "$headers" "$fallback")" || return 1
    (( delay > 0 )) || delay="$fallback"
    log "⚠ 当前附件尚未下载并校验通过（curl=$result，HTTP=$http_code）；等待 $delay 秒后继续，第 $((attempt + 1)) 次，不设重试上限；Ctrl+C 可取消。"
    if (( http_code == 401 || http_code == 403 || http_code == 404 )); then
      log 'ℹ 远端拒绝访问或附件暂不可用；将继续等待重试，期间可能需要处理远端权限或附件状态。'
    fi
    wait_download_retry "$delay" || return 130
  done
)
# 下载单个附件到按 asset ID 区分的断点文件，校验成功后才生成正式文件。
download_asset() {
  local repository="$1" tag="$2" directory="$3" asset="$4"
  local name="" bytes="" digest="" address="" asset_id="" destination="" partial="" metadata="" identity="" result=0
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
  log '━━━━━━━━━━ 来源｜Release 附件 ━━━━━━━━━━'
  log "📦 对象：$repository / $(display_text "$tag") / $name"
  log "🌐 平台 / 主机：GitHub / github.com"
  log "📥 来源地址：$address"
  log '📡 传输方式：官方附件直链；HTTPS 重定向由 curl 跟随，不逐片调用 GitHub API。'
  log "📂 目标位置：$destination"
  log "➤ 大小：$(format_bytes "$bytes")；SHA256：${digest:-API 未提供，仅核对大小}"
  if [[ -L "$destination" || -L "$partial" || -L "$metadata" || ( -e "$destination" && ! -f "$destination" ) || ( -e "$partial" && ! -f "$partial" ) || ( -e "$metadata" && ! -f "$metadata" ) ]]; then
    log '✖ 同名目标或断点不是普通文件；保留原状。'
    return 1
  fi
  if [[ -e "$destination" ]]; then
    result=0
    verify_asset_file "$destination" "$bytes" "$digest" || result=$?
    if (( result == 0 )); then
      log "✔ 已存在且验证通过，跳过：$name｜来源：$address"
      (( SKIP_COUNT++ ))
      return 0
    fi
    (( result == 75 )) && return 75
    log "✖ 已存在同名文件但校验不符，未覆盖：$destination"
    return 1
  fi
  if [[ -e "$partial" ]]; then
    if [[ ! -f "$metadata" || "$(cat "$metadata")" != "$identity" ]]; then
      log "✖ 断点元数据缺失或远端附件已变化；保留 $partial，请移到其它位置后重试。"
      return 1
    fi
  else
    print -r -- "$identity" > "$metadata" || return 1
  fi
  download_with_retry "$address" "$partial" "$bytes" "$digest" || result=$?
  if (( result )); then
    log "✖ 下载未完成（退出码 $result）；断点保留：$partial｜来源：$address"
    return "$result"
  fi
  result=0
  verify_asset_file "$partial" "$bytes" "$digest" || result=$?
  if (( result != 0 )); then
    log "✖ 大小或摘要校验失败；断点保留：$partial｜来源：$address"
    return "$result"
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
  success_echo "✔ 下载并校验完成：$name｜来源：$address"
  (( SUCCESS_COUNT++ ))
  return 0
}
# 全部附件校验成功后调用仓库自带工具；明确扫描及输出目录，不执行下载的脚本。
run_release_merge() {
  local directory="$1" repository="$2" number="" name="" has_splits=0 result=0
  local merge_script="$DOWNLOAD_ROOT/$repository/MacOS/merge.command/merge.command"
  for number in "${SELECTED_ASSETS[@]}"; do
    name="$(print -r -- "$ASSETS_JSON" | jq -r ".[$((number-1))].name")" || return 1
    if [[ "$name" =~ '^.*\.iso@[0-9]+of([0-9]+)$' ]]; then
      if (( ${#match[1]} <= 9 && 10#${match[1]} > 1 )); then
        has_splits=1
      fi
    fi
  done
  if (( ! has_splits )); then
    log 'ℹ 本版所选附件没有需要合并的多卷 ISO；单个文件、独立 ISO 及单卷无需合并。'
    return 0
  fi
  if [[ -L "$merge_script" || ! -f "$merge_script" ]]; then
    log "✖ 缺少有效的合并入口：$merge_script；下载文件保留，请恢复本仓 MacOS/merge.command 功能包后重试。"
    return 1
  fi
  log "➤ 所选附件全部校验通过，正在进入合并脚本：$merge_script"
  log "➤ 分卷扫描与合并输出位置：$directory"
  log '➤ 按合并脚本自述选择分卷组；默认保留分卷，未选择或取消不代表已经合并。'
  (( MERGE_RUN_COUNT++ ))
  (cd -- "$directory" && /bin/zsh "$merge_script" --release-dir "$directory") || result=$?
  if (( result != 0 )); then
    log "✖ 合并脚本未正常结束（退出码 $result）；请查看上方输出，下载文件保留。"
    return "$result"
  fi
  log '✔ 合并脚本正常结束；实际合并或跳过结果以上方合并脚本输出为准。'
  return 0
}
# 仅由原确认进程恢复本轮输入模式，管道和子 Shell 不接管同一终端。
restore_download_confirmation_input() {
  (( ZSH_SUBSHELL == 0 )) || return 0
  [[ -n "$DOWNLOAD_CONFIRM_STTY" ]] || return 0
  if ! stty "$DOWNLOAD_CONFIRM_STTY" <&0; then
    log "✖ 当前终端输入模式未能恢复；请在该终端执行：stty '$DOWNLOAD_CONFIRM_STTY'"
    return 1
  fi
  DOWNLOAD_CONFIRM_STTY=""
  return 0
}
# 隔离前一选择面板排队的按键，最终下载确认只读取提示后的新输入。
prepare_download_confirmation_input() {
  local pending_key=""
  [[ -t 0 ]] || return 0
  DOWNLOAD_CONFIRM_STTY="$(stty -g <&0)" || return 1
  log '➤ 附件选择已结束，请松开按键；等待下面的下载确认提示后，回车或空格后回车开始。'
  while IFS= read -r -s -k 1 -t 0.15 pending_key; do
    if [[ "$pending_key" == $'\004' ]]; then
      log 'ℹ 输入已结束，本版未开始下载。'
      restore_download_confirmation_input || return 1
      return 1
    fi
  done
  restore_download_confirmation_input
}
# 展示最终计划并确认；本版锁保持到下载与合并脚本结束，不锁 Git 工作树。
confirm_and_download() {
  local repository="$1" tag="$2" tag_directory="" directory="" number="" asset="" total_bytes=0 answer="" count=0 failures=0 result=0 processed=0
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
  log '➤ 下载时显示当前附件序号；curl 的 % 为本次传输百分比，Speed 为字节/秒，Time Left 为预计剩余时间。'
  log '➤ 多卷 ISO 全部下载并校验通过后，运行子仓 MacOS 合并功能包，扫描并输出到本次 Release 目录；单文件不合并。'
  prepare_download_confirmation_input || exit 1
  IFS= read -r "answer?$(jobs_prompt_render '开始本版下载？回车或空格后回车执行；输入非空白内容后回车则不执行：')" || exit 1
  if [[ "$answer" == *[^[:space:]]* ]]; then
    log "ℹ 本版未启动下载：最终确认收到非空白内容，按当前规则未执行；$repository / $(display_text "$tag")。"
    (( USER_SKIP_COUNT++ ))
    (( PENDING_COUNT += ${#SELECTED_ASSETS} ))
    log "ℹ 本版已选 ${#SELECTED_ASSETS} 个附件，本轮尚未检查或尝试；已有完成文件与断点保留，不能据此认定全部下载完成。"
    return 0
  fi
  ensure_local_download_ignore "$repository" || return 1
  ensure_download_directory "$repository" "$tag_directory" || return 1
  acquire_release_lock "$directory" || return 1
  for number in "${SELECTED_ASSETS[@]}"; do
    asset="$(print -r -- "$ASSETS_JSON" | jq -c ".[$((number-1))]")"
    (( processed++ ))
    log "➤ 附件进度 [$processed/${#SELECTED_ASSETS}]：$(print -r -- "$asset" | jq -r '.name' | tr '\000-\037\177' ' ')"
    result=0
    download_asset "$repository" "$tag" "$directory" "$asset" || result=$?
    if (( result == 129 || result == 130 || result == 143 )); then
      release_lock
      return "$result"
    elif (( result != 0 )); then
      (( FAILURE_COUNT++ ))
      (( failures++ ))
      if (( result == 75 )); then
        count=$(( ${#SELECTED_ASSETS} - processed ))
        (( PENDING_COUNT += count ))
        log "⚠ 已停止本版后续请求；另有 $count 个附件尚未尝试，下次运行可继续。"
        release_lock
        return 75
      fi
    fi
  done
  if (( failures == 0 )); then
    result=0
    run_release_merge "$directory" "$repository" || result=$?
    if (( result != 0 )); then
      (( MERGE_FAILURE_COUNT++ ))
      release_lock
      (( result == 130 || result == 143 )) && return 130
      return "$result"
    fi
  else
    log '⚠ 本版有附件未通过下载或校验，未启动合并脚本；重新下载成功后再进入合并。'
  fi
  release_lock
  (( failures == 0 ))
}
# 清单失败时保留操作入口，只有明确选择重试后才等待并重新请求。
request_api_recovery() {
  local repository="$1" back_title="$2" result=0 rows=""
  (( LIST_ONLY )) && return 75
  rows=$'1\t等待恢复后重新请求（至少等待 '"$API_RETRY_DELAY"$' 秒）\n2\t使用本地已记录版本（历史计划，非实时线上清单）\n3\t跳过本仓'
  FZF_INITIAL_NUMBERS=()
  choose_with_fzf single "$repository：$API_ERROR_DETAIL" "$rows" "$back_title" || result=$?
  (( result != 0 )) && return "$result"
  case "${SELECTED_NUMBERS[1]:-}" in
    1)
      log "➤ 等待 $API_RETRY_DELAY 秒后重新请求清单；Ctrl+C 可取消。"
      wait_download_retry "$API_RETRY_DELAY" || return 130
      return 0 ;;
    2) return 21 ;;
    *) return 20 ;;
  esac
}
# 在线附件清单失败时允许重试、显式使用同版本本地记录或返回 Release。
fetch_assets_with_recovery() {
  local repository="$1" release_id="$2" tag="$3" result=0
  while true; do
    result=0
    fetch_assets "$repository" "$release_id" || result=$?
    (( result == 0 || result == 130 )) && return "$result"
    while true; do
      result=0
      request_api_recovery "$repository" 'Release' || result=$?
      if (( result == 21 )); then
        load_recorded_assets "$repository" "$tag" && return 0
        log '⚠ 当前版本没有可用的本地历史计划，请重试或返回。'
      elif (( result == 0 )); then
        break
      else
        return "$result"
      fi
    done
  done
}
# 共用在线和历史计划的附件选择、分卷补齐及最终下载确认。
select_release_assets() {
  local repository="$1" tag="$2" back_title="$3" count=0 number=0 asset="" name="" bytes="" rows="" result=0
  count="$(print -r -- "$ASSETS_JSON" | jq 'length')"
  if (( count == 0 )); then
    log '⚠ 本版没有可下载附件，可返回选择其它版本。'
    (( EMPTY_COUNT++ ))
    return 10
  fi
  show_assets
  for (( number=1; number<=count; number++ )); do
    asset="$(print -r -- "$ASSETS_JSON" | jq -c ".[$((number-1))]")"
    name="$(display_text "$(print -r -- "$asset" | jq -r '.name')")"
    bytes="$(print -r -- "$asset" | jq -r '.size')"
    rows+="$number"$'\t'"$name｜$(format_bytes "$bytes")"$'\n'
  done
  FZF_INITIAL_NUMBERS=()
  choose_with_fzf multi "$repository：选择附件（分卷将补齐）" "${rows%$'\n'}" "$back_title" download || result=$?
  (( result != 0 )) && return "$result"
  for number in "${SELECTED_NUMBERS[@]}"; do
    (( number >= 1 && number <= count )) || return 1
  done
  expand_split_groups || return 1
  confirm_and_download "$repository" "$tag"
}
# 本地历史版本单独导航，不将旧附件记录伪装成实时 Release 对象。
process_recorded_repository() {
  local repository="$1" result=0
  while true; do
    result=0
    choose_recorded_release "$repository" '清单恢复' || result=$?
    if (( result == 20 )); then
      (( USER_SKIP_COUNT++ ))
      return 0
    fi
    (( result != 0 )) && return "$result"
    result=0
    select_release_assets "$repository" "$RECORDED_TAG" '本地已记录版本' || result=$?
    (( result == 10 )) && continue
    return "$result"
  done
}
# 对某一仓库逐版展示清单，在线失败时保留重试与本地历史计划入口。
process_repository() {
  local repository="$1" count=0 number=0 release="" release_id="" tag="" release_number="" rows="" name="" bytes="" release_rows="" back_title="" result_code=0
  log "━━━━━━━━━━ 仓库｜JobsKits/$repository ━━━━━━━━━━"
  if (( PARENT_BACK )); then
    back_title='主入口选择'
  elif (( ! REPOS_FROM_OPTIONS )); then
    back_title='Windows 子仓'
  fi
  while true; do
    result_code=0
    fetch_releases "$repository" || result_code=$?
    (( result_code == 0 )) && break
    (( result_code == 130 )) && return 130
    while true; do
      result_code=0
      request_api_recovery "$repository" "$back_title" || result_code=$?
      if (( result_code == 21 )); then
        result_code=0
        process_recorded_repository "$repository" || result_code=$?
        (( result_code == 10 )) && continue
        if (( result_code == 1 )); then
          log '⚠ 本地历史计划未能载入，可在恢复面板重新选择。'
          continue
        fi
        return "$result_code"
      elif (( result_code == 20 )); then
        (( USER_SKIP_COUNT++ ))
        return 0
      elif (( result_code == 0 )); then
        break
      else
        return "$result_code"
      fi
    done
  done
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
      fetch_assets "$repository" "$release_id" || return $?
      show_assets
    fi
  done
  (( LIST_ONLY )) && return 0
  release_rows="${rows%$'\n'}"
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
    result_code=0
    fetch_assets_with_recovery "$repository" "$release_id" "$tag" || result_code=$?
    (( result_code == 10 )) && continue
    if (( result_code == 20 )); then
      (( USER_SKIP_COUNT++ ))
      return 0
    fi
    (( result_code == 0 )) || return "$result_code"
    select_release_assets "$repository" "$tag" 'Release' || result_code=$?
    (( result_code == 10 )) && continue
    return "$result_code"
  done
}
# 逐仓处理并承接上层返回；已完成的下载保留，错误与导航信号分别传播。
process_selected_repositories() {
  local repository="" failed_repositories=0 repository_index=1 result_code=0
  while (( repository_index <= ${#SELECTED_REPOS} )); do
    repository="${SELECTED_REPOS[$repository_index]}"
    result_code=0
    process_repository "$repository" || result_code=$?
    if (( result_code == 129 || result_code == 130 || result_code == 143 )); then
      exit "$result_code"
    elif (( result_code == 10 )); then
      (( PARENT_BACK )) && exit 10
      select_repositories 1
      repository_index=1
      continue
    elif (( result_code != 0 )); then
      log "✖ 该仓处理失败：$repository"
      (( failed_repositories++ ))
      if (( result_code == 75 )); then
        log "⚠ 后续请求已停止，另有 $(( ${#SELECTED_REPOS} - repository_index )) 个仓库未请求；已完成文件与断点保留。"
        break
      fi
    fi
    (( repository_index++ ))
  done
  if (( LIST_ONLY )); then
    log "➤ 清单查询结束：仓库失败 $failed_repositories；未下载附件或修改本地忽略。"
  else
    log "➤ Release 结果：实际下载 $SUCCESS_COUNT，已存在且校验通过 $SKIP_COUNT，选择或确认未执行 $USER_SKIP_COUNT，无可下载内容 $EMPTY_COUNT，附件失败 $FAILURE_COUNT，本轮未检查或尝试 $PENDING_COUNT，仓库失败 $failed_repositories。"
    log "➤ 合并入口结果：启动 $MERGE_RUN_COUNT 次，入口准备或执行失败 $MERGE_FAILURE_COUNT 次；实际合并数量以合并脚本输出为准。"
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
