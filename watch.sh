#!/bin/bash

# watch.sh
if ! command -v cargo-watch &> /dev/null; then
    echo "Installing cargo-watch..."
    cargo install --force cargo-watch
fi

# Set C++ standard to C++17 for dependencies that compile C++ code
# This is required for tectonic_xetex_layout which uses ICU headers
# that require C++17 features (auto template parameters)
export CXXFLAGS="-std=c++17"

# Watch for changes in src directory and restart server
cargo watch -x 'run --bin lensisku -- --jobs 1' -w src -w Cargo.toml