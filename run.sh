#!/usr/bin/env bash
set -euo pipefail

nix run github:utensils/comfyui-nix#cuda -- \
  --base-directory /persist/comfyui \
  --enable-manager
