# Command routing. This file runs after all feature files are loaded.

show_full_status() {
    show_cpu_status
    show_ram_status
    show_battery_status
    show_gpu_status
    show_ssd_health
    show_network_status
}

delegate_tool() {
    local relative_path=$1
    shift
    local tool="$TOOL_ROOT/$relative_path"

    if [ ! -x "$tool" ]; then
        echo "Tool is unavailable: $tool" >&2
        return 127
    fi

    "$tool" "$@"
}

run_cpu() {
    if [ -z "$action" ] || [ "$action" = "help" ]; then
        delegate_tool "hardware/cpu" --help
    elif [[ "$action" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        delegate_tool "hardware/cpu" "$action"
    else
        delegate_tool "hardware/cpu" "$action" "${3:-}"
    fi
}

run_health() {
    if [ -z "$action" ]; then
        delegate_tool "maintenance/system-health" summary
    else
        delegate_tool "maintenance/system-health" "$action"
    fi
}

run_repair() {
    if [ -z "$action" ]; then
        delegate_tool "maintenance/system-repair" help
    else
        delegate_tool "maintenance/system-repair" "$action"
    fi
}

run_desktop() {
    case "$action" in
        terminals)
            delegate_tool "desktop/open-project-terminals.sh"
            ;;
        *)
            echo "Usage: system desktop terminals" >&2
            return 2
            ;;
    esac
}

area=${1:-}
action=${2:-}

