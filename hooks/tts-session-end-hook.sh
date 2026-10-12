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

# Deliberately does NOT cancel TTS or delete queued utterances. This hook fires
# on leaving a session, not only on closing one, so doing either here cut off
# or silently lost speech whenever you switched sessions. Each queued text file
# is removed by tts-play.sh once it is played, cancelled, or times out.
#
# UserPromptSubmit still cancels, so a hung kokoro-tts is still cleared by the
# next prompt.

# Legacy fixed-name files from older versions of these hooks.
rm -f /tmp/kokoro-input.txt /tmp/kokoro-pretool-input.txt 2>/dev/null

# Orphans from players that died without cleaning up. An hour is far longer
# than the player's maximum wait, so this can never race a queued utterance.
find /tmp -maxdepth 1 \( -name 'kokoro-input.*' -o -name 'kokoro-pretool-input.*' \) -mmin +60 -delete 2>/dev/null

# Clean up hash tracking files for fresh start in next session
rm -f /tmp/kokoro-pretool-last-hash.txt /tmp/kokoro-pretool-last-time.txt 2>/dev/null

echo "[$(date)] Session cleanup completed for session $session_id" >> /tmp/kokoro-hook.log

# Exit successfully
exit 0
