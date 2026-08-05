#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Registry Subsystem Tests
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


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/chrony" \
    "${TEST_TEMP_ROOT}/modules/server"


cat > "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "chrony"

stoleus_plugin_description \
    "Install, configure, and verify Chrony."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_capabilities \
    "package-manager" \
    "service-manager" \
    "remote-clock"

stoleus_plugin_lifecycle \
    "install" \
    "chrony_install"

stoleus_plugin_lifecycle \
    "configure" \
    "chrony_configure"

stoleus_plugin_lifecycle \
    "verify" \
    "chrony_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/chrony/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

chrony_install() {
    return 0
}

chrony_configure() {
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
    "Configure a complete server profile."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony"

stoleus_plugin_capabilities \
    "package-manager"

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

server_configure() {
    return 0
}

server_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# Configure isolated discovery.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


# ==============================================================================
# Discovery -> Definition -> Registry
# ==============================================================================

stoleus_discovery_scan
stoleus_definition_build_all
stoleus_registry_import_definitions


assert_equals \
    "2" \
    "$(stoleus_registry_get_count)" \
    "Registry should contain exactly two plugins."


if ! stoleus_registry_is_frozen; then
    fail "Registry should be frozen after import."
fi


if ! stoleus_registry_contains "chrony"; then
    fail "Registry should contain chrony."
fi


if ! stoleus_registry_contains "server"; then
    fail "Registry should contain server."
fi


assert_equals \
    "0" \
    "$(stoleus_registry_get_index "chrony")" \
    "Chrony Registry index is incorrect."


assert_equals \
    "1" \
    "$(stoleus_registry_get_index "server")" \
    "Server Registry index is incorrect."


assert_equals \
    "Install, configure, and verify Chrony." \
    "$(stoleus_registry_get_field "chrony" "description")" \
    "Chrony description lookup failed."


assert_equals \
    "package-manager,service-manager,remote-clock" \
    "$(stoleus_registry_get_field "chrony" "capabilities")" \
    "Chrony capability lookup failed."


assert_equals \
    "chrony" \
    "$(stoleus_registry_get_field "server" "dependencies")" \
    "Server dependency lookup failed."


assert_equals \
    "server_configure" \
    "$(stoleus_registry_get_field "server" "configure")" \
    "Server configure lifecycle lookup failed."


assert_equals \
    "bash" \
    "$(stoleus_registry_get_field "server" "manifest-provider")" \
    "Manifest-provider lookup failed."


# ==============================================================================
# Verify Registry listing.
# ==============================================================================

registry_list="$(
    stoleus_registry_list
)"


expected_list="$(
    printf '%s\n' \
        $'chrony\tmodules\tInstall, configure, and verify Chrony.' \
        $'server\tmodules\tConfigure a complete server profile.'
)"


assert_equals \
    "$expected_list" \
    "$registry_list" \
    "Registry listing is incorrect."


# ==============================================================================
# Verify category filtering.
# ==============================================================================

module_count="$(
    stoleus_registry_list "modules" |
        wc -l |
        tr -d '[:space:]'
)"


assert_equals \
    "2" \
    "$module_count" \
    "Category-filtered Registry listing is incorrect."


# ==============================================================================
# Verify unknown lookup.
# ==============================================================================

set +e

stoleus_registry_get_field \
    "unknown" \
    "description" \
    >/dev/null 2>&1

unknown_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_exit_code" \
    "Unknown Registry plugin should return code 6."


# ==============================================================================
# Verify unsupported field.
# ==============================================================================

set +e

stoleus_registry_get_field \
    "chrony" \
    "unsupported-field" \
    >/dev/null 2>&1

unsupported_field_exit_code=$?

set -e


assert_equals \
    "2" \
    "$unsupported_field_exit_code" \
    "Unsupported Registry field should return code 2."


# ==============================================================================
# Verify Registry immutability.
# ==============================================================================

set +e

stoleus_registry_append_definition \
    "0" \
    >/dev/null 2>&1

immutable_exit_code=$?

set -e


assert_equals \
    "8" \
    "$immutable_exit_code" \
    "Appending after Registry freeze should return code 8."


# ==============================================================================
# Verify implementation files remain unloaded.
# ==============================================================================

if declare -F chrony_install >/dev/null 2>&1; then
    fail "Registry import must not source plugin implementations."
fi


if declare -F server_configure >/dev/null 2>&1; then
    fail "Registry import must not source plugin implementations."
fi


printf '%s\n' \
    "PASS: Registry subsystem tests completed successfully."