case "$area" in
    "")
        show_command_center
        ;;
    menu|interactive)
        enter_command_center
        ;;
    help|-h|--help)
        show_help
        ;;
    status)
        show_full_status
        ;;
    monitor)
        run_monitor "${2:-all}" "${3:-2}"
        ;;
    cpu)
        run_cpu
        ;;
    health)
        run_health
        ;;
    repair)
        run_repair
        ;;
    ai)
        if [ -z "$action" ]; then
            enter_section ai
        else
            delegate_tool "ai/ai" "$action" "${3:-}"
        fi
        ;;
    gaming)
        if [ -z "$action" ]; then
            enter_section gaming
        else
            delegate_tool "gaming/gaming" "$action" "${3:-}"
        fi
        ;;
    games)
        if [ -z "$action" ]; then
            enter_section games
        else
            delegate_tool "gaming/gaming" "$action" "${3:-}"
        fi
        ;;
    ram)
        [ "$action" = "status" ] && show_ram_status || show_help
        ;;
    battery)
        [ "$action" = "status" ] && show_battery_status || show_help
        ;;
    gpu)
        [ "$action" = "status" ] && show_gpu_status || show_help
        ;;
    thermals)
        [ "$action" = "status" ] && show_thermals || show_help
        ;;
    memory)
        [ "$action" = "hardware" ] && show_memory_hardware || show_help
        ;;
    ssd)
        [ "$action" = "health" ] && show_ssd_health || show_help
        ;;
    storage)
        case "$action" in
            sections) show_storage_sections ;;
            home) show_home_storage ;;
            *) show_help ;;
        esac
        ;;
    internet)
        [ "$action" = "test" ] && test_internet || show_help
        ;;
    display)
        if [ -z "$action" ]; then
            enter_section display
        else case "$action" in
            help|-h|--help) show_section_help display ;;
            status) show_display_status ;;
            brightness)
                if [ -z "${3:-}" ]; then
                    show_display_brightness
                else
                    set_display_brightness "${3:-}"
                fi
                ;;
            external) show_external_displays ;;
            contrast)
                if [ -z "${3:-}" ]; then
                    show_external_contrast "${4:-1}"
                else
                    set_external_contrast "${3:-}" "${4:-1}"
                fi
                ;;
            color) run_display_color "${3:-status}" "${4:-}" "${5:-1}" ;;
            install-tools) install_display_tools "${3:-}" ;;
            *) invalid_section_action display "$action" ;;
        esac
        fi
        ;;
    input)
        if [ -z "$action" ]; then
            enter_section input
        else case "$action" in
            help|-h|--help) show_section_help input ;;
            status) show_input_status ;;
            settings) show_input_settings ;;
            mouse-speed)
                if [ -z "${3:-}" ]; then
                    show_mouse_speed
                else
                    set_mouse_speed "${3:-}"
                fi
                ;;
            backlight)
                if [ -z "${3:-}" ]; then
                    show_keyboard_backlight
                else
                    set_keyboard_backlight "${3:-}"
                fi
                ;;
            rgb)
                case "${3:-status}" in
                    status) show_keyboard_rgb ;;
                    set)
                        set_keyboard_rgb "${4:-}" "${5:-}" "${6:-}" "${7:-}"
                        ;;
                    *) invalid_section_action input "rgb ${3:-}" ;;
                esac
                ;;
            install-tools) install_input_tools "${3:-}" ;;
            install-rgb) install_rgb_tools "${3:-}" ;;
            *) invalid_section_action input "$action" ;;
        esac
        fi
        ;;
    controllers)
        if [ -z "$action" ]; then
            enter_section controllers
        else case "$action" in
            help|-h|--help) show_section_help controllers ;;
            status) show_controller_status ;;
            test) test_controller "${3:-}" ;;
            install-tools) install_controller_tools "${3:-}" ;;
            *) invalid_section_action controllers "$action" ;;
        esac
        fi
        ;;
    firmware)
        if [ -z "$action" ]; then
            enter_section firmware
        else case "$action" in
            help|-h|--help) show_section_help firmware ;;
            status) show_firmware_status ;;
            updates) show_firmware_updates ;;
            history) show_firmware_history ;;
            refresh) refresh_firmware_metadata "${3:-}" ;;
            update) update_firmware "${3:-}" ;;
            install-tools) install_firmware_tools "${3:-}" ;;
            *) invalid_section_action firmware "$action" ;;
        esac
        fi
        ;;
    cooling)
        if [ -z "$action" ]; then
            enter_section cooling
        else case "$action" in
            help|-h|--help) show_section_help cooling ;;
            status) show_cooling_status ;;
            profile)
                if [ -z "${3:-}" ]; then
                    show_cooling_status
                else
                    set_cooling_profile "${3:-}"
                fi
                ;;
            install-tools) install_cooling_tools "${3:-}" ;;
            *) invalid_section_action cooling "$action" ;;
        esac
        fi
        ;;
    wifi)
        [ "$action" = "status" ] && show_wifi_status || show_help
        ;;
    hardware)
        [ "$action" = "summary" ] && show_hardware_summary || show_help
        ;;
    devices)
        [ -z "$action" ] && show_devices || show_help
        ;;
    errors)
        case "$action" in
            ""|summary) show_kernel_error_summary ;;
            oom) show_oom_errors ;;
            gpu) show_gpu_errors ;;
            storage) show_storage_errors ;;
            network) show_network_errors ;;
            full) show_full_kernel_errors ;;
            *) show_help ;;
        esac
        ;;
    network)
        if [ -z "$action" ]; then
            enter_section network
        else case "$action" in
            help|-h|--help) show_section_help network ;;
            status) show_network_status ;;
            processes) show_network_processes ;;
            connections) show_network_connections ;;
            install-tools) install_network_tools "${3:-}" ;;
            limit-download) limit_download "${3:-}" "${4:-}" ;;
            limit-upload|limit-send) limit_upload "${3:-}" "${4:-}" ;;
            clear-download) clear_download_limit ;;
            clear-upload|clear-send) clear_upload_limit ;;
            *) invalid_section_action network "$action" ;;
        esac
        fi
        ;;
    ssh)
        if [ -z "$action" ]; then
            enter_section ssh
        else case "$action" in
            help|-h|--help) show_section_help ssh ;;
            status) show_ssh_status ;;
            keys) show_ssh_keys ;;
            install-client) install_ssh_client "${3:-}" ;;
            *) invalid_section_action ssh "$action" ;;
        esac
        fi
        ;;
    desktop)
        run_desktop
        ;;
    *)
        printf 'Unknown system section: %s\n\n' "$area" >&2
        show_command_center >&2
        exit 2
        ;;
esac
