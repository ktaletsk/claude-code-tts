#!/bin/bash
# Audio Ducking Helper - Lowers music app volumes while TTS plays
# Usage: audio-duck.sh [duck|restore|duck-and-wait PID]

DUCK_LEVEL="${DUCK_LEVEL:-5}"  # Duck to 5% by default (0-100 scale)
MIN_DUCK_VOLUME="${MIN_DUCK_VOLUME:-5}"  # Never go below this volume
VOLUME_FILE="/tmp/kokoro-music-volumes.txt"
LOG_FILE="/tmp/kokoro-hook.log"

log() {
    echo "[$(date)] [audio-duck] $1" >> "$LOG_FILE"
}

# Get Apple Music volume
get_music_volume() {
    osascript -e 'tell application "Music" to get sound volume' 2>/dev/null
}

# Set Apple Music volume
set_music_volume() {
    local vol="$1"
    osascript -e "tell application \"Music\" to set sound volume to $vol" 2>/dev/null
}

# Check if Apple Music is running
is_music_running() {
    pgrep -x "Music" >/dev/null 2>&1
}

duck() {
    local saved=""

    # Duck Apple Music if running
    if is_music_running; then
        local music_vol
        music_vol=$(get_music_volume)
        if [ -n "$music_vol" ] && [ "$music_vol" != "" ]; then
            saved="music:$music_vol"
            local ducked_vol=$((music_vol * DUCK_LEVEL / 100))
            # Ensure we don't go below minimum volume
            if [ "$ducked_vol" -lt "$MIN_DUCK_VOLUME" ]; then
                ducked_vol="$MIN_DUCK_VOLUME"
            fi
            set_music_volume "$ducked_vol"
            log "Ducked Apple Music from $music_vol to $ducked_vol"
        fi
    else
        log "Apple Music not running, skipping"
    fi

    # Save original volumes
    if [ -n "$saved" ]; then
        echo "$saved" > "$VOLUME_FILE"
        log "Saved volumes: $saved"
    else
        log "No music apps to duck"
    fi
}

restore() {
    if [ ! -f "$VOLUME_FILE" ]; then
        log "No saved volumes to restore"
        return 0
    fi

    local saved
    saved=$(cat "$VOLUME_FILE")

    # Parse and restore each app's volume
    IFS=',' read -ra APPS <<< "$saved"
    for app_vol in "${APPS[@]}"; do
        local app="${app_vol%%:*}"
        local vol="${app_vol##*:}"

        case "$app" in
            music)
                if is_music_running; then
                    set_music_volume "$vol"
                    log "Restored Apple Music to $vol"
                fi
                ;;
        esac
    done

    rm -f "$VOLUME_FILE"
}

# Duck and wait for a process to finish, then restore
duck_and_wait() {
    local pid="$1"

    if [ -z "$pid" ]; then
        log "No PID provided for duck-and-wait"
        return 1
    fi

    duck

    # Wait for the process to finish
    log "Waiting for PID $pid to finish..."
    while kill -0 "$pid" 2>/dev/null; do
        sleep 0.5
    done

    log "PID $pid finished, restoring volume"
    restore
}

case "$1" in
    duck)
        duck
        ;;
    restore)
        restore
        ;;
    duck-and-wait)
        duck_and_wait "$2"
        ;;
    *)
        echo "Usage: $0 [duck|restore|duck-and-wait PID]"
        exit 1
        ;;
esac
