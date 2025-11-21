#!/bin/bash
# Claude Code SessionEnd Hook - Cleanup TTS processes and temporary files
# This hook is triggered when a Claude Code session ends

# Read hook input
input=$(cat)

# Extract session information
session_id=$(echo "$input" | jq -r '.session_id')
reason=$(echo "$input" | jq -r '.reason')

# Log session end
echo "[$(date)] SessionEnd hook triggered for session $session_id (reason: $reason)" >> /tmp/kokoro-hook.log

# Kill any running kokoro-tts processes
if pkill -9 kokoro-tts 2>/dev/null; then
  echo "[$(date)] Killed running kokoro-tts processes" >> /tmp/kokoro-hook.log
fi

# Clean up TTS temporary files
rm -f /tmp/kokoro-input.txt /tmp/kokoro-pretool-input.txt 2>/dev/null

# Clean up hash tracking files for fresh start in next session
rm -f /tmp/kokoro-pretool-last-hash.txt /tmp/kokoro-pretool-last-time.txt 2>/dev/null

echo "[$(date)] Session cleanup completed for session $session_id" >> /tmp/kokoro-hook.log

# Exit successfully
exit 0
