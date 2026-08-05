#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel API Registry Tests
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


if [[ "${STOLEUS_API_INITIALIZED:-false}" != "true" ]]; then
    fail "API Registry should be initialized by the kernel."
fi


if [[ "${STOLEUS_API_VALIDATED:-false}" != "true" ]]; then
    fail "API Registry should be validated during initialization."
fi


if ! stoleus_api_exists "stoleus_registry_get_field"; then
    fail "Registry get-field API should be registered."
fi


assert_equals \
    "registry" \
    "$(stoleus_api_get_field \
        "stoleus_registry_get_field" \
        "subsystem")" \
    "Registry API subsystem ownership is incorrect."


assert_equals \
    "public" \
    "$(stoleus_api_get_field \
        "stoleus_registry_get_field" \
        "visibility")" \
    "Registry get-field should be public."


assert_equals \
    "dsl" \
    "$(stoleus_api_get_field \
        "stoleus_plugin_begin" \
        "visibility")" \
    "Plugin begin should be classified as DSL."


assert_equals \
    "internal" \
    "$(stoleus_api_get_field \
        "stoleus_lifecycle_invoke" \
        "visibility")" \
    "Lifecycle invoke should be internal."


public_count="$(
    stoleus_api_get_count "public"
)"

dsl_count="$(
    stoleus_api_get_count "dsl"
)"

internal_count="$(
    stoleus_api_get_count "internal"
)"

total_count="$(
    stoleus_api_get_count
)"


if (( public_count <= 0 )); then
    fail "API Registry should contain public functions."
fi


if (( dsl_count <= 0 )); then
    fail "API Registry should contain DSL functions."
fi


if (( internal_count <= 0 )); then
    fail "API Registry should contain internal functions."
fi


assert_equals \
    "$total_count" \
    "$((public_count + dsl_count + internal_count))" \
    "API classification counts do not equal the total count."


TEST_TEMP_ROOT="$(
    mktemp -d
)"


snapshot_path="${TEST_TEMP_ROOT}/kernel-api.tsv"

stoleus_api_write_snapshot \
    "$snapshot_path"


if [[ ! -s "$snapshot_path" ]]; then
    fail "API snapshot should be generated."
fi


if grep -q \
    $'\tstoleus_lifecycle_invoke\tinternal\t' \
    "$snapshot_path"; then

    fail "Internal APIs must not appear in compatibility snapshots."
fi


if ! grep -q \
    $'\tstoleus_plugin_begin\tdsl\tstable\t' \
    "$snapshot_path"; then

    fail "Plugin DSL should appear in the compatibility snapshot."
fi


if ! grep -q \
    $'\tstoleus_kernel_bootstrap\tpublic\tstable\t' \
    "$snapshot_path"; then

    fail "Kernel bootstrap should appear in the compatibility snapshot."
fi


set +e

stoleus_api_register \
    "registry" \
    "stoleus_registry_get_field" \
    "public" \
    "stable" \
    "kernel/registry/registry.sh" \
    >/dev/null 2>&1

duplicate_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_exit_code" \
    "Duplicate API registration should return conflict code 8."


printf '%s\n' \
    "PASS: Kernel API Registry tests completed successfully."
