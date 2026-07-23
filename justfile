# justfile — Perch command runner
# Requires Homebrew tools: brew install xcbeautify swift-format lefthook
# Usage: just <command>

# Default: list available commands
default:
    @just --list

# Verify dev tools are available
setup:
    @command -v xcbeautify >/dev/null 2>&1 || (echo "Error: xcbeautify not found. Run 'brew install xcbeautify'." && exit 1)
    @command -v swift-format >/dev/null 2>&1 || (echo "Error: swift-format not found. Run 'brew install swift-format'." && exit 1)
    @command -v lefthook >/dev/null 2>&1 || (echo "Error: lefthook not found. Run 'brew install lefthook'." && exit 1)
    lefthook install
    @echo "Dev environment ready. Git hooks installed."

# Build the app (Debug)
build:
    #!/bin/bash
    set -o pipefail
    xcodebuild \
        -scheme perch \
        -configuration Debug \
        -destination 'platform=macOS' \
        build \
        2>&1 | xcbeautify

# Run all unit tests
test:
    #!/bin/bash
    set -o pipefail
    xcodebuild \
        -scheme perch \
        -configuration Debug \
        -destination 'platform=macOS' \
        test \
        2>&1 | xcbeautify

# Format Swift files in-place
format:
    swift-format format --recursive --in-place perch/ perchTests/

# Lint Swift files (check only, no modification)
lint:
    swift-format lint --recursive perch/ perchTests/

# Build for Release
release:
    #!/bin/bash
    set -o pipefail
    xcodebuild \
        -scheme perch \
        -configuration Release \
        -destination 'platform=macOS' \
        build \
        2>&1 | xcbeautify

# Clean DerivedData
clean:
    #!/bin/bash
    set -o pipefail
    xcodebuild -scheme perch clean 2>&1 | xcbeautify
    rm -rf ~/Library/Developer/Xcode/DerivedData/perch-*
    echo "Cleaned DerivedData for perch"

# Build and launch Perch inline (Xcode ⌘R equivalent). Ctrl+C stops the app.
run:
    bash scripts/run.sh

# Same as `run` but Release configuration
run-release:
    CONFIG=Release bash scripts/run.sh
