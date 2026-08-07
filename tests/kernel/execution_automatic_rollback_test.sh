#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Automatic Rollback Integration Tests
# ==============================================================================
#
# Scenarios added incrementally:
#
#     1. Successful execution does not require rollback.
#     2. Forward failure triggers successful rollback.
#     3. Forward failure may produce an empty rollback plan.
#     4. Rollback failure is recorded separately.
#     5. Dry-run never triggers rollback.
#     6. Continue policy rolls back after all forward steps are attempted.
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

AUTOMATIC_ROLLBACK_LOG="${TEST_TEMP_ROOT}/automatic-rollback.log"


cleanup() {

    rm -rf -- "$TEST_TEMP_ROOT"
}


trap cleanup EXIT


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


assert_function_exists() {

    local function_name="${1:-}"


    if [[ -z "$function_name" ]]; then
        fail "Function-existence assertion requires a function name."
    fi


    if ! declare -F "$function_name" >/dev/null 2>&1; then
        fail "Expected function does not exist: ${function_name}"
    fi
}


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/success" \
    "${TEST_TEMP_ROOT}/modules/failure" \
    "${TEST_TEMP_ROOT}/modules/norollback"

: > "$AUTOMATIC_ROLLBACK_LOG"

export AUTOMATIC_ROLLBACK_LOG


# ==============================================================================
# Success plugin.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/success/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "success"

stoleus_plugin_description \
    "Successful automatic-rollback integration-test plugin."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "install" \
    "automatic_success_install"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/success/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

automatic_success_install() {

    printf '%s\n' \
        "forward:success:install" \
        >> "$AUTOMATIC_ROLLBACK_LOG"

    return 0
}


automatic_success_restore() {

    printf '%s\n' \
        "rollback:success:restore" \
        >> "$AUTOMATIC_ROLLBACK_LOG"


    if [[ "${AUTOMATIC_ROLLBACK_FORCE_FAILURE:-false}" == "true" ]]; then
        return 47
    fi


    return 0
}
IMPLEMENTATION


# ==============================================================================
# Failure plugin.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/failure/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "failure"

stoleus_plugin_description \
    "Failing automatic-rollback integration-test plugin."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "success"

stoleus_plugin_lifecycle \
    "install" \
    "automatic_failure_install"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/failure/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

automatic_failure_install() {

    printf '%s\n' \
        "forward:failure:install" \
        >> "$AUTOMATIC_ROLLBACK_LOG"

    return 31
}


automatic_failure_restore() {

    printf '%s\n' \
        "rollback:failure:restore" \
        >> "$AUTOMATIC_ROLLBACK_LOG"

    return 0
}
IMPLEMENTATION


# ==============================================================================
# Plugin without a rollback mapping.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/norollback/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "norollback"

stoleus_plugin_description \
    "Forward-failing plugin without a compensating rollback action."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "install" \
    "automatic_norollback_install"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/norollback/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

automatic_norollback_install() {

    printf '%s\n' \
        "forward:norollback:install" \
        >> "$AUTOMATIC_ROLLBACK_LOG"

    return 37
}
IMPLEMENTATION


# ==============================================================================
# Kernel initialization and test-specific discovery.
# ==============================================================================

source "${PROJECT_ROOT}/kernel/kernel.sh"


stoleus_kernel_initialize


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


# ==============================================================================
# Fixture verification.
# ==============================================================================

for plugin_id in \
    success \
    failure \
    norollback
do
    stoleus_registry_get_index \
        "$plugin_id" \
        >/dev/null ||
        fail "Test plugin was not registered: ${plugin_id}"
done


assert_function_exists \
    "stoleus_execution_coordinator_run_automatic_rollback"

assert_function_exists \
    "stoleus_rollback_planner_build"

assert_function_exists \
    "stoleus_rollback_executor_execute_plan"


# Rollback declarations are registered explicitly until the rollback manifest DSL
# is integrated into Definition and Registry import.
stoleus_rollback_registry_register \
    "success" \
    "install" \
    "automatic_success_restore"


