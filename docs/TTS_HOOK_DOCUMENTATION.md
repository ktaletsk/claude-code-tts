# Claude Code TTS Hook Documentation

## Overview

This document describes the Text-to-Speech (TTS) hook configuration that automatically converts Claude's responses to speech using the Kokoro TTS model. The system includes three complementary hooks:

1. **TTS Playback Hook (Stop)**: Automatically reads Claude's final responses aloud after all actions complete
2. **PreToolUse TTS Hook (PreToolUse)**: Reads text that appears before tool uses
3. **TTS Interrupt Hook (UserPromptSubmit)**: Automatically stops ongoing TTS playback when you submit a new message

All hooks are configured globally and work across all Claude Code projects. You hear Claude's commentary as it works, and can interrupt mid-sentence.

## Features

- **Automatic TTS**: All Claude responses are converted to speech automatically
- **Continuous Narration**: Hear Claude's commentary as it works, not just final responses
- **PreToolUse Narration**: Reads text that appears before tool executions (e.g., "Let me check the configuration...")
- **Smart Interruption**: Automatically stops ongoing TTS playback when you submit a new prompt
- **Non-blocking**: Audio plays in the background; you can continue using Claude Code immediately without waiting
- **Global Configuration**: Works in any project directory where you run Claude Code
- **Audio Quality**: Uses Kokoro v1.0 ONNX model for speech synthesis
- **Multiple Voices**: Supports various voice styles including af_sky (currently configured)
- **Markdown Stripping**: Automatically removes markdown formatting using mistune Python library for cleaner speech output
- **Tool Output Filtering**: Only reads Claude's text, not tool outputs (e.g., directory listings)
- **Audio Ducking** (macOS): Automatically lowers Apple Music volume while TTS speaks, then restores it when done - like Google Maps in CarPlay

## File Locations

### Global Configuration Files

1. **Claude Settings**
   - Path: `~/.claude/settings.json`
   - Purpose: Registers the Stop hook that triggers after each Claude response

2. **Hook Scripts**
   - **TTS Playback Hook**
     - Path: `~/.claude/hooks/tts-stop-hook.sh`
     - Purpose: Executes the Kokoro TTS generation and playback after each Claude response
     - Must be executable: `chmod +x ~/.claude/hooks/tts-stop-hook.sh`
   - **PreToolUse TTS Hook**
     - Path: `~/.claude/hooks/tts-pretooluse-hook.sh`
     - Purpose: Reads text that appears before tool uses for natural conversational flow
     - Must be executable: `chmod +x ~/.claude/hooks/tts-pretooluse-hook.sh`
   - **TTS Interrupt Hook**
     - Path: `~/.claude/hooks/tts-interrupt-hook.sh`
     - Purpose: Stops ongoing TTS playback when user submits a new prompt
     - Must be executable: `chmod +x ~/.claude/hooks/tts-interrupt-hook.sh`
   - Note: Previous hook (`tts-stop-hook.sh`) is disabled and kept for reference

### Output Files

1. **Audio Output**
   - Audio is streamed directly to the audio device (no intermediate file)
   - Kokoro TTS uses `--stream` mode for immediate playback

2. **Debug Log**
   - Path: `/tmp/kokoro-hook.log`
   - Description: Detailed execution log for troubleshooting

### Project Dependencies

The hook requires the Kokoro TTS command-line tool:
- **TTS Command**: `kokoro-tts` (must be in PATH)
- **Voice Data**: `voices-v1.0.bin` (included with kokoro-tts installation)
- **Model**: `kokoro-v1.0.onnx` (included with kokoro-tts installation)

## Configuration Details

### Global Settings (`~/.claude/settings.json`)

