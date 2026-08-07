#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Executor Whole-Plan Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

TEST_TEMP_ROOT="$(
    mktemp -d
)"

trap 'rm -rf -- "$TEST_TEMP_ROOT"' EXIT


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


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/example"


cat > "${TEST_TEMP_ROOT}/modules/example/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "example"

stoleus_plugin_description \
    "Example whole-plan rollback plugin."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "install" \
    "example_install"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/example/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

example_install() {

    return 0
}


example_rollback_first() {

    printf '%s\n' \
        "first" \
        >> "$STOLEUS_ROLLBACK_PLAN_TEST_LOG"

    return 0
}


example_rollback_second() {

    printf '%s\n' \
        "second" \
        >> "$STOLEUS_ROLLBACK_PLAN_TEST_LOG"

    return 0
}


example_rollback_failure() {

    printf '%s\n' \
        "failure" \
        >> "$STOLEUS_ROLLBACK_PLAN_TEST_LOG"

    return 29
}


example_rollback_after_failure() {

    printf '%s\n' \
        "after-failure" \
        >> "$STOLEUS_ROLLBACK_PLAN_TEST_LOG"

    return 0
}
IMPLEMENTATION


export STOLEUS_ROLLBACK_PLAN_TEST_LOG="${TEST_TEMP_ROOT}/rollback-plan.log"

: > "$STOLEUS_ROLLBACK_PLAN_TEST_LOG"


source "${PROJECT_ROOT}/kernel/kernel.sh"


stoleus_kernel_initialize


# ==============================================================================
# Configure the test plugin Registry.
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


stoleus_kernel_bootstrap


build_plan() {

    stoleus_rollback_builder_reset
    stoleus_rollback_builder_begin

    while (( $# >= 2 )); do

        stoleus_rollback_builder_add \
            "$1" \
            "example" \
            "$2"

        shift 2
    done

    stoleus_rollback_builder_finalize
}


reset_runtime() {

    stoleus_rollback_executor_reset
    stoleus_rollback_result_registry_reset

    : > "$STOLEUS_ROLLBACK_PLAN_TEST_LOG"
}


# ==============================================================================
# Successful whole-plan execution.
# ==============================================================================

build_plan \
    "8" "example_rollback_first" \
    "7" "example_rollback_second"


stoleus_rollback_executor_execute_plan


expected_success_log="$(
    printf '%s\n' \
        "first" \
        "second"
)"


assert_equals \
    "$expected_success_log" \
    "$(cat "$STOLEUS_ROLLBACK_PLAN_TEST_LOG")" \
    "Rollback Plan functions were not executed in plan order."


assert_equals \
    "2" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Successful whole-plan rollback should record two results."


expected_success_results="$(
    printf '%s\n' \
        $'1\t8\texample\texample_rollback_first\tsucceeded\t0' \
        $'2\t7\texample\texample_rollback_second\tsucceeded\t0'
)"


assert_equals \
    "$expected_success_results" \
    "$(stoleus_rollback_executor_get_results)" \
    "Successful whole-plan rollback results are incorrect."


if ! stoleus_rollback_executor_is_completed; then
    fail "Rollback Executor should be completed after plan execution."
fi


if stoleus_rollback_executor_is_running; then
    fail "Rollback Executor should not remain running after plan execution."
fi


session_id="$(
    stoleus_rollback_executor_get_session_id
)"


if [[ -z "$session_id" ]]; then
    fail "Whole-plan rollback should generate a session ID."
fi


# ==============================================================================
# Repeated execution requires reset.
# ==============================================================================

set +e

stoleus_rollback_executor_execute_plan \
    >/dev/null 2>&1

repeat_exit_code=$?

set -e


assert_equals \
    "8" \
    "$repeat_exit_code" \
    "Repeated rollback-plan execution should return code 8."


# ==============================================================================
# Dry-run traverses every step without invocation.
# ==============================================================================

reset_runtime

stoleus_rollback_builder_reset

build_plan \
    "8" "example_rollback_first" \
    "7" "example_rollback_second"


stoleus_rollback_executor_execute_plan \
    --dry-run


if [[ -s "$STOLEUS_ROLLBACK_PLAN_TEST_LOG" ]]; then
    fail "Dry-run must not invoke rollback functions."
fi


expected_dry_run_results="$(
    printf '%s\n' \
        $'1\t8\texample\texample_rollback_first\tskipped\t0' \
        $'2\t7\texample\texample_rollback_second\tskipped\t0'
)"


assert_equals \
    "$expected_dry_run_results" \
    "$(stoleus_rollback_executor_get_results)" \
    "Dry-run Rollback Plan results are incorrect."


# ==============================================================================
# Stop on first rollback failure.
# ==============================================================================

reset_runtime

stoleus_rollback_builder_reset

build_plan \
    "8" "example_rollback_first" \
    "7" "example_rollback_failure" \
    "6" "example_rollback_after_failure"


set +e

stoleus_rollback_executor_execute_plan

failure_exit_code=$?

set -e


assert_equals \
    "29" \
    "$failure_exit_code" \
    "Whole-plan rollback should preserve the first failure code."


expected_failure_log="$(
    printf '%s\n' \
        "first" \
        "failure"
)"


assert_equals \
    "$expected_failure_log" \
    "$(cat "$STOLEUS_ROLLBACK_PLAN_TEST_LOG")" \
    "Rollback execution should stop immediately after failure."


assert_equals \
    "2" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Only attempted rollback steps should be recorded after failure."


assert_equals \
    "failed" \
    "$(stoleus_rollback_result_registry_get_field \
        "$(stoleus_rollback_executor_get_session_id)" \
        "2" \
        "status")" \
    "Failed whole-plan rollback result status is incorrect."


if ! stoleus_rollback_executor_is_completed; then
    fail "Failed Rollback Plan execution should still complete the executor."
fi


# ==============================================================================
# Invalid argument is rejected before execution starts.
# ==============================================================================

reset_runtime

stoleus_rollback_builder_reset

build_plan \
    "8" "example_rollback_first"


set +e

stoleus_rollback_executor_execute_plan \
    --preview \
    >/dev/null 2>&1

invalid_argument_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_argument_exit_code" \
    "Unsupported rollback-plan argument should return code 2."


if stoleus_rollback_executor_is_running ||
   stoleus_rollback_executor_is_completed; then

    fail "Invalid arguments must not transition Rollback Executor state."
fi


# ==============================================================================
# Empty frozen plans are rejected.
# ==============================================================================

stoleus_rollback_builder_reset
stoleus_rollback_builder_begin
stoleus_rollback_builder_finalize


set +e

stoleus_rollback_executor_execute_plan \
    >/dev/null 2>&1

empty_plan_exit_code=$?

set -e


assert_equals \
    "6" \
    "$empty_plan_exit_code" \
    "Empty Rollback Plan execution should return code 6."


printf '%s\n' \
    "PASS: Rollback Executor Whole-Plan tests completed successfully."
