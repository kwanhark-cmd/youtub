#!/usr/bin/env bash
# 커밋 전 검사: 하나라도 실패하면 멈춘다.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH=/opt/flutter/bin:$PATH
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
