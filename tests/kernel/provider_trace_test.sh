#!/usr/bin/env bash

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}


assert_equals() {

    local expected="${1:-}"
    local actual="${2:-}"
    local message="${3:-Values are not equal.}"

    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s\n' "$message" >&2
        printf 'Expected: %s\n' "$expected" >&2
        printf 'Actual:   %s\n' "$actual" >&2
        exit 1
    fi
}


stoleus_kernel_initialize


assert_equals \
    "true" \
    "${STOLEUS_PROVIDER_TRACE_INITIALIZED:-false}" \
    "Provider Trace should be initialized."


assert_equals \
    "0" \
    "$(stoleus_provider_trace_get_count)" \
    "Provider Trace should initially be empty."


stoleus_provider_trace_append \
    "capability" \
    "package-management" \
    "apt-provider" \
    "true" \
    "os-family=debian" \
    "matched" \
    "100" \
    "selected" \
    "highest-priority eligible provider"


assert_equals \
    "1" \
    "$(stoleus_provider_trace_get_count)" \
    "Provider Trace count is incorrect."


trace_key="capability:package-management@apt-provider#0"


assert_equals \
    "selected" \
    "$(stoleus_provider_trace_get_field \
        "$trace_key" \
        "decision")" \
    "Provider Trace decision is incorrect."


assert_equals \
    "matched" \
    "$(stoleus_provider_trace_get_field \
        "$trace_key" \
        "condition-result")" \
    "Provider Trace condition result is incorrect."


assert_equals \
    "100" \
    "$(stoleus_provider_trace_get_field \
        "$trace_key" \
        "priority")" \
    "Provider Trace priority is incorrect."


stoleus_provider_trace_reset


assert_equals \
    "0" \
    "$(stoleus_provider_trace_get_count)" \
    "Provider Trace reset failed."


printf '%s\n' \
    "PASS: Provider Selection Trace tests completed successfully."
