#!/bin/bash
# Wrapper for satty to work with grimblast
# Converts positional argument to --filename flag

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

exec satty --filename "$1"
