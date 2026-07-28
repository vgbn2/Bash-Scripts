#!/bin/bash
# Wait 3 seconds for desktop manager to finish initializing
sleep 3

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/Documents/codeptit}"

# Launch GNOME Terminal with the two project tabs and one blank terminal tab
gnome-terminal \
  --class="startup-workspace" \
  --tab --title="Bio-Quant" --working-directory="$PROJECT_ROOT/hyperglycemia-faint-predictor" \
  --tab --title="Sovereign Console" --working-directory="$PROJECT_ROOT/personal_finance_draft" \
  --tab --title="Blank Terminal" &

# Give the window time to render, then minimize it
sleep 1
if command -v xdotool &> /dev/null; then
    WID=$(xdotool search --onlyvisible --class "startup-workspace" | head -1)
    if [ -n "$WID" ]; then
        xdotool windowminimize "$WID"
    fi
fi