```json
{
  "env": {
    "DISABLE_TELEMETRY": "1"
  },
  "includeCoAuthoredBy": false,
  "alwaysThinkingEnabled": false,
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-pretooluse-hook.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-stop-hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-session-end-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**Key Settings:**
- `UserPromptSubmit`: Hook type that executes when user submits a new message
  - Triggers the interrupt hook to stop ongoing TTS playback
  - `timeout`: 5 seconds (quick operation to kill TTS process)
- `PreToolUse`: Hook type that executes when Claude is about to use tools
  - Triggers the PreToolUse TTS hook to read text that appears before tool uses
  - `timeout`: 5 seconds (quick text extraction and TTS start)
  - Enables natural conversational flow by narrating Claude's actions
- `Stop`: Hook type that executes after Claude finishes responding
  - Triggers the TTS playback hook to start reading the response
  - `timeout`: 10 seconds (allows time for TTS to start streaming)
- `SessionEnd`: Hook type that executes when Claude Code session terminates
  - Triggers cleanup hook to kill TTS processes and remove temporary files
  - Clears deduplication hashes for fresh start in next session
  - `timeout`: 5 seconds (quick cleanup operation)

### Hook Scripts

#### TTS Playback Hook (`~/.claude/hooks/tts-stop-hook.sh`)

The script performs the following steps:

1. **Receives hook input** via stdin with transcript path
2. **Extracts response text** from the conversation transcript
3. **Strips markdown formatting** for cleaner speech output
4. **Streams audio** using `kokoro-tts` with af_sky voice
5. **Logs execution** to `/tmp/kokoro-hook.log`

**Key Features:**
- **Smart text extraction**: Finds text that appears AFTER all tool results have completed, preventing duplicate playback with PreToolUse hook
- **Post-tool timing**: Only reads final response text, not introductory text before tool uses
- **Markdown stripping**: Removes code blocks, bold/italic markers, links, headers, list markers, etc.
- **Length truncation**: Limits responses to 5000 characters for processing
- **Error handling**: Logs errors without crashing the hook
- **Non-blocking playback**: Uses subshell pattern `(command &)` to fully detach audio playback
- **Streaming mode**: Uses `--stream` flag for immediate audio output without intermediate files
- **Detailed logging**: Every execution is logged for debugging

#### PreToolUse TTS Hook (`~/.claude/hooks/tts-pretooluse-hook.sh`)

The script performs the following steps:

1. **Receives hook input** via stdin when Claude is about to use tools
2. **Extracts text that appears before tool uses** from the conversation transcript
3. **Strips markdown formatting** for cleaner speech output
4. **Streams audio** using `kokoro-tts` with af_sky voice
5. **Logs execution** to `/tmp/kokoro-hook.log`

**Key Features:**
- **Cross-message text extraction**: Reads text from the assistant message immediately preceding the tool_use message (Claude Code splits text and tool_use into separate messages in the transcript)
- **First tool detection**: Only triggers for the first tool_use in a response, preventing repeated playback
- **Session-based deduplication**: Uses MD5 hashing to skip identical text throughout the entire Claude Code session (handles auto-approval scenarios)
- **Cross-hook coordination**: Detects TTS_SUMMARY markers and skips playback to avoid duplication with Stop hook
- **Natural conversational flow**: Reads phrases like "Let me check..." before tools execute
- **Minimum length check**: Skips responses shorter than 10 characters to avoid tiny fragments
- **Markdown stripping**: Same cleaning as main TTS hook
- **Non-blocking playback**: Audio plays in background while tools execute
- **Tool output filtering**: Never reads tool outputs (directory listings, file contents, etc.)

#### TTS Interrupt Hook (`~/.claude/hooks/tts-interrupt-hook.sh`)

The script performs the following steps:

1. **Receives hook trigger** when user submits a new prompt
2. **Kills all running kokoro-tts processes** using `pkill -9`
3. **Logs execution** to `/tmp/kokoro-hook.log`

**Key Features:**
- **Instant interruption**: Uses `pkill -9` for immediate process termination
- **Silent operation**: Doesn't fail if no TTS process is running
- **Fast execution**: Completes within the 5-second timeout
- **Detailed logging**: Records every interrupt attempt for debugging

#### SessionEnd Hook (`~/.claude/hooks/tts-session-end-hook.sh`)

The script performs the following steps:

1. **Receives hook trigger** when Claude Code session ends
2. **Extracts session information** (session ID, termination reason)
3. **Kills running TTS processes** using `pkill -9`
4. **Removes temporary files** (`/tmp/kokoro-*.txt`)
5. **Clears deduplication hashes** to reset for next session
6. **Logs cleanup actions** to `/tmp/kokoro-hook.log`

**Key Features:**
- **Session-based cleanup**: Runs automatically when Claude Code terminates
- **Fresh start**: Clears deduplication tracking for new sessions
- **Resource cleanup**: Removes all TTS-related temporary files
- **Non-blocking**: Cannot prevent session termination
- **Reason tracking**: Logs why session ended (exit/clear/logout)

## How It Works

### Execution Flow

#### When Claude Uses Tools (PreToolUse TTS)

1. **User sends message** to Claude Code
2. **Claude responds** with text like "Let me check the configuration..." followed by tool uses
3. **PreToolUse hook triggers** automatically when Claude is about to use tools
4. **PreToolUse TTS Hook script executes**:
   - Reads conversation transcript from `~/.claude/projects/.../*.jsonl`
   - Locates the tool_use message, then reads backward to find text from the preceding assistant message
   - Only triggers on first tool_use in a response (skips subsequent tools)
   - **Checks for TTS_SUMMARY marker** - if found, skips playback (lets Stop hook handle it)
   - Checks MD5 hash to skip duplicate text in the session (session-based deduplication)
   - Skips if text is less than 10 characters
   - Strips markdown formatting
   - Truncates to 5000 characters if needed
   - Saves cleaned text to `/tmp/kokoro-pretool-input.txt`
5. **Audio generation and playback**:
   - Pipes text file to `kokoro-tts` with `--voice af_sky --stream` flags
   - TTS streams audio immediately (you hear "Let me check..." right away)
   - Uses subshell pattern `(command &)` to fully detach the process
   - Tools execute while audio plays
   - Claude narrates its actions before executing them

#### When Claude Responds (TTS Playback)

1. **User sends message** to Claude Code
2. **Claude responds** with text and/or tool calls
3. **Stop hook triggers** automatically when response completes (after all tools finish)
4. **TTS Playback Hook script executes**:
   - Reads conversation transcript from `~/.claude/projects/.../*.jsonl`
   - Reads backward through messages until finding tool_result (if tools were used)
   - Extracts text from first assistant message BEFORE any tool_result (ensures only post-tool text is read)
   - Skips text that PreToolUse hook already played
   - Concatenates multiple text blocks into single string
   - Strips markdown formatting (code blocks, bold, italic, links, headers, etc.)
   - Truncates to 5000 characters if needed
   - Saves cleaned text to `/tmp/kokoro-input.txt`
5. **Audio generation and playback**:
   - Pipes text file to `kokoro-tts` with `--voice af_sky --stream` flags
   - TTS streams audio directly to audio device (no intermediate file)
   - Uses subshell pattern `(command &)` to fully detach the process
   - User can continue using Claude Code immediately
   - Audio plays asynchronously in the background

#### When User Submits New Prompt (TTS Interruption)

1. **User begins typing** a new message to Claude Code
2. **User submits the message** (presses Enter)
3. **UserPromptSubmit hook triggers** immediately
4. **TTS Interrupt Hook script executes**:
   - Runs `pkill -9 kokoro-tts` to kill all running TTS processes
   - Logs the interrupt action to `/tmp/kokoro-hook.log`
   - Returns immediately (within milliseconds)
5. **Result**:
   - Ongoing TTS playback stops instantly
   - User's new prompt is processed without audio interference
   - When Claude responds, new TTS playback begins automatically

### Cross-Hook Coordination

The PreToolUse and Stop hooks coordinate to prevent duplicate playback when messages contain both text and TTS_SUMMARY markers:

**Scenario: Message with TTS_SUMMARY**
1. Claude responds with text like "Changes Complete..." followed by tool uses and TTS_SUMMARY marker
2. **PreToolUse hook** detects `<!-- TTS_SUMMARY` marker in extracted text
3. **PreToolUse skips** playback and logs "Skipping - message contains TTS_SUMMARY, let Stop hook handle it"
4. **Stop hook** extracts and plays only the TTS_SUMMARY content
5. **Result**: You hear only the concise summary, no repetition

**Scenario: Message without TTS_SUMMARY**
1. Claude responds with "Let me check the configuration..." followed by tool uses
2. **PreToolUse hook** finds no TTS_SUMMARY marker
3. **PreToolUse plays** the full text before tools execute
4. **Stop hook** may play final response after tools complete (if different content)
5. **Result**: You hear commentary before tools, then results after

This coordination ensures:
- Messages with summaries → Only summary is spoken (via Stop hook)
- Messages without summaries → Full text is spoken (via PreToolUse hook)
- No duplicate playback of the same content

### Global Applicability

The hook is **globally configured** and works in any directory because:

1. Hook registration is in `~/.claude/settings.json` (global config)
2. Hook script is in `~/.claude/hooks/` (global hooks directory)
3. `kokoro-tts` command is in PATH (system-wide availability)
4. No project-specific configuration required

**This means:** When you run Claude Code in any project directory, the TTS hook will automatically work without any additional setup.

## Verification

### Check Hook Registration

Run the `/hooks` command in Claude Code:

```bash
/hooks
```

You should see the Stop hook listed.

### Check Files Exist

```bash
# Check global settings
cat ~/.claude/settings.json | jq '.hooks'

# Check hook scripts exist and are executable
ls -lh ~/.claude/hooks/tts-stop-hook.sh
ls -lh ~/.claude/hooks/tts-interrupt-hook.sh

# Check kokoro-tts is available
which kokoro-tts
```

### Monitor Hook Execution

```bash
# Watch the log file in real-time
tail -f /tmp/kokoro-hook.log

# Check recent playback executions
tail -50 /tmp/kokoro-hook.log | grep "Kokoro TTS hook"

# Check recent interrupt executions
tail -50 /tmp/kokoro-hook.log | grep "TTS Interrupt"

# Check if audio is currently playing
pgrep -a kokoro-tts
```

### Test Audio Playback Manually

```bash
# Test kokoro-tts with streaming (current voice)
echo "This is a test of the Kokoro TTS system." | kokoro-tts - --voice af_sky --stream

# Test the interrupt functionality
# In one terminal, start playing audio:
echo "This is a very long message that will take several seconds to complete reading aloud so we can test the interrupt functionality properly." | kokoro-tts - --voice af_sky --stream

# In another terminal, kill the process:
pkill -9 kokoro-tts
```

## Troubleshooting

### No Audio Playback

**Check 1: Hook is executing**

```bash
tail -20 /tmp/kokoro-hook.log | grep "Kokoro TTS hook triggered"
```

If you see recent timestamps, the hook is running.

**Check 2: Text extraction is working**

```bash
tail -20 /tmp/kokoro-hook.log | grep "Response length"
```

Should show non-zero length for responses.

**Check 3: kokoro-tts is running**

```bash
pgrep -a kokoro-tts
```

Should show the kokoro-tts process if audio is currently playing.

**Check 4: Audio device is working**

```bash
# Test audio device
pactl list sinks short

# Test with a simple sound
speaker-test -t wav -c 2 -l 1
```

### Hook Not Executing

**Check 1: Hooks are registered**

```bash
jq '.hooks' ~/.claude/settings.json
# Should show both UserPromptSubmit and Stop hooks
```

**Check 2: Scripts are executable**

```bash
chmod +x ~/.claude/hooks/tts-stop-hook.sh
chmod +x ~/.claude/hooks/tts-interrupt-hook.sh
```

**Check 3: Dependencies are available**

```bash
which jq kokoro-tts
```

### Response Text Not Extracted

Check the log for "Response length: 0" which indicates:
- Message only contained tool calls (no text)
- Text extraction logic failed

The hook automatically skips messages without text and finds the previous message with text content.

### Hook Reads Previous Response Instead of Current

This is caused by a race condition where the hook executes before the transcript is fully written. If you experience this issue:

```bash
# Add a small delay at the beginning of the hook script
sleep 1
```

### Claude Code Blocks During Audio Playback

**Symptoms:** You cannot type or interact with Claude Code while audio is playing.

**Cause:** The kokoro-tts process is not properly detached from the hook script.

**Fix:** Verify the hook script uses the subshell pattern:

```bash
(echo "$claude_response" | kokoro-tts - --voice af_nova --stream 2>>/tmp/kokoro-hook.log &)
```

The parentheses are critical for full detachment.

### TTS Interrupt Not Working

**Symptoms:** Audio continues playing even after submitting a new prompt.

**Possible Causes:**

1. **UserPromptSubmit hook not registered**

   ```bash
   jq '.hooks.UserPromptSubmit' ~/.claude/settings.json
   # Should show the interrupt hook configuration
   ```

2. **Interrupt script not executable**

   ```bash
   chmod +x ~/.claude/hooks/tts-interrupt-hook.sh
   ```

3. **Process name mismatch**

   ```bash
   # Check what processes are actually running
   pgrep -a kokoro
   # Should show "kokoro-tts" when audio is playing
   ```

4. **Check interrupt hook logs**

   ```bash
   tail -20 /tmp/kokoro-hook.log | grep "TTS Interrupt"
   # Should show interrupt hook being triggered
   ```

## Customization

### Audio Ducking (macOS)

Audio ducking automatically lowers Apple Music volume when TTS speaks, then restores it - like Google Maps in CarPlay.

**How it works:**

1. When TTS starts, Apple Music volume drops to 5% of current level
2. A background process monitors when TTS finishes
3. When TTS completes (or is interrupted), volume is restored

**Configuration:**

Set environment variables in `~/.claude/settings.json`:

```json
{
  "env": {
    "AUDIO_DUCK_ENABLED": "true",
    "DUCK_LEVEL": "5"
  }
}
```

| Variable | Default | Description |
|----------|---------|-------------|
| `AUDIO_DUCK_ENABLED` | `true` | Set to `false` to disable ducking |
| `DUCK_LEVEL` | `5` | Target volume as percentage (lower = quieter music) |
| `MIN_DUCK_VOLUME` | `10` | Minimum volume floor (prevents complete silence) |

**Helper Script:**

The ducking logic is in `scripts/audio-duck.sh`. It can be called manually:

```bash
# Duck music volume
./scripts/audio-duck.sh duck

# Restore music volume
./scripts/audio-duck.sh restore

# Duck, wait for process to finish, then restore
./scripts/audio-duck.sh duck-and-wait <PID>
```

**Supported Apps:**

Currently supports Apple Music on macOS via AppleScript. The script controls the app's internal volume (not system volume), so TTS audio remains at full volume.

**Troubleshooting:**

Check `/tmp/kokoro-hook.log` for ducking-related messages:

```bash
grep "audio-duck\|Duck" /tmp/kokoro-hook.log | tail -20
```

### Change Voice

Configure the voice via the `KOKORO_VOICE` environment variable in `~/.claude/settings.json`:

```json
{
  "env": {
    "KOKORO_VOICE": "af_bella"
  }
}
```

The default voice is `af_sky`. Changes take effect on the next Claude Code session.

#### Available Voices (54 total)

**American English:**

- Female: `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky`
- Male: `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`

**British English:**

- Female: `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily`
- Male: `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`

**Other Languages:**

- French: `ff_siwis`
- Italian: `if_sara`, `im_nicola`
- Japanese: `jf_alpha`, `jf_gongitsune`, `jf_nezumi`, `jf_tebukuro`, `jm_kumo`
- Mandarin: `zf_xiaobei`, `zf_xiaoni`, `zf_xiaoxiao`, `zf_xiaoyi`, `zm_yunjian`, `zm_yunxi`, `zm_yunxia`, `zm_yunyang`

See [Kokoro VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) for the complete list

### Adjust Response Length Limit

The hook truncates responses to 5000 characters. To change this, edit the hook script:

```bash
# Find the line with bash substring and adjust the value:
# Current: 5000 characters
claude_response="${claude_response:0:5000}"

# Example: Change to 3000 characters
claude_response="${claude_response:0:3000}"
```

### Disable Streaming (Save to File Instead)

If you want to save audio to a file instead of streaming:

```bash
# Replace the streaming command:
(echo "$claude_response" | kokoro-tts - --voice af_nova > /tmp/claude_response.wav 2>>/tmp/kokoro-hook.log && \
 ffplay -nodisp -autoexit /tmp/claude_response.wav 2>>/tmp/kokoro-hook.log &)
```

### Disable Hooks Temporarily

**Option 1: Disable all hooks**
Remove or comment out the `hooks` section in `~/.claude/settings.json`:

```json
{
  "env": {
    "DISABLE_TELEMETRY": "1"
  },
  "includeCoAuthoredBy": false,
  "alwaysThinkingEnabled": false
  // "hooks": { ... }  <- Commented out
}
```

**Option 2: Disable only TTS playback (keep interrupt)**
Remove just the Stop hook:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
    // "Stop": [ ... ]  <- Removed
  }
}
```

**Option 3: Disable only interrupt (keep TTS playback)**
Remove just the UserPromptSubmit hook:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/tts-stop-hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
    // "UserPromptSubmit": [ ... ]  <- Removed
  }
}
```

**Option 4: Use environment variable**

```bash
export CLAUDE_DISABLE_HOOKS=1
claude
```

## Technical Details

### Hook Input Format

The Stop hook receives JSON via stdin:

```json
{
  "session_id": "abc12345-e878-4ec3-b91a-a0bc29129ad8",
  "transcript_path": "/home/user/.claude/projects/-home-user-myproject/abc12345-e878-4ec3-b91a-a0bc29129ad8.jsonl",
  "cwd": "/home/user/myproject",
  "permission_mode": "acceptEdits",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
```

### Transcript Format

Claude Code splits responses into separate JSONL entries for text and tool_use:

```json
{"type": "assistant", "message": {"content": [{"type": "text", "text": "I'll check the files..."}]}}
{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", ...}]}}
{"type": "tool_result", "tool_use_id": "...", "content": "..."}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "The check completed successfully."}]}}
```

**Hook Coordination:**
- **PreToolUse hook**: Finds the tool_use message, reads backward to extract text from preceding assistant message
- **Stop hook**: Reads backward until finding tool_result, then extracts text from the first assistant message before tool_result
- This prevents both hooks from reading the same text

### Background Playback

Audio playback uses a subshell to fully detach from the hook process:

```bash
(echo "$claude_response" | kokoro-tts - --voice af_nova --stream 2>>/tmp/kokoro-hook.log &)
```

**The subshell pattern `(command &)` is critical** for non-blocking operation:
- **Without parentheses**: `command &` runs in background but parent script may still wait
- **With parentheses**: `(command &)` creates a subshell that fully detaches the process
- The subshell exits immediately after spawning the background process
- This allows the hook script to return immediately to Claude Code
- User can continue typing while TTS audio plays independently

This pattern ensures:
- Hook script completes immediately
- kokoro-tts continues streaming audio in background
- User can use Claude Code without any blocking or delay

## Dependencies

### Required Tools

1. **jq** - JSON processor for parsing transcript

   ```bash
   sudo dnf install jq  # Fedora/RHEL
   ```

2. **kokoro-tts** - Kokoro TTS command-line tool
   - Must be installed and available in PATH
   - Includes voice models (af_nova, af_sky, etc.)
   - Supports streaming mode for real-time audio output

## Maintenance

### Update Hook Script

1. Edit the script:

   ```bash
   nano ~/.claude/hooks/tts-stop-hook.sh
   ```

2. Test changes:

   ```bash
   # Manually run the hook with test input
   echo '{"transcript_path":"~/.claude/projects/.../*.jsonl"}' | bash ~/.claude/hooks/tts-stop-hook.sh
   ```

3. Changes take effect immediately (no restart required)

### Clear Old Logs

```bash
# View log size
du -h /tmp/kokoro-hook.log

# Clear log
> /tmp/kokoro-hook.log

# Or delete old logs
rm /tmp/kokoro-hook.log
```

### Backup Configuration

```bash
# Backup settings
cp ~/.claude/settings.json ~/.claude/settings.json.backup

# Backup hook script
cp ~/.claude/hooks/tts-stop-hook.sh ~/.claude/hooks/tts-stop-hook.sh.backup
```

## Limitations

1. **Command Dependency**: Requires `kokoro-tts` to be installed and in PATH
2. **Streaming Only**: Audio streams directly to audio device (no file saved)
3. **Text Only**: Only reads text content, skips tool outputs and code blocks
4. **Local Playback**: Audio plays on the machine running Claude Code (not remote sessions)
5. **Length Limit**: Responses truncated to 5000 characters for processing
   - **Why it exists**: Prevents extremely long TTS sessions (e.g., 10,000+ character responses could take several minutes to read aloud)
   - **What happens**: If Claude's response exceeds 5000 characters, only the first 5000 characters are sent to TTS
   - **User experience**: Longer responses will appear to "cut off" mid-sentence, even though the full text is visible in Claude Code
   - **How to adjust**: Edit `~/.claude/hooks/tts-stop-hook.sh` and change `${claude_response:0:5000}` to a different value (e.g., `${claude_response:0:10000}` for 10,000 characters)
   - **Remove entirely**: Change `${claude_response:0:5000}` to just `$claude_response` to read all responses regardless of length

## Support

For issues or questions:

1. **Check logs**: `/tmp/kokoro-hook.log`
2. **Test components**: Verify kokoro-tts and jq work independently
3. **Review configuration**: Ensure hook is registered and script is executable
4. **Manual testing**: Run hook script manually to isolate issues

## Recent Fixes (November 2025)

### Migration to Kokoro TTS

**Date:** November 2025

**Change:** Migrated from Supertonic TTS to Kokoro TTS.

**Benefits:**
- Simpler setup - no Python environment needed
- Faster audio generation with streaming mode
- Uses Kokoro v1.0 ONNX model
- No intermediate WAV file generation
- Supports multiple voices

### Fix: Non-Blocking Audio Playback

**Date:** November 19, 2025

**Problem:** Hook script was blocking Claude Code, preventing user interaction until audio completed playing.

**Root Cause:** The background operator `&` alone is insufficient to fully detach a process from the parent script. The parent script may still wait for the child process to complete, blocking the hook from returning to Claude Code.

**Solution:** Wrapped the kokoro-tts command in a subshell with parentheses:

**Before:**

```bash
echo "$claude_response" | kokoro-tts - --voice af_nova --stream 2>>/tmp/kokoro-hook.log &
```

**After:**

```bash
(echo "$claude_response" | kokoro-tts - --voice af_nova --stream 2>>/tmp/kokoro-hook.log &)
```

**How it works:**
- The subshell pattern `(command &)` creates a new subshell
- The subshell spawns kokoro-tts in the background and exits immediately
- This fully detaches the TTS process from the hook script
- Hook script returns immediately, allowing Claude Code to continue
- Audio continues playing independently in the background

This pattern is borrowed from the previous tts-stop-hook.sh which used the same technique successfully with ffplay.

### Enhancement: TTS Interrupt Hook

**Date:** November 19, 2025

**Problem:** When a user submits a new prompt while Claude is still reading the previous response aloud, the audio continues playing and overlaps with the new interaction. This creates a confusing and distracting user experience.

**Solution:** Added a new `UserPromptSubmit` hook that automatically interrupts ongoing TTS playback.

**Implementation:**

1. **New Hook Script:** `~/.claude/hooks/tts-interrupt-hook.sh`
   - Triggers when user submits a new message
   - Immediately kills all running `kokoro-tts` processes using `pkill -9`
   - Logs interrupt action for debugging
   - Returns immediately (non-blocking)

2. **Hook Registration:** Added to `~/.claude/settings.json`

   ```json
   "UserPromptSubmit": [
     {
       "hooks": [
         {
           "type": "command",
           "command": "bash ~/.claude/hooks/tts-interrupt-hook.sh",
           "timeout": 5
         }
       ]
     }
   ]
   ```

**Benefits:**
- **Instant interruption**: Audio stops immediately when user submits new prompt
- **No audio overlap**: Audio does not overlap with new interactions
- **Automatic**: Works without user intervention
- **Fast**: Completes within milliseconds
- **Reliable**: Uses `pkill -9` for guaranteed process termination

**User Experience:**
1. Claude responds and begins reading aloud
2. User starts typing a new message while audio is still playing
3. User presses Enter to submit the message
4. **TTS audio stops instantly**
5. Claude processes the new message
6. When Claude responds, new TTS playback begins

The user can interrupt Claude mid-sentence by submitting a new prompt.

### Enhancement: Markdown Stripping

**Date:** November 19, 2025 (Updated November 25, 2025 to use mistune)

**Problem:** Claude's responses often contain markdown formatting (code blocks, bold/italic text, links, headers, etc.) which sounds awkward when read aloud by TTS.

**Solution:** Markdown stripping using the mistune Python library with a custom PlainTextRenderer.

**Implementation:**

A Python script (`scripts/strip_markdown.py`) uses mistune to properly parse and strip markdown:
- Code blocks (including multiline blocks)
- Inline code
- Bold text (`**text**` or `__text__`)
- Italic text (`*text*` or `_text_`)
- Links (preserves link text, removes URL)
- Headers (`#`, `##`, `###`, etc.)
- List markers (`-`, `*`, `1.`, etc.)
- Blockquotes (`>`)
- Tables (pipe-based)
- Bare URLs
- File paths
- Check marks and emoji

The script is invoked from the shell hooks via:

```bash
uv run --project "/path/to/claude-code-tts" python scripts/strip_markdown.py
```

The project path is automatically set during installation by `install.sh`.

**Benefits:**
- **Proper parsing**: Uses mistune's markdown parser for accurate stripping
- **Multiline support**: Correctly handles multiline code blocks (unlike sed)
- **Cleaner speech**: TTS output sounds more conversational
- **No artifacts**: Removes code and formatting syntax
- **Fallback**: Falls back to original text if Python/uv fails

**Example:**

Before markdown stripping:

```text
"I'll use the **Read** tool to read `config.json`. Here's what I found in the code block: backtick backtick backtick..."
```

After markdown stripping:

```text
"I'll use the Read tool to read. Here's what I found in the code block..."
```

### Fix: PreToolUse Hook Timing and Logic Issues

**Date:** November 19, 2025

**Problem:** The PreToolUse hook was not reading text that appeared before tool uses. When Claude said phrases like "Let me verify the Stop hook..." before making tool calls, users heard nothing.

**Root Causes:**

1. **Timing Issue**: The PreToolUse hook was firing before the transcript file was fully written to disk, resulting in incomplete data being read
2. **Logic Issue**: The jq query in the hook returned `empty` when no tool_use blocks existed in the transcript yet (which is the case when PreToolUse fires, as tool_use blocks haven't been written yet)

**Investigation:**

The logs showed:

```text
[Wed Nov 19 10:34:05 AM CST 2025] PreToolUse extracted text:
```

This empty extraction indicated the hook was executing but not finding text. Analysis of the transcript structure revealed that when PreToolUse fires, the text has been written but tool_use blocks haven't been added yet. The original jq logic was:

```jq
if $first_tool_idx then
  $content[:$first_tool_idx] | map(select(.type == "text") | .text) | join(" ")
else
  empty  # ← This was the problem!
end
```

When no tool_use blocks existed yet, it returned `empty` instead of extracting the text.

**Solution:**

Applied two fixes to `~/.claude/hooks/tts-pretooluse-hook.sh`:

1. **Added 0.5 second delay** (line 8):

   ```bash
   # Small delay to allow transcript to be fully written
   sleep 0.5
   ```

2. **Fixed jq logic** (line 41):

   ```jq
   if $first_tool_idx then
     $content[:$first_tool_idx] | map(select(.type == "text") | .text) | join(" ")
   else
     $content | map(select(.type == "text") | .text) | join(" ")  # ← Extract all text
   end
   ```

**Result:**

After the fix, the hook successfully extracts text:

```text
[Wed Nov 19 11:12:54 AM CST 2025] PreToolUse extracted text: The PreToolUse hook is now working correctly.
```

**Benefits:**
- **Narration before actions**: Users now hear Claude's commentary before tool executions
- **Proper timing**: The delay ensures transcript is fully written before reading
- **Correct logic**: Extracts text whether tool_use blocks exist in transcript or not
- **Consistent behavior**: Works reliably across different types of responses

**User Experience:**

Before the fix:
1. Claude says "Let me check the configuration..." (text)
2. Claude makes tool call
3. User hears nothing

After the fix:
1. Claude says "Let me check the configuration..." (text)
2. User immediately hears "Let me check the configuration..."
3. Tool executes while audio plays
4. Commentary plays while tools execute

### Enhancement: TTS_SUMMARY Extraction

**Date:** November 21, 2025

**Problem:** Claude's responses often contain detailed technical information (file paths, URLs, code snippets, error messages) that is important to read but awkward to hear via TTS. Users want to see the full technical response but only hear a conversational summary.

**Solution:** Added TTS_SUMMARY marker support to the Stop hook for selective content extraction.

**Implementation:**

Modified `~/.claude/hooks/tts-stop-hook.sh` to detect and extract TTS_SUMMARY markers:

```bash
# Check if response contains TTS_SUMMARY marker
if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
  # Extract only the TTS_SUMMARY content
  tts_summary=$(echo "$claude_response" | sed -n 's/.*<!-- TTS_SUMMARY[[:space:]]*\(.*\)[[:space:]]*TTS_SUMMARY -->.*/\1/p')

  if [ -n "$tts_summary" ]; then
    claude_response="$tts_summary"  # Use summary only
  fi
