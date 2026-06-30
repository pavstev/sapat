#!/usr/bin/env bash
# Clean-slate precondition for installing Šapat. Removes any prior install and stops
# anything left running so install.sh starts fresh. Idempotent — safe to run anytime.
#
#   ./scripts/cleanup.sh           quit + uninstall the app, clear local build artifacts
#   ./scripts/cleanup.sh --purge   ALSO delete saved history + the memory index + downloaded models
#
# Inference runs in-process (MLX), so there is no sidecar server/daemon to tear down. Model
# weights and the memory index live under ~/Library/Application Support/Sapat (cleared by
# --purge); the WhisperKit cache under ~/Documents/huggingface is cleared too.
set -euo pipefail

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

echo "▶ Quitting Šapat if running…"
osascript -e 'tell application "Sapat" to quit' >/dev/null 2>&1 || true
pkill -x Sapat 2>/dev/null || true

echo "▶ Removing installed app…"
rm -rf "/Applications/Sapat.app" "$HOME/Applications/Sapat.app"

if [[ -f Package.swift ]]; then
  echo "▶ Clearing local build artifacts…"
  rm -rf .build Sapat.app Sapat.xcodeproj
  rm -rf ./*.iconset 2>/dev/null || true
fi

if [[ $PURGE -eq 1 ]]; then
  echo "▶ Purging saved history, memory index, and downloaded models…"
  # Covers history.json, memory.sqlite, Recordings/, and Models/ (reasoner weights).
  rm -rf "$HOME/Library/Application Support/Sapat"
  # WhisperKit's own model cache.
  rm -rf "$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3"
fi

echo "✓ Clean slate."
