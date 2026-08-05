#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Definition Subsystem Tests
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
    "${TEST_TEMP_ROOT}/modules/chrony"


cat > "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "chrony"

stoleus_plugin_description \
    "Install, configure, and verify Chrony."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies

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

STOLEUS_TEST_IMPLEMENTATION_WAS_LOADED="true"

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


# ==============================================================================
# Configure isolated discovery roots.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


# ==============================================================================
# Discover and build definitions.
# ==============================================================================

stoleus_discovery_scan
stoleus_definition_build_all


assert_equals \
    "1" \
    "${#STOLEUS_DEFINITION_IDS[@]}" \
    "Exactly one PluginDefinition should be built."


assert_equals \
    "chrony" \
    "${STOLEUS_DEFINITION_IDS[0]}" \
    "PluginDefinition ID is incorrect."


assert_equals \
    "modules" \
    "${STOLEUS_DEFINITION_CATEGORIES[0]}" \
    "PluginDefinition category is incorrect."


assert_equals \
    "Install, configure, and verify Chrony." \
    "${STOLEUS_DEFINITION_DESCRIPTIONS[0]}" \
    "PluginDefinition description is incorrect."


assert_equals \
    "package-manager,service-manager,remote-clock" \
    "${STOLEUS_DEFINITION_CAPABILITIES[0]}" \
    "PluginDefinition capabilities are incorrect."


assert_equals \
    "chrony_install" \
    "${STOLEUS_DEFINITION_INSTALL_FUNCTIONS[0]}" \
    "Install lifecycle function is incorrect."


assert_equals \
    "chrony_configure" \
    "${STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS[0]}" \
    "Configure lifecycle function is incorrect."


assert_equals \
    "chrony_verify" \
    "${STOLEUS_DEFINITION_VERIFY_FUNCTIONS[0]}" \
    "Verify lifecycle function is incorrect."


assert_equals \
    "bash" \
    "${STOLEUS_DEFINITION_MANIFEST_PROVIDERS[0]}" \
    "Manifest provider is incorrect."


if [[ "${STOLEUS_DEFINITIONS_FROZEN:-false}" != "true" ]]; then
    fail "Definitions should be frozen after a successful build."
fi


if [[ -n "${STOLEUS_TEST_IMPLEMENTATION_WAS_LOADED:-}" ]]; then
    fail "Definition building must not source plugin implementations."
fi


# ==============================================================================
# Verify immutability.
# ==============================================================================

set +e

stoleus_definition_register \
    "late-plugin" \
    "modules" \
    "Late plugin" \
    "${TEST_TEMP_ROOT}/modules/chrony" \
    "${TEST_TEMP_ROOT}/modules/chrony/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh" \
    "bash" \
    "late_install" \
    "" \
    "" \
    "" \
    "" \
    >/dev/null 2>&1

immutable_exit_code=$?

set -e


assert_equals \
    "8" \
    "$immutable_exit_code" \
    "Registering after freeze should return conflict code 8."


printf '%s\n' \
    "PASS: Definition subsystem tests completed successfully."