else
  # Fall back to full response with markdown stripping
  claude_response=$(echo "$claude_response" | sed -E '...')  # Original behavior
fi
```

**Marker Format:**

```html
<!-- TTS_SUMMARY
Brief, natural language summary without URLs, file paths, or technical jargon.
Just explain what was accomplished in 1-2 sentences.
TTS_SUMMARY -->
```

**Example Usage:**

Claude's full response:

```text
I've modified the hook script at ~/.claude/hooks/tts-stop-hook.sh on line 54
using the sed pattern: sed -n 's/.*<!-- TTS_SUMMARY[[:space:]]*\(.*\)...'

The file permissions are -rwx--x--x and the script is executable.

<!-- TTS_SUMMARY
I modified the text to speech hook to extract only the summary portions of my responses.
TTS_SUMMARY -->

Additional technical details follow...
```

What the user hears:

```text
I modified the text to speech hook to extract only the summary portions of my responses.
```

**Benefits:**
- **Selective listening**: Hear only conversational summaries, not technical details
- **No audio clutter**: URLs, file paths, and code snippets are excluded from TTS
- **Easier to follow**: Summaries are written specifically for listening
- **Backward compatible**: Works with or without TTS_SUMMARY markers
- **Flexible**: Claude can choose when to include summaries based on response complexity

**Integration:**
- The installer automatically adds TTS_SUMMARY instructions to `~/.claude/CLAUDE.md` (preserves existing content)
- Works with both global (`~/.claude/CLAUDE.md`) and project-specific CLAUDE.md instructions
- Automatically detects markers without requiring configuration changes
- Falls back to full markdown stripping if no TTS_SUMMARY is present
- Logs detection and extraction to `/tmp/kokoro-hook.log` for debugging

**User Experience:**

Before TTS_SUMMARY:
1. Claude writes detailed technical response
2. TTS reads everything including file paths, URLs, and code
3. Audio is long and difficult to follow

After TTS_SUMMARY:
1. Claude writes detailed technical response (visible on screen)
2. Claude adds conversational summary in TTS_SUMMARY marker
3. TTS reads ONLY the summary
4. Audio is concise

Users can read technical details while hearing conversational summaries.

### Fix: PreToolUse Hook Duplicate Playback

**Date:** November 21, 2025

**Problem:** When Claude responded with multiple tool uses in a single message (e.g., 5 WebSearch/WebFetch calls), the PreToolUse hook triggered once for each tool use. This caused the same introductory text (e.g., "I'll search online for information...") to be read aloud 5 times instead of just once.

**Root Cause:** The PreToolUse hook fires for every tool use in a message, not just once per message. The existing time-based deduplication (120-second window) provides a safety net to prevent the same text from being played multiple times even when tool executions take a long time.

**Example of the Problem:**

User sees this in Claude's response:

```text
● I'll search online for information...