stoleus_rollback_registry_register \
    "failure" \
    "install" \
    "automatic_failure_restore"


assert_equals \
    "2" \
    "$(stoleus_rollback_registry_get_count)" \
    "Automatic-rollback fixture mappings are incorrect."


# ==============================================================================
# Scenario 1 — Successful execution does not require rollback.
# ==============================================================================

: > "$AUTOMATIC_ROLLBACK_LOG"

unset AUTOMATIC_ROLLBACK_FORCE_FAILURE || true


# Reset forward and rollback runtime state.
stoleus_execution_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_rollback_planner_reset
stoleus_rollback_executor_reset
stoleus_rollback_result_registry_reset


# Build a successful forward execution plan.
stoleus_planning_create_request \
    "success" \
    "install" \
    "stage"

stoleus_planning_build_plan


# Execute with automatic rollback enabled.
stoleus_execution_execute_plan \
    --automatic-rollback


successful_session="$(
    stoleus_execution_get_session
)"


IFS=$'	' read -r \
    successful_execution_id \
    successful_mode \
    successful_failure_policy \
    successful_status \
    successful_target \
    successful_operation \
    successful_started_at \
    successful_finished_at \
    successful_current_step \
    successful_total_steps \
    successful_failed_step_count \
    successful_exit_code \
    successful_automatic_rollback \
    successful_rollback_attempted \
    successful_rollback_status \
    successful_rollback_exit_code \
    <<< "$successful_session"


assert_equals \
    "succeeded" \
    "$successful_status" \
    "Successful execution session status is incorrect."


assert_equals \
    "0" \
    "$successful_exit_code" \
    "Successful execution exit code is incorrect."


assert_equals \
    "true" \
    "$successful_automatic_rollback" \
    "Automatic rollback should be enabled for the session."


assert_equals \
    "false" \
    "$successful_rollback_attempted" \
    "Rollback should not be attempted after successful execution."


assert_equals \
    "not-needed" \
    "$successful_rollback_status" \
    "Successful execution rollback status is incorrect."


assert_equals \
    "0" \
    "$successful_rollback_exit_code" \
    "Successful execution rollback exit code is incorrect."


assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Successful forward execution should not create rollback results."


expected_success_log="$(
    printf '%s
' \
        "forward:success:install"
)"


assert_equals \
    "$expected_success_log" \
    "$(cat "$AUTOMATIC_ROLLBACK_LOG")" \
    "Successful execution produced unexpected activity."


# ==============================================================================
# Scenario 2 — Forward failure triggers successful rollback.
# ==============================================================================

: > "$AUTOMATIC_ROLLBACK_LOG"

unset AUTOMATIC_ROLLBACK_FORCE_FAILURE || true


# Reset forward and rollback runtime state.
stoleus_execution_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_rollback_planner_reset
stoleus_rollback_executor_reset
stoleus_rollback_result_registry_reset


# Build a forward plan:
#
#     success/install  -> succeeds
#     failure/install  -> fails with 31
#
# The successful first step has a registered rollback mapping.
stoleus_planning_create_request \
    "failure" \
    "install" \
    "stage"

stoleus_planning_build_plan


set +e

stoleus_execution_execute_plan \
    --automatic-rollback

forward_failure_exit_code=$?

set -e


assert_equals \
    "31" \
    "$forward_failure_exit_code" \
    "Automatic rollback must preserve the original forward failure code."


failed_rollback_session="$(
    stoleus_execution_get_session
)"


IFS=$'	' read -r \
    failed_rollback_execution_id \
    failed_rollback_mode \
    failed_rollback_failure_policy \
    failed_rollback_status \
    failed_rollback_target \
    failed_rollback_operation \
    failed_rollback_started_at \
    failed_rollback_finished_at \
    failed_rollback_current_step \
    failed_rollback_total_steps \
    failed_rollback_failed_step_count \
    failed_rollback_forward_exit_code \
    failed_rollback_enabled \
    failed_rollback_attempted \
    failed_rollback_outcome \
    failed_rollback_exit_code \
    <<< "$failed_rollback_session"


