#!/bin/bash
# TTS Interrupt Hook - Stops ongoing TTS playback when user submits a new prompt
# This hook is triggered when the user submits a new message to Claude

# Audio ducking configuration - restores music volume when TTS is interrupted
AUDIO_DUCK_SCRIPT="__CLAUDE_TTS_PROJECT_DIR__/scripts/audio-duck.sh"

# Debug logging
echo "[$(date)] TTS Interrupt hook triggered - stopping ongoing TTS playback" >> /tmp/kokoro-hook.log

# Stop what is speaking AND drop anything queued behind it, so a new prompt
# does not get answered by stale audio that was still waiting for the lock.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if "$HOOK_DIR/tts-cancel.sh"; then
  # Restore audio volume since TTS was interrupted mid-playback.
  if [ -x "$AUDIO_DUCK_SCRIPT" ]; then
    echo "[$(date)] Restoring audio after interrupt" >> /tmp/kokoro-hook.log
    "$AUDIO_DUCK_SCRIPT" restore
  fi
fi

# Exit successfully (non-blocking)
exit 0