● WebSearch(...)
  ⎿  Did 1 search in 21s

● WebFetch(...)
  ⎿  Received 50.8KB

● WebSearch(...)
  ⎿  Did 1 search in 23s

● WebFetch(...)
  ⎿  Running...

● WebFetch(...)
  ⎿  Fetching...
```

User heard "I'll search online for information..." **5 times** (once per tool use).

**Solution:** Modified `~/.claude/hooks/tts-pretooluse-hook.sh` to detect whether the current tool use is the first tool use in the message, and skip playback for subsequent tool uses.

**Implementation:**

Added logic to extract and compare tool_use IDs:

```bash
# Extract the current tool_use_id from hook input
current_tool_use_id=$(echo "$input" | jq -r '.tool_use_id')

# Extract the first tool_use_id from the last assistant message in transcript
first_tool_use_id=$(tac "$transcript_path" | while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "assistant"' >/dev/null 2>&1; then
    echo "$line" | jq -r '.message.content[] | select(.type == "tool_use") | .id' 2>/dev/null | head -1
    break
  fi
done)

# Only proceed if this is the first tool use
if [ "$current_tool_use_id" != "$first_tool_use_id" ]; then
  echo "[$(date)] Skipping - not the first tool use in this message" >> /tmp/kokoro-hook.log
  exit 0
