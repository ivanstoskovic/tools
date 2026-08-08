#!/usr/bin/env bash

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"


fail() {

    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}


violations="$(
    grep -RnE \
      '^[[:space:]]*set[[:space:]]+[+-]e([[:space:]]|$)' \
      "${PROJECT_ROOT}/kernel" \
      || true
)"


if [[ -n "$violations" ]]; then

    printf '%s\n' \
        "ERROR: Kernel library code must not toggle errexit with 'set +e' or 'set -e'." \
        >&2

    printf '%s\n' "$violations" >&2

    fail \
        "Kernel functions must preserve caller shell-option state."
fi


printf '%s\n' \
    "PASS: Kernel shell-option safety tests completed successfully."
