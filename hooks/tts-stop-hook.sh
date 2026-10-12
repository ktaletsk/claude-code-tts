#!/bin/bash
# Claude Code TTS Hook - Reads Claude's responses using kokoro-tts

# Voice configuration - can be set via KOKORO_VOICE env var in ~/.claude/settings.json
VOICE="${KOKORO_VOICE:-af_sky}"

# Playback (serialization + audio ducking) lives in the shared player script.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Debug logging
echo "[$(date)] Kokoro TTS hook triggered" >> /tmp/kokoro-hook.log

# Small delay to avoid race condition where transcript isn't fully written yet
sleep 1

# Read the hook input JSON from stdin
input=$(cat)

# Debug: Log the input
echo "[$(date)] Hook input: $input" >> /tmp/kokoro-hook.log

# Extract the transcript path
transcript_path=$(echo "$input" | jq -r '.transcript_path')

# Debug: Log the transcript path
echo "[$(date)] Transcript path: $transcript_path" >> /tmp/kokoro-hook.log

# Expand tilde to home directory if present
transcript_path="${transcript_path/#\~/$HOME}"

# Check if transcript file exists
if [ ! -f "$transcript_path" ]; then
  echo "[$(date)] Transcript file not found: $transcript_path" >> /tmp/kokoro-hook.log
  exit 0
fi

# Extract Claude's last response from the transcript
# Loop through messages in reverse to find text that appears AFTER tool uses completed
# This prevents reading text that PreToolUse hook already played
# NOTE: Using process substitution < <(tail -r ...) instead of pipe to avoid subshell variable scope issues
# Using tail -r instead of tac for macOS compatibility
seen_tool_result=0
claude_response=""
while IFS= read -r line; do
  message_type=$(echo "$line" | jq -r '.type' 2>/dev/null)

  # Once we see a tool_result, we know tools have been used
  if [ "$message_type" = "tool_result" ]; then
    seen_tool_result=1
  fi

  # Look for assistant text messages
  if [ "$message_type" = "assistant" ]; then
    TEXT=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null | tr '\n' ' ')

    # Only use text if we haven't seen any tool_results yet (meaning this is final response after tools)
    # OR if we never saw tool_results (meaning no tools were used)
    if [ -n "$TEXT" ]; then
      if [ "$seen_tool_result" != "1" ]; then
        claude_response="$TEXT"
        break
      fi
    fi
  fi
done < <(tail -r "$transcript_path")

# NOTE: no truncation here. The cap is applied AFTER marker extraction (below),
# because the summary marker sits at the END of a response: truncating first
# sliced the marker off any long answer, so extraction never saw it and the hook
# silently fell back to speaking the first 5000 characters of the full response.

# Debug: Log what was extracted
echo "[$(date)] Extracted response: $claude_response" >> /tmp/kokoro-hook.log

# Only proceed if we got a response
if [ -n "$claude_response" ]; then
  echo "[$(date)] Sending to kokoro-tts with $VOICE voice" >> /tmp/kokoro-hook.log
  echo "[$(date)] Response length: ${#claude_response}" >> /tmp/kokoro-hook.log

  # Check if response contains TTS_SUMMARY marker
  if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
    # Extract only the TTS_SUMMARY content
    # Note: $claude_response is already flattened to a single line by tr '\n' ' ' earlier
    # Uses awk to extract text between markers on a single line.
    # Scans for the LAST opening marker, not the first: a response that quotes the
    # marker syntax while explaining it would otherwise hijack the extraction and
    # yield the example's placeholder text instead of the real summary (observed
    # 2026-08-19 -- a 3-character "..." was spoken). The real summary is always last.
    tts_summary=$(echo "$claude_response" | awk '
      {
        open_tag = "<!-- TTS_SUMMARY"
        close_tag = "TTS_SUMMARY -->"
        open_len = length(open_tag)

        # Walk every occurrence of the opening marker, keeping the final one.
        start = 0
        search_from = 1
        while ((hit = index(substr($0, search_from), open_tag)) > 0) {
          start = search_from + hit - 1
          search_from = start + open_len
        }

        if (start > 0) {
          rest = substr($0, start + open_len)
          end = index(rest, close_tag)
          if (end > 0) {
            content = substr(rest, 1, end - 1)
            gsub(/^[[:space:]]+/, "", content)
            gsub(/[[:space:]]+$/, "", content)
            print content
          }
        }
      }
    ')

    if [ -n "$tts_summary" ]; then
      echo "[$(date)] Found TTS_SUMMARY, using summary content only" >> /tmp/kokoro-hook.log
      # Strip any markdown from TTS_SUMMARY content (e.g., **bold** -> bold)
      claude_response=$(echo "$tts_summary" | uv run --project "__CLAUDE_TTS_PROJECT_DIR__" python "__CLAUDE_TTS_PROJECT_DIR__/scripts/strip_markdown.py" 2>>/tmp/kokoro-hook.log || echo "$tts_summary")
    else
      echo "[$(date)] TTS_SUMMARY marker found but empty, falling back to full response" >> /tmp/kokoro-hook.log
    fi
  else
    echo "[$(date)] No TTS_SUMMARY found, stripping markdown via strip_markdown.py" >> /tmp/kokoro-hook.log

    # Strip markdown formatting using mistune Python library
    # Full absolute path ensures script works regardless of current working directory
    claude_response=$(echo "$claude_response" | uv run --project "__CLAUDE_TTS_PROJECT_DIR__" python "__CLAUDE_TTS_PROJECT_DIR__/scripts/strip_markdown.py" 2>>/tmp/kokoro-hook.log || echo "$claude_response")
  fi

  # Cap what is actually spoken (an extracted summary is short; this bounds the
  # no-marker fallback, which is the whole response).
  if [ "${#claude_response}" -gt 5000 ]; then
    echo "[$(date)] Truncating spoken text from ${#claude_response} to 5000 chars" >> /tmp/kokoro-hook.log
    claude_response="${claude_response:0:5000}"
  fi

  echo "[$(date)] Final response for TTS (length: ${#claude_response})" >> /tmp/kokoro-hook.log

  # Save response to secure temp file to avoid pipe blocking issues
  # Use mktemp with restrictive permissions for security
  tmpfile=$(mktemp /tmp/kokoro-input.XXXXXX)
  chmod 600 "$tmpfile"
  echo "$claude_response" > "$tmpfile"

  # Hand off to the shared serialized player: it waits (in the background, so
  # this hook still returns instantly) for any kokoro-tts already speaking,
  # then plays this one. No pkill here - overlapping speech used to be "solved"
  # by killing the other stream, which just made both utterances useless.
  "$HOOK_DIR/tts-play.sh" "$tmpfile" "$VOICE"
  echo "[$(date)] Queued response for serialized TTS playback" >> /tmp/kokoro-hook.log
else
  echo "[$(date)] No response found" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
