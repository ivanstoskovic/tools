#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel Bootstrap Tests
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


# ==============================================================================
# Initialize the kernel before replacing standard roots with isolated roots.
# ==============================================================================

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
    "Install and verify Chrony."

stoleus_plugin_implementation \
    "implementation.sh"

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

STOLEUS_BOOTSTRAP_TEST_IMPLEMENTATION_LOADED="true"

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

stoleus_plugin_lifecycle \
    "configure" \
    "server_configure"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/server/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

STOLEUS_BOOTSTRAP_TEST_SERVER_IMPLEMENTATION_LOADED="true"

server_configure() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# Configure isolated discovery before bootstrap.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


# ==============================================================================
# Execute complete kernel bootstrap.
# ==============================================================================

stoleus_kernel_bootstrap


assert_equals \
    "true" \
    "${STOLEUS_KERNEL_READY:-false}" \
    "Kernel should be ready after successful bootstrap."


assert_equals \
    "true" \
    "${STOLEUS_KERNEL_BOOTSTRAP_COMPLETED:-false}" \
    "Kernel bootstrap should be marked completed."


assert_equals \
    "ready" \
    "${STOLEUS_KERNEL_BOOTSTRAP_STAGE:-}" \
    "Kernel bootstrap stage should be ready."


assert_equals \
    "0" \
    "${STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE:-}" \
    "Successful bootstrap should record exit code zero."


assert_equals \
    "2" \
    "${#STOLEUS_DISCOVERY_RECORD_PATHS[@]}" \
    "Bootstrap should discover two plugins."


assert_equals \
    "2" \
    "${#STOLEUS_DEFINITION_IDS[@]}" \
    "Bootstrap should build two definitions."


assert_equals \
    "2" \
    "$(stoleus_registry_get_count)" \
    "Bootstrap should import two Registry entries."


assert_equals \
    "true" \
    "${STOLEUS_DEFINITIONS_FROZEN:-false}" \
    "Definition collection should be frozen."


registry_frozen="false"

if stoleus_registry_is_frozen; then
    registry_frozen="true"
fi


assert_equals \
    "true" \
    "$registry_frozen" \
    "Registry should be frozen."


assert_equals \
    "true" \
    "${STOLEUS_RESOLVER_VALIDATED:-false}" \
    "Resolver should validate Registry references."


if [[ -n "${STOLEUS_BOOTSTRAP_TEST_IMPLEMENTATION_LOADED:-}" ]]; then
    fail "Bootstrap must not load plugin implementations."
fi


if [[ -n "${STOLEUS_BOOTSTRAP_TEST_SERVER_IMPLEMENTATION_LOADED:-}" ]]; then
    fail "Bootstrap must not load plugin implementations."
fi


# ==============================================================================
# Verify status output.
# ==============================================================================

expected_status="$(
    printf '%s' \
        $'true\ttrue\ttrue\ttrue\ttrue\tready\t0\t2\t2\t2\t2\ttrue'
)"


assert_equals \
    "$expected_status" \
    "$(stoleus_kernel_get_status)" \
    "Kernel status output is incorrect."


# ==============================================================================
# Verify successful bootstrap is idempotent.
# ==============================================================================

stoleus_kernel_bootstrap
stoleus_kernel_bootstrap


assert_equals \
    "2" \
    "$(stoleus_registry_get_count)" \
    "Repeated successful bootstrap must not duplicate Registry entries."


assert_equals \
    "2" \
    "${#STOLEUS_DISCOVERY_RECORD_PATHS[@]}" \
    "Repeated successful bootstrap must not duplicate discovery records."


# ==============================================================================
# Verify the kernel is ready for Planning.
# ==============================================================================

stoleus_planning_create_request \
    "server" \
    "setup" \
    "stage"

stoleus_planning_build_plan


expected_plan="$(
    printf '%s\n' \
        "chrony" \
        "server"
)"


assert_equals \
    "$expected_plan" \
    "$(stoleus_planning_get_plugins)" \
    "Bootstrapped Registry should be usable by Planning."


printf '%s\n' \
    "PASS: Kernel bootstrap tests completed successfully."
