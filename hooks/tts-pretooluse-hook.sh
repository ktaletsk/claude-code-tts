#!/bin/bash
# Claude Code PreToolUse TTS Hook - Reads text that appears before tool uses

# Voice configuration - can be set via KOKORO_VOICE env var in ~/.claude/settings.json
VOICE="${KOKORO_VOICE:-af_sky}"

# Audio ducking configuration - lowers Apple Music volume while TTS plays (like Google Maps in CarPlay)
# macOS only - uses AppleScript to control Apple Music's internal volume
AUDIO_DUCK_ENABLED="${AUDIO_DUCK_ENABLED:-true}"
AUDIO_DUCK_SCRIPT="__CLAUDE_TTS_PROJECT_DIR__/scripts/audio-duck.sh"

# Debug logging
echo "[$(date)] PreToolUse TTS hook triggered" >> /tmp/kokoro-hook.log

# Small delay to allow transcript to be fully written
sleep 0.5

# Read the hook input JSON from stdin
input=$(cat)

# Debug: Log the input
echo "[$(date)] PreToolUse hook input: $input" >> /tmp/kokoro-hook.log

# Extract the transcript path and tool_use_id
transcript_path=$(echo "$input" | jq -r '.transcript_path')
current_tool_use_id=$(echo "$input" | jq -r '.tool_use_id')

echo "[$(date)] Current tool_use_id: $current_tool_use_id" >> /tmp/kokoro-hook.log

# Expand tilde to home directory if present
transcript_path="${transcript_path/#\~/$HOME}"

# Check if transcript file exists
if [ ! -f "$transcript_path" ]; then
  echo "[$(date)] Transcript file not found: $transcript_path" >> /tmp/kokoro-hook.log
  exit 0
fi

# Check if this is the first tool_use in the current message
# Extract the first tool_use_id from the last assistant message
# NOTE: Using process substitution < <(tail -r ...) instead of pipe to avoid subshell variable scope issues
# Using tail -r instead of tac for macOS compatibility
first_tool_use_id=""
while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "assistant"' >/dev/null 2>&1; then
    first_tool_use_id=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use") | .id' 2>/dev/null | head -1)
    break
  fi
done < <(tail -r "$transcript_path")

echo "[$(date)] First tool_use_id in message: $first_tool_use_id" >> /tmp/kokoro-hook.log

# Only proceed if this is the first tool use
if [ "$current_tool_use_id" != "$first_tool_use_id" ]; then
  echo "[$(date)] Skipping - not the first tool use in this message" >> /tmp/kokoro-hook.log
  exit 0
fi

echo "[$(date)] This is the first tool use - proceeding with TTS" >> /tmp/kokoro-hook.log

# Extract text from assistant messages that appear before the tool use
# Claude Code splits responses into separate messages for text and tool_use blocks
# We need to find text from the most recent assistant text message before the first tool use
# NOTE: Using process substitution < <(tail -r ...) instead of pipe to avoid subshell variable scope issues
# Using tail -r instead of tac for macOS compatibility
found_tool_use=0
claude_response=""
while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "assistant"' >/dev/null 2>&1; then
    # Check if this message contains the current tool_use_id
    tool_ids=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use") | .id' 2>/dev/null)

    # If we found the message with the first tool use, now look for preceding text
    if echo "$tool_ids" | grep -q "$current_tool_use_id"; then
      echo "[$(date)] Found message containing current tool_use_id" >> /tmp/kokoro-hook.log
      # Mark that we've found the tool use message, now collect text from previous messages
      found_tool_use=1
      continue
    fi

    # If we've found the tool use and this is a text message, extract it
    if [ "$found_tool_use" = "1" ]; then
      content_type=$(echo "$line" | jq -r '.message.content[0].type' 2>/dev/null)
      if [ "$content_type" = "text" ]; then
        TEXT=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null)
        if [ -n "$TEXT" ]; then
          echo "[$(date)] Found text message before tool use" >> /tmp/kokoro-hook.log
          claude_response="$TEXT"
          break
        fi
      fi
    fi
  fi
done < <(tail -r "$transcript_path")
# Truncate to 5000 characters
claude_response="${claude_response:0:5000}"