fi
```

**Benefits:**
- **Single playback per message**: Text before tool uses is read exactly once, regardless of how many tools are used
- **No repetition**: No more repetitive audio when Claude uses multiple tools
- **Efficient**: Detects first tool use using IDs rather than timing heuristics
- **Reliable**: Works regardless of how long tool executions take
- **Clean logs**: Clearly shows which tool uses are skipped

**User Experience:**

Before the fix:
1. Claude says "I'll search online..." (text)
2. User hears "I'll search online..."
3. Tool 1 executes
4. User hears "I'll search online..." (duplicate)
5. Tool 2 executes
6. User hears "I'll search online..." (duplicate)
7. Tool 3 executes
8. (etc., repeated for all tool uses)

After the fix:
1. Claude says "I'll search online..." (text)
2. User hears "I'll search online..." (first tool use)
3. Tool 1 executes
4. Tool 2 executes (silent)
5. Tool 3 executes (silent)
6. Tool 4 executes (silent)
7. Tool 5 executes (silent)
8. Single playback only

**Log Output:**

After the fix, the log shows clear skipping behavior:

```text
[Fri Nov 21 09:20:51 AM CST 2025] PreToolUse TTS hook triggered
[Fri Nov 21 09:20:51 AM CST 2025] Current tool_use_id: toolu_01HXQr8F3uvhS7cnb1KEBjE
[Fri Nov 21 09:20:51 AM CST 2025] First tool_use_id in message: toolu_01HXQr8F3uvhS7cnb1KEBjE
[Fri Nov 21 09:20:51 AM CST 2025] This is the first tool use - proceeding with TTS

