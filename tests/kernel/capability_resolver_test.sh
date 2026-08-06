#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Resolver Tests
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
    "${plugin_root}/server" \
    "${plugin_root}/alternative-time"


for plugin_id in \
    chrony \
    server \
    alternative-time; do

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${plugin_root}/${plugin_id}/implementation.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${plugin_root}/${plugin_id}/manifest.sh"
done


# ==============================================================================
# Unique provider resolution.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_capability_registry_reset
stoleus_capability_resolver_reset


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
    "server" \
    "profiles" \
    "General-purpose server profile." \
    "${plugin_root}/server" \
    "${plugin_root}/server/implementation.sh" \
    "" \
    "time-sync" \
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


resolution_path="${TEST_TEMP_ROOT}/resolution.tsv"


# Execute directly so the resolver cache remains in this shell.
stoleus_capability_resolver_resolve \
    "time-sync" \
    > "$resolution_path"


assert_equals \
    $'time-sync\tchrony' \
    "$(cat "$resolution_path")" \
    "Capability resolution selected the wrong provider."


if ! stoleus_capability_resolver_is_resolved "time-sync"; then
    fail "time-sync capability should be cached as resolved."
fi


assert_equals \
    "chrony" \
    "$(stoleus_capability_resolver_get_provider "time-sync")" \
    "Resolved capability provider lookup is incorrect."


assert_equals \
    "1" \
    "${#STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS[@]}" \
    "Resolver cache should contain exactly one capability."


# ==============================================================================
# Validate all plugin requirements.
# ==============================================================================

stoleus_capability_resolver_validate_registry


assert_equals \
    "true" \
    "${STOLEUS_CAPABILITY_RESOLVER_VALIDATED:-false}" \
    "Capability Registry validation state is incorrect."


assert_equals \
    $'time-sync\tchrony' \
    "$(stoleus_capability_resolver_get_resolved)" \
    "Resolved capability listing is incorrect."


# ==============================================================================
# Missing provider detection.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_capability_registry_reset
stoleus_capability_resolver_reset


stoleus_definition_register \
    "server" \
    "profiles" \
    "Server requiring an unavailable capability." \
    "${plugin_root}/server" \
    "${plugin_root}/server/implementation.sh" \
    "" \
    "remote-shell" \
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


set +e

stoleus_capability_resolver_validate_registry \
    >/dev/null 2>&1

missing_provider_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_provider_exit_code" \
    "Missing capability provider should return configuration code 6."


# ==============================================================================
# Ambiguous provider detection.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_capability_registry_reset
stoleus_capability_resolver_reset


stoleus_definition_register \
    "chrony" \
    "modules" \
    "Chrony provider." \
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
    "alternative-time" \
    "modules" \
    "Alternative time provider." \
    "${plugin_root}/alternative-time" \
    "${plugin_root}/alternative-time/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/alternative-time/manifest.sh" \
    "bash" \
    "" \
    "" \
    "alternative_verify" \
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
    "Server requiring time synchronization." \
    "${plugin_root}/server" \
    "${plugin_root}/server/implementation.sh" \
    "" \
    "time-sync" \
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


set +e

stoleus_capability_resolver_resolve \
    "time-sync" \
    >/dev/null 2>&1

ambiguous_provider_exit_code=$?

set -e


assert_equals \
    "8" \
    "$ambiguous_provider_exit_code" \
    "Ambiguous capability providers should return conflict code 8."


printf '%s\n' \
    "PASS: Capability Resolver tests completed successfully."