# Debug: Log what was extracted
echo "[$(date)] PreToolUse extracted text: $claude_response" >> /tmp/kokoro-hook.log

# Check if response contains TTS_SUMMARY marker
# If it does, skip playback - let the Stop hook handle TTS_SUMMARY extraction
if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
  echo "[$(date)] Skipping - message contains TTS_SUMMARY, let Stop hook handle it" >> /tmp/kokoro-hook.log
  exit 0
fi

# Session-based deduplication: compute hash of the text
# Hash files are cleared only at SessionEnd, so deduplication lasts entire session
text_hash=$(echo "$claude_response" | md5sum | awk '{print $1}')
last_hash_file="/tmp/kokoro-pretool-last-hash.txt"
last_hash=$(cat "$last_hash_file" 2>/dev/null)

# If we played this exact text in this session, skip (no time limit)
if [ "$text_hash" = "$last_hash" ]; then
  echo "[$(date)] Skipping - same text already played in this session" >> /tmp/kokoro-hook.log
  exit 0
fi

# Only proceed if we got a response and it's not empty
if [ -n "$claude_response" ] && [ ${#claude_response} -gt 10 ]; then
  echo "[$(date)] Sending to kokoro-tts with $VOICE voice" >> /tmp/kokoro-hook.log
  echo "[$(date)] Response length: ${#claude_response}, stripping markdown via strip_markdown.py" >> /tmp/kokoro-hook.log

  # Strip markdown formatting using mistune Python library
  # Full absolute path ensures script works regardless of current working directory
  claude_response=$(echo "$claude_response" | uv run --project "__CLAUDE_TTS_PROJECT_DIR__" python "__CLAUDE_TTS_PROJECT_DIR__/scripts/strip_markdown.py" 2>>/tmp/kokoro-hook.log || echo "$claude_response")

  echo "[$(date)] Response after markdown strip (length: ${#claude_response})" >> /tmp/kokoro-hook.log

  # Save the hash for session-based deduplication
  echo "$text_hash" > "$last_hash_file"
  echo "[$(date)] Saved text hash for session-based deduplication: $text_hash" >> /tmp/kokoro-hook.log

  # Save response to secure temp file
  # Use mktemp with restrictive permissions for security
  tmpfile=$(mktemp /tmp/kokoro-pretool-input.XXXXXX)
  chmod 600 "$tmpfile"
  echo "$claude_response" > "$tmpfile"

  # Kill any existing TTS processes to prevent overlapping audio
  # This ensures new narration doesn't overlap with previous TTS still playing
  if pkill -9 kokoro-tts 2>/dev/null; then
    echo "[$(date)] Killed existing kokoro-tts process" >> /tmp/kokoro-hook.log
  fi

  # Audio ducking: lower other audio before TTS starts
  if [ "$AUDIO_DUCK_ENABLED" = "true" ] && [ -x "$AUDIO_DUCK_SCRIPT" ]; then
    echo "[$(date)] Ducking audio before TTS" >> /tmp/kokoro-hook.log
    "$AUDIO_DUCK_SCRIPT" duck
  fi

  # Run kokoro-tts in background and capture PID for audio ducking restore
  kokoro-tts "$tmpfile" --voice "$VOICE" --stream --model "MODEL_PATH_PLACEHOLDER/kokoro-v1.0.onnx" --voices "MODEL_PATH_PLACEHOLDER/voices-v1.0.bin" >>/tmp/kokoro-hook.log 2>&1 &
  TTS_PID=$!
  echo "[$(date)] Started kokoro-tts with PID: $TTS_PID" >> /tmp/kokoro-hook.log

  # In background: wait for TTS to finish, then restore audio volume
  if [ "$AUDIO_DUCK_ENABLED" = "true" ] && [ -x "$AUDIO_DUCK_SCRIPT" ]; then
    (
      while kill -0 "$TTS_PID" 2>/dev/null; do
        sleep 0.5
      done
      echo "[$(date)] TTS finished, restoring audio" >> /tmp/kokoro-hook.log
      "$AUDIO_DUCK_SCRIPT" restore
    ) &
  fi
else
  echo "[$(date)] No text before tool uses, or text too short (${#claude_response} chars)" >> /tmp/kokoro-hook.log
fi

# Exit successfully (non-blocking)
exit 0