[Fri Nov 21 09:20:55 AM CST 2025] PreToolUse TTS hook triggered
[Fri Nov 21 09:20:55 AM CST 2025] Current tool_use_id: toolu_01B735eVY4pF3QeVxgX5QFYv
[Fri Nov 21 09:20:55 AM CST 2025] First tool_use_id in message: toolu_01HXQr8F3uvhS7cnb1KEBjE
[Fri Nov 21 09:20:55 AM CST 2025] Skipping - not the first tool use in this message
```

**Backward Compatibility:**

The time-based deduplication (120-second window) remains as a safety net for edge cases, but the primary deduplication now happens via tool_use_id comparison.

### Fix: Message Isolation for PreToolUse Hook

**Date:** November 21, 2025

**Problem:** The PreToolUse hook was extracting text from previous messages instead of the current message. When a user submitted a new prompt, the hook would fire before the transcript was fully updated, causing it to read text from the assistant's previous response instead of the current message.

**Root Cause:** The hook searched for "the last assistant message" without verifying it was the same message containing the current tool_use_id. This caused it to read text from previous messages.

**Example of the Problem:**

1. Claude responds: "I've added .onnx files to gitignore..." (Message A)
2. User asks: "Can you review the logs?" (Message B)
3. PreToolUse hook fires for Message B's tool use
4. Hook extracts text from Message A (previous message)
5. User hears: "I've added .onnx files to gitignore..." (wrong message)

**Solution:** Modified the PreToolUse hook to verify the extracted text comes from the message containing the current tool_use_id.

**Implementation:**

```bash
# Extract text from the SPECIFIC message that contains the current tool_use_id
claude_response=$(tac "$transcript_path" | while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "assistant"' >/dev/null 2>&1; then
    # Check if this message contains the current tool_use_id
    tool_ids=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use") | .id' 2>/dev/null)

    # Only process this message if it contains the current tool_use_id
    if echo "$tool_ids" | grep -q "$current_tool_use_id"; then
      # Extract text only from THIS message
      ...
    fi
  fi
done | head -c 5000)
```

**Benefits:**
- **Message isolation**: Only reads text from the current message
- **No cross-message contamination**: Won't read text from previous responses
- **Accurate narration**: Users hear commentary for the current action only
- **Proper context**: Text matches the tools being executed

**User Experience:**

Before the fix:
1. Claude responds: "I've updated the hooks..." (Message A)
2. User asks: "Check the logs" (Message B)
3. User hears: "I've updated the hooks..." (from Message A, wrong)

After the fix:
1. Claude responds: "I've updated the hooks..." (Message A)
2. User asks: "Check the logs" (Message B with tool but no intro text)
3. User hears: (nothing, because Message B has no text before tools)

### Fix: Content-Based Deduplication for Auto-Approved Edits

**Date:** November 21, 2025

**Problem:** When users select "allow all edits for this session" or similar auto-approval settings, Claude sends multiple separate messages (one per edit), each containing the same introductory text. The PreToolUse hook fires for each message's first tool use, causing the same text to be read aloud repeatedly.

**Root Cause:** The previous deduplication logic only checked the message ID (`first_tool_use_id`). When Claude sends multiple messages with the same text but different IDs, each message triggers playback.

**Example of the Problem:**

User approves all edits, Claude responds:
- Message 1: "I'll help you make those files better." + Edit(file1)
- Message 2: "I'll help you make those files better." + Edit(file2)
- Message 3: "I'll help you make those files better." + Edit(file3)

User heard the same text 3 times.

**Solution:** Added content-based deduplication using MD5 hash of the text content.

**Implementation:**

Modified `~/.claude/hooks/tts-pretooluse-hook.sh` to:
1. Compute MD5 hash of the extracted text
2. Check if the same hash was played within the last 60 seconds
3. Skip playback if it's a duplicate based on content, not just message ID

```bash
# Content-based deduplication: compute hash of the text
text_hash=$(echo "$claude_response" | md5sum | awk '{print $1}')
last_hash_file="/tmp/kokoro-pretool-last-hash.txt"
last_hash=$(cat "$last_hash_file" 2>/dev/null)
last_hash_time_file="/tmp/kokoro-pretool-last-time.txt"
last_hash_time=$(cat "$last_hash_time_file" 2>/dev/null)
current_time=$(date +%s)

