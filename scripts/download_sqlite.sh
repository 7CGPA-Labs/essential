#!/bin/bash
# Download SQLite3 amalgamation + sqlite-vec extension for Kingdom AI Server
# Run from project root: bash scripts/download_sqlite.sh

set -e

SQLITE_VER="3460000"  # 3.46.0
SQLITE_VEC_VER="0.1.6"
CPP_DIR="android/app/src/main/cpp/sqlite"

mkdir -p "$CPP_DIR"

echo "[1/3] Downloading SQLite3 amalgamation..."
curl -L "https://www.sqlite.org/2024/sqlite-amalgamation-${SQLITE_VER}.zip" -o /tmp/sqlite.zip
unzip -j /tmp/sqlite.zip "*.c" "*.h" -d "$CPP_DIR"

echo "[2/3] Downloading sqlite-vec extension..."
curl -L "https://github.com/asg017/sqlite-vec/releases/download/v${SQLITE_VEC_VER}/sqlite-vec-${SQLITE_VEC_VER}-loadable-linux-x86_64.tar.gz" -o /tmp/sqlite_vec.tar.gz
# Actually get the source header+c directly:
curl -L "https://github.com/asg017/sqlite-vec/releases/download/v${SQLITE_VEC_VER}/sqlite-vec-${SQLITE_VEC_VER}-amalgamation.tar.gz" -o /tmp/sqlite_vec_src.tar.gz
tar -xzf /tmp/sqlite_vec_src.tar.gz -C /tmp/
cp /tmp/sqlite_vec.c "$CPP_DIR/" 2>/dev/null || true
cp /tmp/sqlite_vec.h "$CPP_DIR/" 2>/dev/null || true

echo "[3/3] Done! SQLite files in $CPP_DIR:"
ls -lh "$CPP_DIR"
echo ""
echo "Now rebuild: cd android && ./gradlew assembleDebug"
