# Shared help text and small helpers.

show_help() {
    cat <<'HELP'
Usage: system <area> <command> [arguments]

COMMAND CENTER
  system                         Show the short command-center overview.
  system menu                    Enter the interactive command center.
  system status                  Hardware, storage, battery, GPU, and network.
  system monitor [section] [seconds]  Live foreground hardware monitor.
  system health [summary|run|latest]
  system repair [suggest|thermal|gpu|desktop]

WORKLOADS
  system ai                      Enter the interactive AI section.
  system games                   Enter the interactive game-library section.
  system gaming                  Compatibility alias for game/GPU tools.
  system ai <command>            Run one AI command directly.
  system games [steam|non-steam|launchers|all|compatibility|diagnose]

HARDWARE
  system cpu [status|cool|balanced|game|full|<GHz>]
  system ram status | battery status | gpu status | thermals status
  system ssd health | ssd raw /dev/nvmeNnM
  system storage [sections|home] | memory hardware
  system input [help|status|settings|mouse-speed [<-1.0..1.0>]]
  system input [backlight [level]|rgb status|install-tools --yes]
  system input rgb set <device> <pattern> <RRGGBB> --yes
  system input install-rgb --yes
  system controllers [help|status|test <jsN>|install-tools --yes]
  system display [help|status|brightness [1-100]|external]
  system display contrast [1-100] [display-number]
  system display color [status|warm|normal|preset]
  system display install-tools --yes
  system firmware [help|status|updates|history]
  system firmware [refresh --yes|update --yes|install-tools --yes]
  system cooling [help|status|profile [name]|install-tools --yes]
  system hardware summary | devices

NETWORK AND SSH
  system network [help|status|processes|connections]
  system network limit-download <percent> <max-mbps>
  system network limit-upload <percent> <max-mbps>
  system network clear-download | clear-upload | install-tools --yes
  system internet test | wifi status
  system ssh [help|status|keys|install-client --yes]

MAINTENANCE AND DESKTOP
  system errors [summary|oom|gpu|storage|network|full]
  system desktop terminals        Open the project-terminal workspace.

Existing commands (ai, gaming, cpu, system-health, system-repair) remain
available, but system is the preferred command root.

Typing only `system <section>` opens a scoped prompt. Use `back` to leave it.
HELP
}

show_command_center() {
    cat <<'MENU'
=== System command center ===

  system status                  Overall hardware and network status
  system health summary          Latest saved health-report summary
  system repair suggest          Safe repair recommendations

  system ai help                 Local-model tools
  system games                   Steam, non-Steam, launchers, and compatibility
  system input status            Keyboard, mouse, and touchpad
  system controllers status      Gamepads and joystick devices
  system display status          Monitors and brightness
  system firmware status         BIOS and fwupd-managed devices
  system cooling status          Temperatures and firmware fan profiles
  system network processes       Live bandwidth by process
  system ssh status              SSH client/server and port status

  system help                    Full command reference
MENU
}

print_section() {
    printf '\n=== %s ===\n' "$1"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}
