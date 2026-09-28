#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Command Line Tools ship Swift Testing but SwiftPM does not always add their
# framework search path. Full Xcode runners already discover it automatically.
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [ -d "$FRAMEWORKS/Testing.framework" ]; then
    swift test --disable-xctest -Xswiftc -DLORO_RELEASE_REQUIRES_FOUNDATION_MODELS \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$(dirname "$FRAMEWORKS")/usr/lib"
else
    swift test --disable-xctest -Xswiftc -DLORO_RELEASE_REQUIRES_FOUNDATION_MODELS
fi