assert_equals \
    "failed" \
    "$failed_rollback_status" \
    "Forward execution session should remain failed after successful rollback."


assert_equals \
    "31" \
    "$failed_rollback_forward_exit_code" \
    "Execution session should preserve the forward failure code."


assert_equals \
    "true" \
    "$failed_rollback_enabled" \
    "Automatic rollback should be enabled for the failed session."


assert_equals \
    "true" \
    "$failed_rollback_attempted" \
    "Rollback should be attempted after forward execution failure."


assert_equals \
    "succeeded" \
    "$failed_rollback_outcome" \
    "Automatic rollback should succeed."


assert_equals \
    "0" \
    "$failed_rollback_exit_code" \
    "Successful automatic rollback should record exit code 0."


assert_equals \
    "1" \
    "$(stoleus_rollback_plan_get_count)" \
    "Automatic rollback should produce one compensating action."


assert_equals \
    "1" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Automatic rollback should record one rollback result."


rollback_session_id="$(
    stoleus_rollback_executor_get_session_id
)"


assert_equals \
    "succeeded" \
    "$(stoleus_rollback_result_registry_get_field \
        "$rollback_session_id" \
        "1" \
        "status")" \
    "Automatic rollback result status is incorrect."


assert_equals \
    "automatic_success_restore" \
    "$(stoleus_rollback_result_registry_get_field \
        "$rollback_session_id" \
        "1" \
        "rollback-function")" \
    "Automatic rollback invoked the wrong compensating function."


expected_failure_rollback_log="$(
    printf '%s
' \
        "forward:success:install" \
        "forward:failure:install" \
        "rollback:success:restore"
)"


assert_equals \
    "$expected_failure_rollback_log" \
    "$(cat "$AUTOMATIC_ROLLBACK_LOG")" \
    "Forward failure and automatic rollback order is incorrect."


# ==============================================================================
# Scenario 3 — Forward failure creates an empty rollback plan.
# ==============================================================================

: > "$AUTOMATIC_ROLLBACK_LOG"

unset AUTOMATIC_ROLLBACK_FORCE_FAILURE || true


# Reset forward and rollback runtime state.
stoleus_execution_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_rollback_planner_reset
stoleus_rollback_executor_reset
stoleus_rollback_result_registry_reset


# Build a plan containing only a failing plugin with no rollback mapping.
stoleus_planning_create_request \
    "norollback" \
    "install" \
    "stage"

stoleus_planning_build_plan


set +e

stoleus_execution_execute_plan \
    --automatic-rollback

empty_plan_forward_exit_code=$?

set -e


assert_equals \
    "37" \
    "$empty_plan_forward_exit_code" \
    "Empty rollback plan must preserve the forward failure code."


empty_plan_session="$(
    stoleus_execution_get_session
)"


IFS=$'	' read -r \
    empty_execution_id \
    empty_mode \
    empty_failure_policy \
    empty_status \
    empty_target \
    empty_operation \
    empty_started_at \
    empty_finished_at \
    empty_current_step \
    empty_total_steps \
    empty_failed_step_count \
    empty_forward_exit_code \
    empty_automatic_rollback \
    empty_rollback_attempted \
    empty_rollback_status \
    empty_rollback_exit_code \
    <<< "$empty_plan_session"


assert_equals \
    "failed" \
    "$empty_status" \
    "Execution should remain failed when the rollback plan is empty."


assert_equals \
    "37" \
    "$empty_forward_exit_code" \
    "Session should preserve the original forward failure code."


assert_equals \
    "true" \
    "$empty_automatic_rollback" \
    "Automatic rollback should be enabled for the empty-plan scenario."


assert_equals \
    "true" \
    "$empty_rollback_attempted" \
    "Rollback planning should be attempted after forward failure."


assert_equals \
    "empty" \
    "$empty_rollback_status" \
    "Empty rollback-plan status is incorrect."


