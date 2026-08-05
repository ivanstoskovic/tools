#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Planning Subsystem Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"
source "${PROJECT_ROOT}/tests/kernel/helpers/registry_storage.sh"


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
    "${TEST_TEMP_ROOT}/modules/docker" \
    "${TEST_TEMP_ROOT}/modules/server"


cat > "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "chrony"

stoleus_plugin_description \
    "Install, configure, and verify Chrony."

stoleus_plugin_implementation \
    "implementation.sh"

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


cat > "${TEST_TEMP_ROOT}/modules/docker/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "docker"

stoleus_plugin_description \
    "Install and verify Docker."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony"

stoleus_plugin_lifecycle \
    "install" \
    "docker_install"

stoleus_plugin_lifecycle \
    "verify" \
    "docker_verify"

stoleus_plugin_lifecycle \
    "upgrade" \
    "docker_upgrade"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/server/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "server"

stoleus_plugin_description \
    "Configure and verify a server profile."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony" \
    "docker"

stoleus_plugin_lifecycle \
    "configure" \
    "server_configure"

stoleus_plugin_lifecycle \
    "verify" \
    "server_verify"

stoleus_plugin_lifecycle \
    "remove" \
    "server_remove"

stoleus_plugin_end
MANIFEST


for plugin_id in chrony docker server; do

    cat > "${TEST_TEMP_ROOT}/modules/${plugin_id}/implementation.sh" <<IMPLEMENTATION
#!/usr/bin/env bash

${plugin_id}_install() {
    return 0
}

${plugin_id}_configure() {
    return 0
}

${plugin_id}_verify() {
    return 0
}

${plugin_id}_upgrade() {
    return 0
}

${plugin_id}_remove() {
    return 0
}
IMPLEMENTATION

done


# ==============================================================================
# Build isolated Registry.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"

stoleus_discovery_scan
stoleus_definition_build_all
stoleus_registry_import_definitions
stoleus_resolver_validate_registry


# ==============================================================================
# Setup request and dependency-first plan.
# ==============================================================================

stoleus_planning_create_request \
    "server" \
    "setup" \
    "stage"


assert_equals \
    $'server\tsetup\t1' \
    "$(stoleus_planning_get_request)" \
    "ExecutionRequest output is incorrect."


stoleus_planning_build_plan


assert_equals \
    "true" \
    "${STOLEUS_PLAN_FROZEN:-false}" \
    "ExecutionPlan should be frozen."


expected_plugin_order="$(
    printf '%s\n' \
        "chrony" \
        "docker" \
        "server"
)"


assert_equals \
    "$expected_plugin_order" \
    "$(stoleus_planning_get_plugins)" \
    "Dependency-first plugin ordering is incorrect."


assert_equals \
    "7" \
    "${#STOLEUS_PLAN_STEP_PLUGIN_IDS[@]}" \
    "Setup plan should contain seven lifecycle steps."


expected_steps="$(
    printf '%s\n' \
        $'1\tchrony\t0\tinstall\tchrony_install\tfalse' \
        $'2\tchrony\t0\tconfigure\tchrony_configure\tfalse' \
        $'3\tchrony\t0\tverify\tchrony_verify\tfalse' \
        $'4\tdocker\t1\tinstall\tdocker_install\tfalse' \
        $'5\tdocker\t1\tverify\tdocker_verify\tfalse' \
        $'6\tserver\t2\tconfigure\tserver_configure\ttrue' \
        $'7\tserver\t2\tverify\tserver_verify\ttrue'
)"


assert_equals \
    "$expected_steps" \
    "$(stoleus_planning_get_steps)" \
    "Setup ExecutionPlan steps are incorrect."


# ==============================================================================
# Verify plan idempotency.
# ==============================================================================

stoleus_planning_build_plan


assert_equals \
    "7" \
    "${#STOLEUS_PLAN_STEP_PLUGIN_IDS[@]}" \
    "Repeated plan building must not duplicate steps."


# ==============================================================================
# Verify operation.
# ==============================================================================

stoleus_planning_reset
STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_planning_create_request \
    "server" \
    "verify"

stoleus_planning_build_plan


expected_verify_steps="$(
    printf '%s\n' \
        $'1\tchrony\t0\tverify\tchrony_verify\tfalse' \
        $'2\tdocker\t1\tverify\tdocker_verify\tfalse' \
        $'3\tserver\t2\tverify\tserver_verify\ttrue'
)"


assert_equals \
    "$expected_verify_steps" \
    "$(stoleus_planning_get_steps)" \
    "Verify ExecutionPlan is incorrect."


# ==============================================================================
# Upgrade operation adds verify when available.
# ==============================================================================

stoleus_planning_reset
STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_planning_create_request \
    "docker" \
    "upgrade"

stoleus_planning_build_plan


expected_upgrade_steps="$(
    printf '%s\n' \
        $'1\tchrony\t0\tverify\tchrony_verify\tfalse' \
        $'2\tdocker\t1\tupgrade\tdocker_upgrade\ttrue' \
        $'3\tdocker\t1\tverify\tdocker_verify\ttrue'
)"


assert_equals \
    "$expected_upgrade_steps" \
    "$(stoleus_planning_get_steps)" \
    "Upgrade ExecutionPlan is incorrect."


# ==============================================================================
# Remove operation must not remove dependencies automatically.
# ==============================================================================

stoleus_planning_reset
STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_planning_create_request \
    "server" \
    "remove"

stoleus_planning_build_plan


assert_equals \
    "server" \
    "$(stoleus_planning_get_plugins)" \
    "Remove plan must contain only the requested plugin."


assert_equals \
    $'1\tserver\t2\tremove\tserver_remove\ttrue' \
    "$(stoleus_planning_get_steps)" \
    "Remove ExecutionPlan is incorrect."


# ==============================================================================
# Unknown target handling.
# ==============================================================================

stoleus_planning_reset
STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_planning_create_request \
    "unknown" \
    "setup"


set +e

stoleus_planning_build_plan \
    >/dev/null 2>&1

unknown_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_exit_code" \
    "Unknown plan target should return code 6."


# ==============================================================================
# Multi-plugin cycle detection.
# ==============================================================================

stoleus_planning_reset
STOLEUS_PLANNING_REQUEST_CREATED="false"

original_chrony_dependencies="$(
    stoleus_registry_get_field         "chrony"         "dependencies"
)"

stoleus_test_registry_replace_field     "chrony"     "dependencies"     "server"


stoleus_planning_create_request \
    "server" \
    "setup"


set +e

cycle_output="$(
    stoleus_planning_build_plan 2>&1
)"

cycle_exit_code=$?

set -e


assert_equals \
    "8" \
    "$cycle_exit_code" \
    "Circular dependency should return conflict code 8."


if [[ "$cycle_output" != *"server -> chrony -> server"* ]]; then
    fail "Cycle diagnostic should contain the dependency path."
fi


stoleus_test_registry_replace_field     "chrony"     "dependencies"     "$original_chrony_dependencies"


printf '%s\n' \
    "PASS: Planning subsystem tests completed successfully."
