#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Plugin Manager Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


TEST_TEMP_ROOT=""
STOLEUS_PLUGIN_TEST_LOG=""


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

STOLEUS_PLUGIN_TEST_LOG="${TEST_TEMP_ROOT}/plugin.log"

export STOLEUS_PLUGIN_TEST_LOG


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/chrony" \
    "${TEST_TEMP_ROOT}/modules/server"


cat > "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "chrony"

stoleus_plugin_description \
    "Install and verify Chrony."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_capabilities \
    "package-manager" \
    "service-manager"

stoleus_plugin_lifecycle \
    "install" \
    "chrony_install"

stoleus_plugin_lifecycle \
    "verify" \
    "chrony_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/chrony/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

printf '%s\n' \
    "loaded:chrony" \
    >> "$STOLEUS_PLUGIN_TEST_LOG"

chrony_install() {
    return 0
}

chrony_verify() {
    return 0
}
IMPLEMENTATION


cat > "${TEST_TEMP_ROOT}/modules/server/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "server"

stoleus_plugin_description \
    "Configure a server profile."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony"

stoleus_plugin_capabilities \
    "service-manager"

stoleus_plugin_lifecycle \
    "configure" \
    "server_configure"

stoleus_plugin_lifecycle \
    "verify" \
    "server_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/server/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

printf '%s\n' \
    "loaded:server" \
    >> "$STOLEUS_PLUGIN_TEST_LOG"

server_configure() {
    return 0
}

server_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# Configure isolated roots before bootstrap.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset
stoleus_plugin_reset
stoleus_lifecycle_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


# ==============================================================================
# Bootstrap and activate the Plugin Manager.
# ==============================================================================

stoleus_kernel_bootstrap


assert_equals \
    "true" \
    "${STOLEUS_PLUGIN_MANAGER_ACTIVE:-false}" \
    "Plugin Manager should be active after kernel bootstrap."


if [[ -f "$STOLEUS_PLUGIN_TEST_LOG" ]]; then
    fail "Plugin Manager activation must not load implementations."
fi


# ==============================================================================
# Existence and field lookup.
# ==============================================================================

if ! stoleus_plugin_exists "chrony"; then
    fail "Plugin Manager should contain chrony."
fi


if stoleus_plugin_exists "unknown"; then
    fail "Unknown plugin should not exist."
fi


assert_equals \
    "modules" \
    "$(stoleus_plugin_get_field "chrony" "category")" \
    "Chrony category is incorrect."


assert_equals \
    "metadata-only" \
    "$(stoleus_plugin_get_field "chrony" "runtime-state")" \
    "Chrony should initially be metadata-only."


assert_equals \
    "false" \
    "$(stoleus_plugin_get_field "chrony" "loaded")" \
    "Chrony should initially be unloaded."


# ==============================================================================
# Lifecycle operation support.
# ==============================================================================

expected_chrony_operations="$(
    printf '%s\n' \
        "install" \
        "verify"
)"


assert_equals \
    "$expected_chrony_operations" \
    "$(stoleus_plugin_list_operations "chrony")" \
    "Chrony lifecycle operations are incorrect."


if ! stoleus_plugin_supports_operation "chrony" "install"; then
    fail "Chrony should support install."
fi


if stoleus_plugin_supports_operation "chrony" "configure"; then
    fail "Chrony should not support configure."
fi


# ==============================================================================
# Dependencies and capabilities.
# ==============================================================================

assert_equals \
    "chrony" \
    "$(stoleus_plugin_get_dependencies "server")" \
    "Server dependencies are incorrect."


expected_chrony_capabilities="$(
    printf '%s\n' \
        "package-manager" \
        "service-manager"
)"


assert_equals \
    "$expected_chrony_capabilities" \
    "$(stoleus_plugin_get_capabilities "chrony")" \
    "Chrony capabilities are incorrect."


# ==============================================================================
# Complete plugin views and listing.
# ==============================================================================

assert_equals \
    $'chrony\tmodules\tInstall and verify Chrony.\tmetadata-only\t\tpackage-manager,service-manager\tinstall,verify' \
    "$(stoleus_plugin_get "chrony")" \
    "Complete Chrony plugin view is incorrect."


expected_list="$(
    printf '%s\n' \
        $'chrony\tmodules\tmetadata-only\tInstall and verify Chrony.' \
        $'server\tmodules\tmetadata-only\tConfigure a server profile.'
)"


assert_equals \
    "$expected_list" \
    "$(stoleus_plugin_list)" \
    "Plugin listing is incorrect."


# ==============================================================================
# Runtime state reflects Lifecycle loading.
# ==============================================================================

stoleus_lifecycle_load_plugin "chrony"


assert_equals \
    "loaded" \
    "$(stoleus_plugin_get_field "chrony" "runtime-state")" \
    "Chrony runtime state should become loaded."


assert_equals \
    "true" \
    "$(stoleus_plugin_get_field "chrony" "loaded")" \
    "Chrony loaded field should become true."


expected_loaded_list="$(
    printf '%s\n' \
        $'chrony\tmodules\tloaded\tInstall and verify Chrony.' \
        $'server\tmodules\tmetadata-only\tConfigure a server profile.'
)"


assert_equals \
    "$expected_loaded_list" \
    "$(stoleus_plugin_list)" \
    "Plugin listing should reflect implementation loading."


if [[ "$(cat "$STOLEUS_PLUGIN_TEST_LOG")" != "loaded:chrony" ]]; then
    fail "Lifecycle should load only the requested implementation."
fi


# ==============================================================================
# Unknown plugin handling.
# ==============================================================================

set +e

stoleus_plugin_get \
    "unknown" \
    >/dev/null 2>&1

unknown_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_exit_code" \
    "Unknown plugin lookup should return code 6."


printf '%s\n' \
    "PASS: Plugin Manager tests completed successfully."