# If we played this exact text within the last 60 seconds, skip
if [ "$text_hash" = "$last_hash" ]; then
  time_diff=$((current_time - last_hash_time))
  if [ $time_diff -lt 60 ]; then
    echo "[$(date)] Skipping - same text played $time_diff seconds ago" >> /tmp/kokoro-hook.log
    exit 0
  fi
fi
```

**Benefits:**
- **No duplicate audio**: Same text is only played once within 60 seconds, regardless of how many messages contain it
- **Smart expiry**: After 60 seconds, the same text can be played again (useful for repeated operations)
- **Works with auto-approval**: Handles the "allow all edits" scenario gracefully
- **Content-aware**: Deduplication based on actual text content, not arbitrary IDs

**User Experience:**

Before the fix (with auto-approval):
1. Claude sends: "I'll help you..." + Edit(file1)
2. User hears: "I'll help you..."
3. Claude sends: "I'll help you..." + Edit(file2)
4. User hears: "I'll help you..." (duplicate)
5. Claude sends: "I'll help you..." + Edit(file3)
6. User hears: "I'll help you..." (duplicate)

After the fix (with auto-approval):
1. Claude sends: "I'll help you..." + Edit(file1)
2. User hears: "I'll help you..."
3. Claude sends: "I'll help you..." + Edit(file2)
4. User hears: (nothing - duplicate detected)
5. Claude sends: "I'll help you..." + Edit(file3)
6. User hears: (nothing - duplicate detected)

### Fix: Cross-Hook Repetition with TTS_SUMMARY

**Date:** November 21, 2025

**Problem:** When Claude responds with both text and TTS_SUMMARY markers followed by tool uses, both PreToolUse and Stop hooks would play content from the same message, causing repetition. Users heard the full response via PreToolUse, then heard the summary again via Stop.

**Example of the Problem:**

Claude responds:

```text
Changes Complete

