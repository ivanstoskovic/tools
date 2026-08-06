#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Result Registry Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


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


stoleus_kernel_initialize
stoleus_execution_reset


STOLEUS_PLANNING_INITIALIZED="true"
STOLEUS_PLANNING_REQUEST_CREATED="true"
STOLEUS_PLANNING_REQUEST_TARGET="chrony"
STOLEUS_PLANNING_REQUEST_OPERATION="install"
STOLEUS_PLANNING_REQUEST_ARGUMENTS=()

STOLEUS_PLAN_FROZEN="true"

STOLEUS_PLAN_STEP_PLUGIN_IDS=("chrony")
STOLEUS_PLAN_STEP_REGISTRY_INDEXES=("0")
STOLEUS_PLAN_STEP_STAGES=("install")
STOLEUS_PLAN_STEP_FUNCTIONS=("chrony_install")
STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=("true")

STOLEUS_LIFECYCLE_INITIALIZED="true"


stoleus_lifecycle_invoke() {

    return 0
}


stoleus_execution_execute_plan


assert_equals \
    "1" \
    "$(stoleus_execution_result_registry_get_count)" \
    "Result Registry should contain one result."


assert_equals \
    "1" \
    "${#STOLEUS_EXECUTION_RESULT_STEP_NUMBERS[@]}" \
    "Compatibility result arrays should remain synchronized."


expected_standard="$(
    printf '%s\n' \
        $'1\tchrony\tinstall\tchrony_install\tsucceeded\t0'
)"


assert_equals \
    "$expected_standard" \
    "$(stoleus_execution_get_results)" \
    "Standard execution-result output changed."


detailed="$(
    stoleus_execution_get_detailed_results
)"


IFS=$'\t' read -r \
    result_id \
    execution_id \
    mode \
    step_number \
    plugin_id \
    stage \
    function_name \
    status \
    exit_code \
    started_at \
    finished_at \
    duration_ms \
    <<< "$detailed"


if [[ -z "$result_id" || -z "$execution_id" ]]; then
    fail "Detailed result identifiers should be populated."
fi


assert_equals \
    "execute" \
    "$mode" \
    "Detailed result mode is incorrect."


assert_equals \
    "1" \
    "$step_number" \
    "Detailed result step number is incorrect."


assert_equals \
    "chrony" \
    "$plugin_id" \
    "Detailed result plugin is incorrect."


assert_equals \
    "succeeded" \
    "$status" \
    "Detailed result status is incorrect."


if [[ -z "$started_at" || -z "$finished_at" ]]; then
    fail "Detailed result timestamps should be populated."
fi


if [[ ! "$duration_ms" =~ ^[0-9]+$ ]]; then
    fail "Detailed result duration should be numeric."
fi


stoleus_execution_reset


assert_equals \
    "0" \
    "$(stoleus_execution_result_registry_get_count)" \
    "Execution reset should clear the Result Registry."


printf '%s\n' \
    "PASS: Execution Result Registry tests completed successfully."