assert_equals \
    "0" \
    "$empty_rollback_exit_code" \
    "An empty rollback plan should not record a rollback failure."


assert_equals \
    "0" \
    "$(stoleus_rollback_plan_get_count)" \
    "Rollback Plan should contain no compensating actions."


assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Empty rollback plans should not create rollback results."


expected_empty_plan_log="$(
    printf '%s
' \
        "forward:norollback:install"
)"


assert_equals \
    "$expected_empty_plan_log" \
    "$(cat "$AUTOMATIC_ROLLBACK_LOG")" \
    "Empty rollback-plan scenario produced unexpected activity."


# ==============================================================================
# Scenario 4 — Rollback failure is recorded separately.
# ==============================================================================

: > "$AUTOMATIC_ROLLBACK_LOG"

export AUTOMATIC_ROLLBACK_FORCE_FAILURE="true"


stoleus_execution_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_rollback_planner_reset
stoleus_rollback_executor_reset
stoleus_rollback_result_registry_reset


stoleus_planning_create_request \
    "failure" \
    "install" \
    "stage"

stoleus_planning_build_plan


set +e

stoleus_execution_execute_plan \
    --automatic-rollback

rollback_failure_forward_exit_code=$?

set -e


unset AUTOMATIC_ROLLBACK_FORCE_FAILURE


assert_equals \
    "31" \
    "$rollback_failure_forward_exit_code" \
    "Forward exit code must remain authoritative."


rollback_failure_session="$(
    stoleus_execution_get_session
)"


IFS=$'	' read -r \
    execution_id \
    mode \
    failure_policy \
    status \
    target \
    operation \
    started_at \
    finished_at \
    current_step \
    total_steps \
    failed_step_count \
    forward_exit_code \
    automatic_rollback \
    rollback_attempted \
    rollback_status \
    rollback_exit_code \
    <<< "$rollback_failure_session"


assert_equals \
    "true" \
    "$rollback_attempted" \
    "Rollback should have been attempted."


assert_equals \
    "failed" \
    "$rollback_status" \
    "Rollback failure was not recorded."


assert_equals \
    "47" \
    "$rollback_exit_code" \
    "Rollback exit code is incorrect."


assert_equals \
    "31" \
    "$forward_exit_code" \
    "Forward exit code should not change after rollback failure."


assert_equals \
    "1" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Rollback Result Registry should contain one failed rollback."


rollback_session_id="$(
    stoleus_rollback_executor_get_session_id
)"


assert_equals \
    "failed" \
    "$(stoleus_rollback_result_registry_get_field \
        "$rollback_session_id" \
        "1" \
        "status")" \
    "Rollback Result Registry stored the wrong status."


expected_log="$(
printf '%s
' \
    "forward:success:install" \
    "forward:failure:install" \
    "rollback:success:restore"
)"


assert_equals \
    "$expected_log" \
    "$(cat "$AUTOMATIC_ROLLBACK_LOG")" \
    "Rollback failure execution order is incorrect."

# ==============================================================================
# Scenario 5 — Dry-run suppresses automatic rollback.
# ==============================================================================

: > "$AUTOMATIC_ROLLBACK_LOG"

unset AUTOMATIC_ROLLBACK_FORCE_FAILURE || true


# Reset forward and rollback runtime state.
stoleus_execution_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_rollback_planner_reset
stoleus_rollback_executor_reset
stoleus_rollback_result_registry_reset


# Build a plan that would fail during real execution.
stoleus_planning_create_request \
    "failure" \
    "install" \
    "stage"

stoleus_planning_build_plan


# Dry-run skips all forward functions. Because no real failure occurs,
# automatic rollback must not be attempted.
stoleus_execution_execute_plan \
    --dry-run \
    --automatic-rollback


dry_run_session="$(
    stoleus_execution_get_session
)"