I've updated the installer to automatically configure the global CLAUDE.md file...

<!-- TTS_SUMMARY
I updated the installer to add TTS instructions to CLAUDE.md.
TTS_SUMMARY -->
```

User heard:
1. PreToolUse: "Changes Complete - I've updated the installer..." (full text)
2. Stop: "I updated the installer to add TTS instructions..." (summary)

**Root Cause:** PreToolUse hook extracted text before tool uses without checking for TTS_SUMMARY markers. It played the full content, unaware that Stop hook would later play the summary from the same message.

**Solution:** Added TTS_SUMMARY detection to PreToolUse hook. When detected, PreToolUse skips playback entirely and lets Stop hook handle the TTS_SUMMARY extraction.

**Implementation:**

Modified `hooks/tts-pretooluse-hook.sh` and `install.sh` to add detection after text extraction:

```bash
# Check if response contains TTS_SUMMARY marker
# If it does, skip playback - let the Stop hook handle TTS_SUMMARY extraction
if echo "$claude_response" | grep -q "<!-- TTS_SUMMARY"; then
  echo "[$(date)] Skipping - message contains TTS_SUMMARY, let Stop hook handle it" >> /tmp/kokoro-hook.log
  exit 0
fi
```

**Benefits:**
- **No duplicate playback**: Messages with TTS_SUMMARY only play via Stop hook (summary only)
- **Clean separation**: PreToolUse handles commentary, Stop handles summaries
- **Cross-hook coordination**: Both hooks work together without overlap
- **Maintains intended behavior**: Messages without TTS_SUMMARY still play via PreToolUse

**User Experience:**

After the fix:
1. Messages with TTS_SUMMARY → PreToolUse skips, Stop plays summary only
2. Messages without TTS_SUMMARY → PreToolUse plays full text
3. No repetition or duplicate playback

### Enhancement: Audio Ducking (macOS)

**Date:** January 2026

**Feature:** Added automatic audio ducking that lowers Apple Music volume when TTS speaks, then restores it - similar to how Google Maps works in CarPlay.

**Implementation:**

1. **New Helper Script:** `scripts/audio-duck.sh`
   - Controls Apple Music volume via AppleScript
   - Supports duck, restore, and duck-and-wait operations
   - Configurable duck level and minimum volume

2. **Hook Integration:**
   - All TTS hooks (Stop, PreToolUse, Interrupt) updated to support ducking
   - Volume is ducked before TTS starts
   - Background process monitors TTS and restores volume when complete
   - Interrupt hook restores volume if TTS is killed

**Configuration:**

```json
{
  "env": {
    "AUDIO_DUCK_ENABLED": "true",
    "DUCK_LEVEL": "5"
  }
}
```

**Technical Details:**

- Uses AppleScript to control Apple Music's internal volume (not system volume)
- TTS audio remains at full volume while music is ducked
- Original volume is saved to `/tmp/kokoro-music-volumes.txt` and restored after TTS
- Handles edge cases: app not running, interrupted TTS, multiple rapid TTS calls

**macOS Compatibility Fix:**

The hook scripts originally used `tac` (GNU coreutils) to reverse file contents, which is not available on macOS. Fixed by replacing `tac` with `tail -r` (macOS native equivalent).

## References

- **Claude Code Hooks Documentation**: See `.claude/` directory and Claude Code docs
- **Kokoro TTS**: Command-line TTS tool using Kokoro v1.0 ONNX model
- **Hook Script**: `~/.claude/hooks/tts-stop-hook.sh`
- **Global Settings**: `~/.claude/settings.json`
- **Previous Hook (reference)**: `~/.claude/hooks/tts-stop-hook.sh` (disabled)
- **TTS_SUMMARY Modification**: `docs/TTS_SUMMARY_FORMAT.md`
