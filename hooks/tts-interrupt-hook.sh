#!/bin/bash
# TTS Interrupt Hook - Stops ongoing TTS playback when user submits a new prompt
# This hook is triggered when the user submits a new message to Claude

# Debug logging
echo "[$(date)] TTS Interrupt hook triggered - stopping ongoing TTS playback" >> /tmp/kokoro-hook.log

# Kill all running kokoro-tts processes and log the result
if pkill -9 kokoro-tts 2>/dev/null; then
  echo "[$(date)] Successfully stopped kokoro-tts process" >> /tmp/kokoro-hook.log
else
  echo "[$(date)] No kokoro-tts process was running" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