IFS=$'	' read -r \
    dry_run_execution_id \
    dry_run_mode \
    dry_run_failure_policy \
    dry_run_status \
    dry_run_target \
    dry_run_operation \
    dry_run_started_at \
    dry_run_finished_at \
    dry_run_current_step \
    dry_run_total_steps \
    dry_run_failed_step_count \
    dry_run_forward_exit_code \
    dry_run_automatic_rollback \
    dry_run_rollback_attempted \
    dry_run_rollback_status \
    dry_run_rollback_exit_code \
    <<< "$dry_run_session"


assert_equals \
    "dry-run" \
    "$dry_run_mode" \
    "Automatic-rollback dry-run session mode is incorrect."


assert_equals \
    "succeeded" \
    "$dry_run_status" \
    "Dry-run execution should complete successfully."


assert_equals \
    "0" \
    "$dry_run_forward_exit_code" \
    "Dry-run execution exit code is incorrect."


assert_equals \
    "true" \
    "$dry_run_automatic_rollback" \
    "Automatic rollback should remain enabled in dry-run metadata."


assert_equals \
    "false" \
    "$dry_run_rollback_attempted" \
    "Dry-run must not attempt automatic rollback."


assert_equals \
    "not-needed" \
    "$dry_run_rollback_status" \
    "Dry-run rollback status is incorrect."


assert_equals \
    "0" \
    "$dry_run_rollback_exit_code" \
    "Dry-run rollback exit code should remain zero."


assert_equals \
    "0" \
    "$(stoleus_rollback_plan_get_count)" \
    "Dry-run should not build a Rollback Plan."


assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Dry-run should not create rollback results."


if [[ -s "$AUTOMATIC_ROLLBACK_LOG" ]]; then

    fail \
        "Dry-run unexpectedly invoked forward or rollback lifecycle functions."
fi


# ==============================================================================
# Scenario 6 — Continue policy delays rollback until forward traversal completes.
# ==============================================================================

: > "$AUTOMATIC_ROLLBACK_LOG"

unset AUTOMATIC_ROLLBACK_FORCE_FAILURE || true

stoleus_execution_reset
stoleus_planning_reset

STOLEUS_PLANNING_REQUEST_CREATED="false"

stoleus_rollback_planner_reset
stoleus_rollback_executor_reset
stoleus_rollback_result_registry_reset


#
# Build:
#
# success
# failure (depends on success)
#
# Continue policy ensures traversal completes before rollback.
#

stoleus_planning_create_request \
    "failure" \
    "install" \
    "stage"

stoleus_planning_build_plan


set +e

stoleus_execution_execute_plan \
    --failure-policy continue \
    --automatic-rollback

continue_exit_code=$?

set -e


assert_equals \
    "31" \
    "$continue_exit_code" \
    "Continue policy should preserve the original forward failure."


continue_session="$(
    stoleus_execution_get_session
)"

IFS=$'	' read -r \
    execution_id \
    mode \
    failure_policy \
    status \
    target \
    operation \
    started_at \
    finished_at \
    current_step \
    total_steps \
    failed_step_count \
    forward_exit_code \
    automatic_rollback \
    rollback_attempted \
    rollback_status \
    rollback_exit_code \
    <<< "$continue_session"


assert_equals \
    "continue" \
    "$failure_policy" \
    "Failure policy was not recorded correctly."


assert_equals \
    "true" \
    "$rollback_attempted" \
    "Rollback should have been attempted."


assert_equals \
    "succeeded" \
    "$rollback_status" \
    "Rollback should succeed under continue policy."


assert_equals \
    "31" \
    "$forward_exit_code" \
    "Forward exit code changed unexpectedly."


assert_equals \
    "0" \
    "$rollback_exit_code" \
    "Rollback exit code is incorrect."


expected_log="$(
printf '%s
' \
    "forward:success:install" \
    "forward:failure:install" \
    "rollback:success:restore"
)"

assert_equals \
    "$expected_log" \
    "$(cat "$AUTOMATIC_ROLLBACK_LOG")" \
    "Rollback occurred before forward traversal completed."

printf '%s
' \
    "PASS: Automatic Rollback integration tests completed successfully."

