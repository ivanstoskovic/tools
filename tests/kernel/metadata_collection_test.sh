#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Generic Metadata Collection Tests
# ==============================================================================

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
stoleus_metadata_reset


# ==============================================================================
# Create a Contract-like collection.
# ==============================================================================

stoleus_metadata_collection_create \
    "contracts" \
    "id" \
    "id" \
    "version" \
    "description" \
    "operations"


assert_equals \
    "id,version,description,operations" \
    "$(stoleus_metadata_collection_get_schema "contracts")" \
    "Contract collection schema is incorrect."


assert_equals \
    "0" \
    "$(stoleus_metadata_collection_get_count "contracts")" \
    "New collection should be empty."


# ==============================================================================
# Append rows.
# ==============================================================================

stoleus_metadata_collection_append \
    "contracts" \
    "package-manager" \
    "1.0.0" \
    "Installs and removes packages." \
    "install,remove,exists"


stoleus_metadata_collection_append \
    "contracts" \
    "service-manager" \
    "1.0.0" \
    "Controls operating-system services." \
    "enable,start,is-active"


assert_equals \
    "2" \
    "$(stoleus_metadata_collection_get_count "contracts")" \
    "Contract collection should contain two rows."


if ! stoleus_metadata_collection_contains \
    "contracts" \
    "package-manager"; then

    fail "Contract collection should contain package-manager."
fi


assert_equals \
    "0" \
    "$(stoleus_metadata_collection_get_index "contracts" "package-manager")" \
    "Package-manager row index is incorrect."


assert_equals \
    "1" \
    "$(stoleus_metadata_collection_get_index "contracts" "service-manager")" \
    "Service-manager row index is incorrect."


assert_equals \
    "Installs and removes packages." \
    "$(stoleus_metadata_collection_get_field \
        "contracts" \
        "package-manager" \
        "description")" \
    "Metadata field lookup is incorrect."


# ==============================================================================
# Complete and selected-field listing.
# ==============================================================================

expected_complete_list="$(
    printf '%s\n' \
        $'package-manager\t1.0.0\tInstalls and removes packages.\tinstall,remove,exists' \
        $'service-manager\t1.0.0\tControls operating-system services.\tenable,start,is-active'
)"


assert_equals \
    "$expected_complete_list" \
    "$(stoleus_metadata_collection_list "contracts")" \
    "Complete metadata listing is incorrect."


expected_selected_list="$(
    printf '%s\n' \
        $'package-manager\t1.0.0' \
        $'service-manager\t1.0.0'
)"


assert_equals \
    "$expected_selected_list" \
    "$(stoleus_metadata_collection_list \
        "contracts" \
        "id" \
        "version")" \
    "Selected-field metadata listing is incorrect."


# ==============================================================================
# Duplicate keys are rejected.
# ==============================================================================

set +e

stoleus_metadata_collection_append \
    "contracts" \
    "package-manager" \
    "2.0.0" \
    "Duplicate." \
    "install" \
    >/dev/null 2>&1

duplicate_key_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_key_exit_code" \
    "Duplicate metadata key should return conflict code 8."


# ==============================================================================
# Incorrect value counts are rejected.
# ==============================================================================

set +e

stoleus_metadata_collection_append \
    "contracts" \
    "incomplete" \
    "1.0.0" \
    >/dev/null 2>&1

value_count_exit_code=$?

set -e


assert_equals \
    "2" \
    "$value_count_exit_code" \
    "Incorrect metadata value count should return usage code 2."


# ==============================================================================
# Freeze and immutability.
# ==============================================================================

stoleus_metadata_collection_freeze \
    "contracts"


if ! stoleus_metadata_collection_is_frozen "contracts"; then
    fail "Contract collection should be frozen."
fi


set +e

stoleus_metadata_collection_append \
    "contracts" \
    "filesystem" \
    "1.0.0" \
    "Filesystem operations." \
    "write,read" \
    >/dev/null 2>&1

frozen_append_exit_code=$?

set -e


assert_equals \
    "8" \
    "$frozen_append_exit_code" \
    "Appending to a frozen collection should return conflict code 8."


# ==============================================================================
# Multiple collections remain isolated.
# ==============================================================================

stoleus_metadata_collection_create \
    "commands" \
    "id" \
    "id" \
    "description"


stoleus_metadata_collection_append \
    "commands" \
    "setup" \
    "Execute setup lifecycle operations."


assert_equals \
    "1" \
    "$(stoleus_metadata_collection_get_count "commands")" \
    "Command collection should contain one row."


assert_equals \
    "2" \
    "$(stoleus_metadata_collection_get_count "contracts")" \
    "Creating another collection must not modify contracts."


# ==============================================================================
# Unknown fields and keys.
# ==============================================================================

set +e

stoleus_metadata_collection_get_field \
    "contracts" \
    "package-manager" \
    "unknown-field" \
    >/dev/null 2>&1

unknown_field_exit_code=$?


stoleus_metadata_collection_get_field \
    "contracts" \
    "unknown-contract" \
    "description" \
    >/dev/null 2>&1

unknown_key_exit_code=$?

set -e


assert_equals \
    "2" \
    "$unknown_field_exit_code" \
    "Unknown metadata field should return usage code 2."


assert_equals \
    "6" \
    "$unknown_key_exit_code" \
    "Unknown metadata key should return configuration code 6."


# ==============================================================================
# Collection reset.
# ==============================================================================

stoleus_metadata_collection_reset \
    "commands"


if stoleus_metadata_collection_exists "commands"; then
    fail "Reset collection should no longer exist."
fi


if ! stoleus_metadata_collection_exists "contracts"; then
    fail "Resetting commands must not remove contracts."
fi


printf '%s\n' \
    "PASS: Generic Metadata Collection tests completed successfully."
