#!/bin/bash
# Check for emojis in files

if grep -E "✅|❌|⚠️|🚀|💡|📝|🎯|🔥|⭐|🎉|👍|👎" "$@"; then
    echo "Error: Emojis found in files. Please remove them."
    exit 1
fi

exit 0
