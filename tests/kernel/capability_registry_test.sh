#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Registry Tests
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


TEST_TEMP_ROOT="$(
    mktemp -d
)"


plugin_root="${TEST_TEMP_ROOT}/plugins"

mkdir -p \
    "${plugin_root}/chrony" \
    "${plugin_root}/systemd-timesyncd" \
    "${plugin_root}/server"


for plugin_id in \
    chrony \
    systemd-timesyncd \
    server; do

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${plugin_root}/${plugin_id}/implementation.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${plugin_root}/${plugin_id}/manifest.sh"
done


# ==============================================================================
# Build Plugin Registry metadata.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_capability_registry_reset


stoleus_definition_register \
    "chrony" \
    "modules" \
    "Chrony time synchronization provider." \
    "${plugin_root}/chrony" \
    "${plugin_root}/chrony/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/chrony/manifest.sh" \
    "bash" \
    "" \
    "" \
    "chrony_verify" \
    "" \
    "" \
    "" \
    "" \
    "" \
    "" \
    "time-sync"


stoleus_definition_register \
    "systemd-timesyncd" \
    "modules" \
    "Systemd time synchronization provider." \
    "${plugin_root}/systemd-timesyncd" \
    "${plugin_root}/systemd-timesyncd/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/systemd-timesyncd/manifest.sh" \
    "bash" \
    "" \
    "" \
    "timesyncd_verify" \
    "" \
    "" \
    "" \
    "" \
    "" \
    "" \
    "time-sync"


stoleus_definition_register \
    "server" \
    "profiles" \
    "General-purpose server profile." \
    "${plugin_root}/server" \
    "${plugin_root}/server/implementation.sh" \
    "" \
    "time-sync,remote-shell" \
    "${plugin_root}/server/manifest.sh" \
    "bash" \
    "" \
    "" \
    "server_verify" \
    "" \
    "" \
    "" \
    "" \
    "" \
    "" \
    ""


STOLEUS_DEFINITIONS_FROZEN="true"

stoleus_registry_import_definitions
stoleus_capability_registry_import_plugins


# ==============================================================================
# Registry state.
# ==============================================================================

if ! stoleus_capability_registry_is_frozen; then
    fail "Capability Registry should be frozen after import."
fi


assert_equals \
    "2" \
    "$(stoleus_capability_registry_get_count)" \
    "Capability Registry should contain two provider records."


if ! stoleus_capability_registry_contains \
    "time-sync@chrony"; then

    fail "Chrony time-sync provider should exist."
fi


if ! stoleus_capability_registry_contains \
    "time-sync@systemd-timesyncd"; then

    fail "Systemd-timesyncd time-sync provider should exist."
fi


assert_equals \
    "chrony" \
    "$(stoleus_capability_registry_get_provider \
        "time-sync" \
        "chrony")" \
    "Chrony capability provider lookup is incorrect."


assert_equals \
    "time-sync" \
    "$(stoleus_capability_registry_get_field \
        "time-sync@chrony" \
        "capability-id")" \
    "Capability field lookup is incorrect."


# ==============================================================================
# Provider listing preserves deterministic Registry order.
# ==============================================================================

expected_providers="$(
    printf '%s\n' \
        "chrony" \
        "systemd-timesyncd"
)"


assert_equals \
    "$expected_providers" \
    "$(stoleus_capability_registry_list_providers "time-sync")" \
    "Capability provider listing is incorrect."


expected_registry="$(
    printf '%s\n' \
        $'time-sync\tchrony' \
        $'time-sync\tsystemd-timesyncd'
)"


assert_equals \
    "$expected_registry" \
    "$(stoleus_capability_registry_list)" \
    "Complete Capability Registry listing is incorrect."


# ==============================================================================
# Successful repeated import is idempotent after freeze.
# ==============================================================================

stoleus_capability_registry_import_plugins


assert_equals \
    "2" \
    "$(stoleus_capability_registry_get_count)" \
    "Repeated Capability Registry import must not duplicate providers."


# ==============================================================================
# Frozen Registry rejects direct provider import.
# ==============================================================================

set +e

stoleus_capability_registry_import_provider \
    "chrony" \
    "remote-shell" \
    >/dev/null 2>&1

frozen_import_exit_code=$?

set -e


# The generic metadata collection rejects mutation after freeze.
assert_equals \
    "8" \
    "$frozen_import_exit_code" \
    "Provider import after freeze should return conflict code 8."


# ==============================================================================
# Unknown provider lookup.
# ==============================================================================

set +e

stoleus_capability_registry_get_provider \
    "time-sync" \
    "unknown-provider" \
    >/dev/null 2>&1

unknown_provider_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_provider_exit_code" \
    "Unknown capability provider should return code 6."


printf '%s\n' \
    "PASS: Capability Registry tests completed successfully."
