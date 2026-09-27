#!/bin/bash
# Startup script for workspace terminals with split tmux sessions
# ponytail: weekend-only gate (Saturday=6, Sunday=7 in UTC+7). Bypass with --force or FORCE_STARTUP=1
DOW=$(TZ="Asia/Ho_Chi_Minh" date +%u)
if [[ "${1:-}" != "--force" && "${FORCE_STARTUP:-0}" != "1" ]]; then
    if [[ "$DOW" -ne 6 && "$DOW" -ne 7 ]]; then
        echo "open-project-terminals: Today is $(TZ='Asia/Ho_Chi_Minh' date +'%A') (UTC+7). Configured for weekend startup only (Saturday/Sunday). Exiting."
        exit 0
    fi
fi

# Wait 3 seconds for desktop manager to finish initializing
sleep 3

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/Documents/codeptit}"

# 1. Setup/Ensure 'games-diabetic' tmux session (Diabetic | Games split in half)
if ! tmux has-session -t games-diabetic 2>/dev/null; then
    tmux new-session -d -s games-diabetic -n "workspace" -c "$PROJECT_ROOT/diabetic"
    tmux split-window -h -t games-diabetic:0 -c "$PROJECT_ROOT/Games"
    tmux select-pane -t games-diabetic:0.0
fi

# 2. Setup/Ensure 'sv-tools' tmux session (Sovereign Console | Tools split in half)
if ! tmux has-session -t sv-tools 2>/dev/null; then
    tmux new-session -d -s sv-tools -n "sv-tools" -c "$PROJECT_ROOT/personal_finance_draft"
    tmux split-window -h -t sv-tools:0 -c "$PROJECT_ROOT/tools"
    tmux select-pane -t sv-tools:0.0
fi

# 3. Setup/Ensure 'cluster' tmux session (HP Desk Proxmox | Dell OptiPlex Proxmox split in half)
if ! tmux has-session -t cluster 2>/dev/null; then
    tmux new-session -d -s cluster -n "cluster" "ssh -t hpdesk 'tmux new-session -A -s main || bash'"
    tmux split-window -h -t cluster:0 "ssh -t delloptiplex 'tmux new-session -A -s main || bash'"
    tmux select-pane -t cluster:0.0
fi

# 4. Setup/Ensure 'local' tmux session (Blank local terminal)
if ! tmux has-session -t local 2>/dev/null; then
    tmux new-session -d -s local -c "$HOME"
fi

# Launch GNOME Terminal with tabs:
# Tab 1: Diabetic & Games (split in half)
# Tab 2: SV & Tools (split in half)
# Tab 3: HP Desk & Dell OptiPlex Proxmox cluster (split in half)
# Tab 4: Blank Local
gnome-terminal \
  --class="startup-workspace" \
  --tab --title="Diabetic | Games" --command="bash -c 'tmux attach-session -t games-diabetic; exec bash'" \
  --tab --title="SV | Tools" --command="bash -c 'tmux attach-session -t sv-tools; exec bash'" \
  --tab --title="HPDesk | DellOptiPlex" --command="bash -c 'tmux attach-session -t cluster; exec bash'" \
  --tab --title="Local" --command="bash -c 'tmux attach-session -t local; exec bash'" &

# Minimize window on login
sleep 1
if command -v xdotool &> /dev/null; then
    WID=$(xdotool search --onlyvisible --class "startup-workspace" | head -1)
    if [ -n "$WID" ]; then
        xdotool windowminimize "$WID"
    fi
fi
