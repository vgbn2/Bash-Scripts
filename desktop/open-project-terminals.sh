#!/bin/bash
# Startup script for workspace terminals with split tmux sessions
# Weekend-only startup restriction disabled
# DOW=$(TZ="Asia/Ho_Chi_Minh" date +%u)
# if [[ "${1:-}" != "--force" && "${FORCE_STARTUP:-0}" != "1" ]]; then
#     if [[ "$DOW" -ne 6 && "$DOW" -ne 7 ]]; then
#         echo "open-project-terminals: Today is $(TZ='Asia/Ho_Chi_Minh' date +'%A') (UTC+7). Configured for weekend startup only (Saturday/Sunday). Exiting."
#         exit 0
#     fi
# fi

# Wait 3 seconds for desktop manager to finish initializing
sleep 3

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/Documents/codeptit}"

# 1. Setup/Ensure 'diabetic-studying' tmux session (Diabetic | Studying split in half)
if ! tmux has-session -t diabetic-studying 2>/dev/null; then
    tmux new-session -d -s diabetic-studying -n "workspace" -c "$PROJECT_ROOT/diabetic"
    tmux split-window -h -t diabetic-studying:0 -c "$PROJECT_ROOT/Studying"
    tmux select-pane -t diabetic-studying:0.0
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

# 4. Setup/Ensure 'ktlt-ktvxl' tmux session (KTLT | BTL_KTVXL split in half)
if ! tmux has-session -t ktlt-ktvxl 2>/dev/null; then
    tmux new-session -d -s ktlt-ktvxl -n "ktlt-ktvxl" -c "$PROJECT_ROOT/KTLT"
    tmux split-window -h -t ktlt-ktvxl:0 -c "$PROJECT_ROOT/stm32-esp32/BTL_KTVXL"
    tmux select-pane -t ktlt-ktvxl:0.0
fi

# 5. Setup/Ensure 'local' tmux session (Blank local terminal)
if ! tmux has-session -t local 2>/dev/null; then
    tmux new-session -d -s local -c "$HOME"
fi

# Launch GNOME Terminal with tabs:
# Tab 1: Diabetic & Studying (split in half)
# Tab 2: SV & Tools (split in half)
# Tab 3: HP Desk & Dell OptiPlex Proxmox cluster (split in half)
# Tab 4: KTLT & BTL_KTVXL (split in half)
# Tab 5: Blank Local
gnome-terminal \
  --class="startup-workspace" \
  --tab --title="Diabetic | Studying" --command="bash -c 'tmux attach-session -t diabetic-studying; exec bash'" \
  --tab --title="SV | Tools" --command="bash -c 'tmux attach-session -t sv-tools; exec bash'" \
  --tab --title="HPDesk | DellOptiPlex" --command="bash -c 'tmux attach-session -t cluster; exec bash'" \
  --tab --title="KTLT | KTVXL" --command="bash -c 'tmux attach-session -t ktlt-ktvxl; exec bash'" \
  --tab --title="Local" --command="bash -c 'tmux attach-session -t local; exec bash'" &

# Minimize window on login
sleep 1
if command -v xdotool &> /dev/null; then
    WID=$(xdotool search --onlyvisible --class "startup-workspace" | head -1)
    if [ -n "$WID" ]; then
        xdotool windowminimize "$WID"
    fi
fi
