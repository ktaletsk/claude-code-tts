#!/bin/bash
# Serialized kokoro-tts player, shared by every tts-*-hook script.
#
# Problem it solves: each hook used to launch kokoro-tts directly, so two
# concurrent Claude sessions produced two overlapping audio streams and neither
# was understandable. This wrapper funnels all playback through a single
# system-wide lock, so speech plays one utterance at a time.
#
# Usage: tts-play.sh <text-file> [voice]
#
# Returns immediately: the wait-then-play happens in a detached background
# process, because Claude Code kills hooks after 5-10 seconds. That background
# process is this same script re-invoked with --play-now, rather than a
# ( ... ) & subshell: under bash 3.2 a subshell's $$ is still the PARENT's pid,
# so the lock owner recorded there looked dead the moment the hook exited and
# every waiter happily cleared the lock and spoke over the others.

PLAY_NOW=0
START_GEN=""
if [ "$1" = "--play-now" ]; then
  PLAY_NOW=1
  START_GEN="$2"
  shift 2
fi

TEXT_FILE="$1"
VOICE="${2:-${KOKORO_VOICE:-af_sky}}"

LOG_FILE="${KOKORO_LOG:-/tmp/kokoro-hook.log}"
LOCK_DIR="${KOKORO_LOCK_DIR:-/tmp/kokoro-tts.lock}"
GEN_FILE="${KOKORO_GEN_FILE:-/tmp/kokoro-tts-generation}"
MAX_WAIT_SECONDS="${KOKORO_MAX_WAIT_SECONDS:-300}"
# A lock dir with no pid file is a player between mkdir and writing its pid;
# after this long it is one that died there, and the lock is abandoned.
NO_PID_GRACE_SECONDS="${KOKORO_NO_PID_GRACE_SECONDS:-5}"
KOKORO_BIN="${KOKORO_BIN:-kokoro-tts}"

AUDIO_DUCK_ENABLED="${AUDIO_DUCK_ENABLED:-true}"
AUDIO_DUCK_SCRIPT="${AUDIO_DUCK_SCRIPT:-__CLAUDE_TTS_PROJECT_DIR__/scripts/audio-duck.sh}"

log() {
  echo "[$(date)] [tts-play] $1" >> "$LOG_FILE"
}

if [ ! -f "$TEXT_FILE" ]; then
  log "No text file to speak: $TEXT_FILE"
  exit 0
fi

# Generation token: tts-cancel.sh bumps it to cancel whatever is queued. A
# player that sees a different token than the one it was queued with drops its
# utterance instead of speaking stale text.
current_gen() { cat "$GEN_FILE" 2>/dev/null; }

# First invocation: detach and return, so the calling hook can exit immediately.
# The token is read HERE, at queue time, and handed to the detached player: if
# the player read it itself, a cancel landing before it started would become
# its starting token, and the stale utterance would play anyway.
if [ "$PLAY_NOW" = "0" ]; then
  nohup "$0" --play-now "$(current_gen)" "$TEXT_FILE" "$VOICE" </dev/null >/dev/null 2>&1 &
  exit 0
fi

start_gen="$START_GEN"

drop_if_cancelled() {
  if [ "$(current_gen)" != "$start_gen" ]; then
    log "Cancelled $1 - dropping utterance"
    rm -f "$TEXT_FILE"
    return 0
  fi
  return 1
}

dir_age_seconds() {
  local mtime
  mtime=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
  echo $(( $(date +%s) - mtime ))
}

waited_tenths=0
max_tenths=$((MAX_WAIT_SECONDS * 10))
acquired=0

while :; do
  # Cancelled while queued? Checked BEFORE trying the lock: cancel bumps the
  # token and then kills the player, whose exit frees the lock - a waiter that
  # tried the lock first could grab it in that gap and speak stale text.
  drop_if_cancelled "while waiting for the lock" && exit 0

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    acquired=1
    break
  fi

  # Clear a lock left behind by a process that died without releasing it.
  holder=$(cat "$LOCK_DIR/pid" 2>/dev/null)
  if [ -z "$holder" ] && [ -d "$LOCK_DIR" ]; then
    age=$(dir_age_seconds "$LOCK_DIR")
    if [ -n "$age" ] && [ "$age" -ge "$NO_PID_GRACE_SECONDS" ]; then
      log "Clearing abandoned lock with no pid (${age}s old)"
      rm -rf "$LOCK_DIR"
      continue
    fi
  fi
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    sleep 0.2
    still=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ "$still" = "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
      log "Clearing stale lock held by dead pid $holder"
      rm -rf "$LOCK_DIR"
    fi
    waited_tenths=$((waited_tenths + 2))
    continue
  fi

  if [ "$waited_tenths" -ge "$max_tenths" ]; then
    log "WARNING: waited ${MAX_WAIT_SECONDS}s for kokoro-tts to finish - dropping this utterance"
    rm -f "$TEXT_FILE"
    exit 0
  fi

  sleep 0.2
  waited_tenths=$((waited_tenths + 2))
done

if [ "$acquired" = "1" ] && [ "$waited_tenths" -gt 0 ]; then
  log "Acquired TTS lock after $((waited_tenths / 10))s of waiting"
fi

# Release the lock however we leave. On INT/TERM, stop kokoro-tts and exit:
# a bash trap that just returns lets the script carry on, so it released the
# lock while kokoro-tts kept speaking (or went on to start it without the lock).
kokoro_pid=""
trap 'rm -rf "$LOCK_DIR"; rm -f "$TEXT_FILE"' EXIT
trap '[ -n "$kokoro_pid" ] && kill -9 "$kokoro_pid" 2>/dev/null; exit 143' INT TERM

# A cancel can land between the last check in the loop and taking the lock.
drop_if_cancelled "just before playback" && exit 0

if [ "$AUDIO_DUCK_ENABLED" = "true" ] && [ -x "$AUDIO_DUCK_SCRIPT" ]; then
  log "Ducking audio before TTS"
  "$AUDIO_DUCK_SCRIPT" duck
fi

# The lock is held for the whole playback, which is what makes concurrent hooks
# serial rather than simultaneous. kokoro-tts's pid goes in the lock so that
# tts-cancel.sh kills exactly this process instead of pattern-matching.
"$KOKORO_BIN" "$TEXT_FILE" --voice "$VOICE" --stream \
  --model "MODEL_PATH_PLACEHOLDER/kokoro-v1.0.onnx" \
  --voices "MODEL_PATH_PLACEHOLDER/voices-v1.0.bin" >>"$LOG_FILE" 2>&1 &
kokoro_pid=$!
echo "$kokoro_pid" > "$LOCK_DIR/kokoro-pid"
# Cancel bumps the token THEN reads kokoro-pid; we wrote kokoro-pid THEN read
# the token. So a racing cancel either finds the pid or is seen here.
if drop_if_cancelled "as playback started"; then
  kill -9 "$kokoro_pid" 2>/dev/null
fi
wait "$kokoro_pid"
log "kokoro-tts finished"

if [ "$AUDIO_DUCK_ENABLED" = "true" ] && [ -x "$AUDIO_DUCK_SCRIPT" ]; then
  log "TTS finished, restoring audio"
  "$AUDIO_DUCK_SCRIPT" restore
fi

exit 0
