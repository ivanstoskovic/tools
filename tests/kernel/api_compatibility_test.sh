#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel API Compatibility Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


TEST_TEMP_ROOT=""


cleanup() {

    if [[ -n "$TEST_TEMP_ROOT" && -d "$TEST_TEMP_ROOT" ]]; then
        rm -rf "$TEST_TEMP_ROOT"
    fi
}


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


trap cleanup EXIT


stoleus_kernel_initialize


baseline_path="${PROJECT_ROOT}/contracts/kernel-api.tsv"


if [[ ! -f "$baseline_path" ]]; then
    fail "Committed kernel API baseline is missing."
fi


# ==============================================================================
# Current live API must exactly match the committed baseline.
# ==============================================================================

stoleus_api_compare_snapshot \
    "$baseline_path"


# ==============================================================================
# Create isolated compatibility fixtures.
# ==============================================================================

TEST_TEMP_ROOT="$(
    mktemp -d
)"


live_snapshot="${TEST_TEMP_ROOT}/live.tsv"

stoleus_api_write_snapshot \
    "$live_snapshot"


# ==============================================================================
# Removed API detection.
# ==============================================================================

removed_snapshot="${TEST_TEMP_ROOT}/removed.tsv"

{
    head -n 1 "$live_snapshot"

    tail -n +2 "$live_snapshot" |
        grep -v $'\tstoleus_kernel_bootstrap\t'

} > "$removed_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$removed_snapshot" \
    >/dev/null 2>&1

removed_exit_code=$?

set -e


assert_equals \
    "8" \
    "$removed_exit_code" \
    "Removed API should produce compatibility conflict code 8."


# ==============================================================================
# Newly added API detection.
# ==============================================================================

added_snapshot="${TEST_TEMP_ROOT}/added.tsv"

cp "$live_snapshot" "$added_snapshot"

printf '%s\n' \
    $'kernel\tstoleus_kernel_future_api\tpublic\texperimental\tkernel/kernel.sh' \
    >> "$added_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$added_snapshot" \
    >/dev/null 2>&1

added_exit_code=$?

set -e


assert_equals \
    "8" \
    "$added_exit_code" \
    "Unaccepted API addition should produce compatibility conflict code 8."


# ==============================================================================
# Ownership change detection.
# ==============================================================================

ownership_snapshot="${TEST_TEMP_ROOT}/ownership.tsv"

awk -F '\t' '
BEGIN {
    OFS = "\t"
}

$2 == "stoleus_registry_get_field" {
    $1 = "plugin"
}

{
    print
}
' "$live_snapshot" > "$ownership_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$ownership_snapshot" \
    >/dev/null 2>&1

ownership_exit_code=$?

set -e


assert_equals \
    "8" \
    "$ownership_exit_code" \
    "Changed subsystem ownership should produce conflict code 8."


# ==============================================================================
# Visibility change detection.
# ==============================================================================

visibility_snapshot="${TEST_TEMP_ROOT}/visibility.tsv"

awk -F '\t' '
BEGIN {
    OFS = "\t"
}

$2 == "stoleus_plugin_begin" {
    $3 = "public"
}

{
    print
}
' "$live_snapshot" > "$visibility_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$visibility_snapshot" \
    >/dev/null 2>&1

visibility_exit_code=$?

set -e


assert_equals \
    "8" \
    "$visibility_exit_code" \
    "Changed API visibility should produce conflict code 8."


# ==============================================================================
# Stability change detection.
# ==============================================================================

stability_snapshot="${TEST_TEMP_ROOT}/stability.tsv"

awk -F '\t' '
BEGIN {
    OFS = "\t"
}

$2 == "stoleus_kernel_bootstrap" {
    $4 = "experimental"
}

{
    print
}
' "$live_snapshot" > "$stability_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$stability_snapshot" \
    >/dev/null 2>&1

stability_exit_code=$?

set -e


assert_equals \
    "8" \
    "$stability_exit_code" \
    "Changed API stability should produce conflict code 8."


# ==============================================================================
# Owner-file change detection.
# ==============================================================================

owner_snapshot="${TEST_TEMP_ROOT}/owner.tsv"

awk -F '\t' '
BEGIN {
    OFS = "\t"
}

$2 == "stoleus_kernel_bootstrap" {
    $5 = "kernel/runtime/runtime.sh"
}

{
    print
}
' "$live_snapshot" > "$owner_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$owner_snapshot" \
    >/dev/null 2>&1

owner_exit_code=$?

set -e


assert_equals \
    "8" \
    "$owner_exit_code" \
    "Changed API owner should produce conflict code 8."


# ==============================================================================
# Malformed baseline detection.
# ==============================================================================

malformed_snapshot="${TEST_TEMP_ROOT}/malformed.tsv"

printf '%s\n' \
    "invalid-header" \
    > "$malformed_snapshot"


set +e

stoleus_api_compare_snapshot \
    "$malformed_snapshot" \
    >/dev/null 2>&1

malformed_exit_code=$?

set -e


assert_equals \
    "6" \
    "$malformed_exit_code" \
    "Malformed API baseline should return configuration code 6."


# ==============================================================================
# Missing baseline detection.
# ==============================================================================

set +e

stoleus_api_compare_snapshot \
    "${TEST_TEMP_ROOT}/missing.tsv" \
    >/dev/null 2>&1

missing_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_exit_code" \
    "Missing API baseline should return configuration code 6."


printf '%s\n' \
    "PASS: Kernel API compatibility tests completed successfully."
