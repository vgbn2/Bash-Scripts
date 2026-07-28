# Interactive, scoped command prompts such as `system ai`.

clear_prompt_screen() {
    printf '\033[H\033[2J'
}

show_section_help() {
    local section=$1

    case "$section" in
        ai)
            delegate_tool "ai/ai" help
            ;;
        gaming|games)
            delegate_tool "gaming/gaming" help
            ;;
        network)
            cat <<'HELP'
network commands:
  status
  processes
  connections
  limit-download <percent> <max-mbps>
  limit-upload <percent> <max-mbps>
  clear-download
  clear-upload
  install-tools --yes
HELP
            ;;
        input)
            cat <<'HELP'
input commands:
  status
  settings
  mouse-speed [value from -1.0 to 1.0]
  backlight [level]
  rgb status
  rgb set <device> <static|breathing|rainbow|spectrum|wave> <RRGGBB> --yes
  install-tools --yes
  install-rgb --yes
HELP
            ;;
        controllers)
            cat <<'HELP'
controller commands:
  status
  test <jsN>
  install-tools --yes
HELP
            ;;
        display)
            cat <<'HELP'
display commands:
  status
  brightness [1-100]
  external
  contrast [1-100] [display-number]
  color status
  color warm <1700-4700>
  color normal
  color preset <6500|7500|9300|user1> [display-number]
  install-tools --yes
HELP
            ;;
        firmware)
            cat <<'HELP'
firmware commands:
  status
  updates
  history
  refresh --yes
  update --yes
  install-tools --yes
HELP
            ;;
        cooling)
            cat <<'HELP'
cooling commands:
  status
  profile [low-power|balanced|performance|max-power|custom]
  install-tools --yes

This laptop exposes firmware cooling profiles, not manual fan RPM/PWM.
HELP
            ;;
        ssh)
            cat <<'HELP'
ssh commands:
  status
  keys
  install-client --yes
HELP
            ;;
        *)
            echo "No interactive help is defined for: $section" >&2
            return 2
            ;;
    esac
}

invalid_section_action() {
    local section=$1
    local command_name=${2:-}

    printf 'Unknown %s command: %s\n\n' "$section" "${command_name:-empty}" >&2
    show_section_help "$section" >&2
    return 2
}

run_section_command() {
    local section=$1
    shift

    case "$section" in
        ai) delegate_tool "ai/ai" "$@" ;;
        gaming|games) delegate_tool "gaming/gaming" "$@" ;;
        *) "$SYSTEM_ENTRY" "$section" "$@" ;;
    esac
}

show_prompt_controls() {
    cat <<'HELP'
Prompt controls: help/menu, repeat, clear, back, exit, or quit.
HELP
}

enter_command_center() {
    local line
    local result
    local -a words
    local -a last_words=()

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        show_command_center
        return
    fi

    printf 'Interactive system command center. Type help, clear, or quit.\n\n'
    show_command_center
    echo

    while true; do
        if ! IFS= read -r -e -p 'system> ' line; then
            echo
            break
        fi

        read -r -a words <<<"$line"
        [ "${#words[@]}" -gt 0 ] || continue

        case "${words[0]}" in
            back|exit|quit)
                break
                ;;
            help|\?|menu|commands)
                show_help
                ;;
            clear|cls)
                clear_prompt_screen
                show_command_center
                ;;
            repeat)
                if [ "${#last_words[@]}" -eq 0 ]; then
                    echo "Nothing to repeat yet. Run a system command first." >&2
                    continue
                fi
                printf 'Repeating:'
                printf ' %q' "${last_words[@]}"
                echo
                "$SYSTEM_ENTRY" "${last_words[@]}"
                result=$?
                ;;
            *)
                last_words=("${words[@]}")
                "$SYSTEM_ENTRY" "${words[@]}"
                result=$?
                if [ "$result" -ne 0 ] && [ "$result" -ne 2 ]; then
                    printf 'Command exited with status %s. Type help for guidance.\n' \
                        "$result" >&2
                fi
                ;;
        esac
    done
}

enter_section() {
    local section=$1
    local line
    local result
    local -a words
    local -a last_words=()

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        show_section_help "$section"
        return
    fi

    printf 'Entered %s mode. Type help, menu, repeat, clear, or back.\n\n' "$section"
    show_section_help "$section"
    show_prompt_controls
    echo

    while true; do
        if ! IFS= read -r -e -p "system $section> " line; then
            echo
            break
        fi

        read -r -a words <<<"$line"
        [ "${#words[@]}" -gt 0 ] || continue

        case "${words[0]}" in
            back|exit|quit)
                break
                ;;
            help|\?|menu|commands)
                show_section_help "$section"
                ;;
            clear|cls)
                clear_prompt_screen
                show_section_help "$section"
                show_prompt_controls
                ;;
            repeat)
                if [ "${#last_words[@]}" -eq 0 ]; then
                    echo "Nothing to repeat yet. Run a section command first." >&2
                    continue
                fi
                printf 'Repeating:'
                printf ' %q' "${last_words[@]}"
                echo
                run_section_command "$section" "${last_words[@]}"
                result=$?
                ;;
            *)
                last_words=("${words[@]}")
                run_section_command "$section" "${words[@]}"
                result=$?
                if [ "$result" -ne 0 ] && [ "$result" -ne 2 ]; then
                    printf 'Command exited with status %s. Type help for guidance.\n' \
                        "$result" >&2
                fi
                ;;
        esac
    done
}
