#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Lifecycle and Execution Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


TEST_TEMP_ROOT=""
STOLEUS_TEST_EXECUTION_LOG=""


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

STOLEUS_TEST_EXECUTION_LOG="${TEST_TEMP_ROOT}/execution.log"

export STOLEUS_TEST_EXECUTION_LOG


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

printf '%s\n' \
    "load:chrony" \
    >> "$STOLEUS_TEST_EXECUTION_LOG"

chrony_install() {

    printf '%s\n' \
        "run:chrony:install:args=$#" \
        >> "$STOLEUS_TEST_EXECUTION_LOG"

    return 0
}


chrony_verify() {

    printf '%s\n' \
        "run:chrony:verify:args=$#" \
        >> "$STOLEUS_TEST_EXECUTION_LOG"

    return 0
}
IMPLEMENTATION


cat > "${TEST_TEMP_ROOT}/modules/server/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "server"

stoleus_plugin_description \
    "Configure and verify a server profile."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony"

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
    "load:server" \
    >> "$STOLEUS_TEST_EXECUTION_LOG"

server_configure() {

    local profile="${1:-}"

    printf '%s\n' \
        "run:server:configure:profile=${profile}:args=$#" \
        >> "$STOLEUS_TEST_EXECUTION_LOG"

    [[ "$profile" == "stage" ]]
}


server_verify() {

    local profile="${1:-}"

    printf '%s\n' \
        "run:server:verify:profile=${profile}:args=$#" \
        >> "$STOLEUS_TEST_EXECUTION_LOG"

    return 0
}
IMPLEMENTATION


# ==============================================================================
# Build the metadata pipeline.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset
stoleus_planning_reset
stoleus_lifecycle_reset
stoleus_execution_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"


stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"

stoleus_discovery_scan
stoleus_definition_build_all
stoleus_registry_import_definitions
stoleus_resolver_validate_registry


# ==============================================================================
# Verify implementations remain unloaded before execution.
# ==============================================================================

if [[ -f "$STOLEUS_TEST_EXECUTION_LOG" ]]; then
    fail "Plugin implementations must remain unloaded before execution."
fi


# ==============================================================================
# Plan and execute setup.
# ==============================================================================

stoleus_planning_create_request \
    "server" \
    "setup" \
    "stage"

stoleus_planning_build_plan
stoleus_execution_execute_plan


assert_equals \
    "true" \
    "${STOLEUS_EXECUTION_COMPLETED:-false}" \
    "Execution should be marked completed."


assert_equals \
    "true" \
    "${STOLEUS_EXECUTION_SUCCEEDED:-false}" \
    "Execution should succeed."


assert_equals \
    "4" \
    "${#STOLEUS_EXECUTION_RESULT_STEP_NUMBERS[@]}" \
    "Execution should record exactly four steps."


expected_log="$(
    printf '%s\n' \
        "load:chrony" \
        "run:chrony:install:args=0" \
        "run:chrony:verify:args=0" \
        "load:server" \
        "run:server:configure:profile=stage:args=1" \
        "run:server:verify:profile=stage:args=1"
)"


assert_equals \
    "$expected_log" \
    "$(cat "$STOLEUS_TEST_EXECUTION_LOG")" \
    "Lifecycle execution order or argument forwarding is incorrect."


expected_results="$(
    printf '%s\n' \
        $'1\tchrony\tinstall\tchrony_install\tsucceeded\t0' \
        $'2\tchrony\tverify\tchrony_verify\tsucceeded\t0' \
        $'3\tserver\tconfigure\tserver_configure\tsucceeded\t0' \
        $'4\tserver\tverify\tserver_verify\tsucceeded\t0'
)"


assert_equals \
    "$expected_results" \
    "$(stoleus_execution_get_results)" \
    "Execution results are incorrect."


assert_equals \
    "2" \
    "${#STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS[@]}" \
    "Exactly two plugin implementations should be loaded."


# ==============================================================================
# Verify implementations load only once.
# ==============================================================================

stoleus_lifecycle_load_plugin "chrony"
stoleus_lifecycle_load_plugin "server"


assert_equals \
    "$expected_log" \
    "$(cat "$STOLEUS_TEST_EXECUTION_LOG")" \
    "Repeated plugin loading must be idempotent."


# ==============================================================================
# Verify repeated plan execution is rejected.
# ==============================================================================

set +e

stoleus_execution_execute_plan \
    >/dev/null 2>&1

repeat_exit_code=$?

set -e


assert_equals \
    "8" \
    "$repeat_exit_code" \
    "Repeated plan execution should return conflict code 8."


# ==============================================================================
# Verify a failing lifecycle step stops later execution.
# ==============================================================================

stoleus_planning_reset
stoleus_execution_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

server_verify() {

    printf '%s\n' \
        "run:server:verify:forced-failure" \
        >> "$STOLEUS_TEST_EXECUTION_LOG"

    return 9
}


stoleus_planning_create_request \
    "server" \
    "verify" \
    "stage"

stoleus_planning_build_plan


set +e

stoleus_execution_execute_plan

failure_exit_code=$?

set -e


assert_equals \
    "9" \
    "$failure_exit_code" \
    "Lifecycle failure exit code should be preserved."


assert_equals \
    "false" \
    "${STOLEUS_EXECUTION_SUCCEEDED:-true}" \
    "Failed execution must not be marked successful."


failure_results="$(
    stoleus_execution_get_results
)"


expected_failure_results="$(
    printf '%s\n' \
        $'1\tchrony\tverify\tchrony_verify\tsucceeded\t0' \
        $'2\tserver\tverify\tserver_verify\tfailed\t9'
)"


assert_equals \
    "$expected_failure_results" \
    "$failure_results" \
    "Failed execution results are incorrect."


# ==============================================================================
# Verify execution requires a frozen plan.
# ==============================================================================

stoleus_planning_reset
stoleus_execution_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"


set +e

stoleus_execution_execute_plan \
    >/dev/null 2>&1

unplanned_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unplanned_exit_code" \
    "Execution without a frozen plan should return code 6."


printf '%s\n' \
    "PASS: Lifecycle and Execution subsystem tests completed successfully."
