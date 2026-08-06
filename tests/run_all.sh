#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Unified Test Runner
# ==============================================================================
#
# Usage:
#
#     bash tests/run_all.sh
#     bash tests/run_all.sh capability
#     bash tests/run_all.sh registry
#     bash tests/run_all.sh --verbose
#     bash tests/run_all.sh --list
#     bash tests/run_all.sh --help
#
# Selection:
#
#     With no filter, every tests/kernel/*_test.sh file is executed.
#
#     A positional filter selects tests whose filename contains that value:
#
#         bash tests/run_all.sh capability
#
#     executes:
#
#         capability_definition_test.sh
#         capability_registry_test.sh
#         capability_resolver_test.sh
#
# Exit codes:
#
#     0 = every selected test passed
#     1 = one or more tests failed
#     2 = invalid runner arguments
#     6 = test discovery or environment error
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Paths
# ==============================================================================

TESTS_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

PROJECT_ROOT="$(
    cd -- "${TESTS_ROOT}/.." &&
    pwd
)"

KERNEL_TEST_ROOT="${TESTS_ROOT}/kernel"


# ==============================================================================
# Runner Configuration
# ==============================================================================

STOLEUS_TEST_RUNNER_VERBOSE="false"
STOLEUS_TEST_RUNNER_LIST_ONLY="false"
STOLEUS_TEST_RUNNER_FILTER=""


# ==============================================================================
# Runtime State
# ==============================================================================

declare -a STOLEUS_TEST_FILES=()
declare -a STOLEUS_TEST_NAMES=()
declare -a STOLEUS_TEST_RESULTS=()
declare -a STOLEUS_TEST_DURATIONS_MS=()
declare -a STOLEUS_TEST_EXIT_CODES=()
declare -a STOLEUS_TEST_OUTPUT_FILES=()

STOLEUS_TEST_TEMP_ROOT=""

STOLEUS_TEST_EXECUTED_COUNT=0
STOLEUS_TEST_PASSED_COUNT=0
STOLEUS_TEST_FAILED_COUNT=0

STOLEUS_TEST_SUITE_START_MS=0
STOLEUS_TEST_SUITE_END_MS=0


# ==============================================================================
# stoleus_test_runner_cleanup
# ==============================================================================

stoleus_test_runner_cleanup() {

    if [[ -n "$STOLEUS_TEST_TEMP_ROOT" &&
          -d "$STOLEUS_TEST_TEMP_ROOT" ]]; then

        rm -rf -- "$STOLEUS_TEST_TEMP_ROOT"
    fi
}


# ==============================================================================
# stoleus_test_runner_print_usage
# ==============================================================================

stoleus_test_runner_print_usage() {

    cat <<'USAGE'
Usage:
    bash tests/run_all.sh [options] [filter]

Options:
    -v, --verbose   Print output from every test.
    -l, --list      List selected tests without executing them.
    -h, --help      Show this help text.

Filter:
    Select tests whose filename contains the supplied text.

Examples:
    bash tests/run_all.sh
    bash tests/run_all.sh capability
    bash tests/run_all.sh registry
    bash tests/run_all.sh --verbose service
    bash tests/run_all.sh --list
USAGE
}


# ==============================================================================
# stoleus_test_runner_parse_arguments
# ==============================================================================

stoleus_test_runner_parse_arguments() {

    local argument=""


    while (( $# > 0 )); do

        argument="$1"

        case "$argument" in

            -v|--verbose)
                STOLEUS_TEST_RUNNER_VERBOSE="true"
                ;;


            -l|--list)
                STOLEUS_TEST_RUNNER_LIST_ONLY="true"
                ;;


            -h|--help)
                stoleus_test_runner_print_usage
                exit 0
                ;;


            --)
                shift

                if (( $# > 1 )); then

                    printf '%s\n' \
                        "ERROR: Only one test filter may be supplied." >&2

                    return 2
                fi

                if (( $# == 1 )); then
                    STOLEUS_TEST_RUNNER_FILTER="$1"
                fi

                return 0
                ;;


            -*)

                printf '%s\n' \
                    "ERROR: Unknown test-runner option: ${argument}" >&2

                return 2

                ;;


            *)

                if [[ -n "$STOLEUS_TEST_RUNNER_FILTER" ]]; then

                    printf '%s\n' \
                        "ERROR: Only one test filter may be supplied." >&2

                    return 2
                fi

                STOLEUS_TEST_RUNNER_FILTER="$argument"

                ;;
        esac

        shift
    done


    return 0
}


# ==============================================================================
# stoleus_test_runner_now_ms
# ==============================================================================

stoleus_test_runner_now_ms() {

    local timestamp=""


    # GNU date is available in Git Bash and common Linux environments.
    if timestamp="$(date +%s%3N 2>/dev/null)" &&
       [[ "$timestamp" =~ ^[0-9]+$ ]]; then

        printf '%s\n' "$timestamp"

        return 0
    fi


    # Portable fallback with one-second precision.
    timestamp="$(date +%s)"

    printf '%s\n' "$((timestamp * 1000))"

    return 0
}


# ==============================================================================
# stoleus_test_runner_format_duration
# ==============================================================================

stoleus_test_runner_format_duration() {

    local duration_ms="${1:-0}"

    local seconds=0
    local milliseconds=0


    if [[ ! "$duration_ms" =~ ^[0-9]+$ ]]; then
        duration_ms=0
    fi


    seconds="$((duration_ms / 1000))"
    milliseconds="$((duration_ms % 1000))"


    printf '%d.%03ds\n' \
        "$seconds" \
        "$milliseconds"

    return 0
}


# ==============================================================================
# stoleus_test_runner_format_name
# ==============================================================================

stoleus_test_runner_format_name() {

    local test_file="${1:-}"
    local test_name=""


    test_name="$(basename -- "$test_file")"
    test_name="${test_name%_test.sh}"
    test_name="${test_name//_/ }"


    printf '%s\n' "$test_name"

    return 0
}


# ==============================================================================
# stoleus_test_runner_discover
# ==============================================================================

stoleus_test_runner_discover() {

    local test_file=""
    local test_basename=""


    if [[ ! -d "$KERNEL_TEST_ROOT" ]]; then

        printf '%s\n' \
            "ERROR: Kernel test directory does not exist: ${KERNEL_TEST_ROOT}" \
            >&2

        return 6
    fi


    STOLEUS_TEST_FILES=()
    STOLEUS_TEST_NAMES=()


    while IFS= read -r test_file; do

        [[ -z "$test_file" ]] && continue

        test_basename="$(basename -- "$test_file")"


        if [[ -n "$STOLEUS_TEST_RUNNER_FILTER" ]] &&
           [[ "$test_basename" != *"$STOLEUS_TEST_RUNNER_FILTER"* ]]; then

            continue
        fi


        STOLEUS_TEST_FILES+=("$test_file")

        STOLEUS_TEST_NAMES+=(
            "$(
                stoleus_test_runner_format_name \
                    "$test_file"
            )"
        )

    done < <(
        find "$KERNEL_TEST_ROOT" \
            -maxdepth 1 \
            -type f \
            -name '*_test.sh' \
            -print |
            LC_ALL=C sort
    )


    if (( ${#STOLEUS_TEST_FILES[@]} == 0 )); then

        if [[ -n "$STOLEUS_TEST_RUNNER_FILTER" ]]; then

            printf '%s\n' \
                "ERROR: No kernel tests match filter: ${STOLEUS_TEST_RUNNER_FILTER}" \
                >&2

        else
            printf '%s\n' \
                "ERROR: No kernel tests were discovered." >&2
        fi

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_test_runner_print_header
# ==============================================================================

stoleus_test_runner_print_header() {

    printf '%s\n' \
        "============================================================" \
        " Stoleus Kernel Test Suite" \
        "============================================================"


    if [[ -n "$STOLEUS_TEST_RUNNER_FILTER" ]]; then

        printf ' Filter: %s\n' \
            "$STOLEUS_TEST_RUNNER_FILTER"
    fi


    printf ' Tests:  %s\n' \
        "${#STOLEUS_TEST_FILES[@]}"

    printf '%s\n\n' \
        "============================================================"
}


# ==============================================================================
# stoleus_test_runner_list
# ==============================================================================

stoleus_test_runner_list() {

    local test_index=0


    for test_index in "${!STOLEUS_TEST_FILES[@]}"; do

        printf '%2d. %-32s %s\n' \
            "$((test_index + 1))" \
            "${STOLEUS_TEST_NAMES[$test_index]}" \
            "${STOLEUS_TEST_FILES[$test_index]#${PROJECT_ROOT}/}"
    done


    return 0
}


# ==============================================================================
# stoleus_test_runner_print_test_output
# ==============================================================================

stoleus_test_runner_print_test_output() {

    local output_file="${1:-}"


    if [[ -z "$output_file" || ! -f "$output_file" ]]; then
        return 0
    fi


    if [[ ! -s "$output_file" ]]; then

        printf '%s\n' \
            "    (test produced no output)"

        return 0
    fi


    while IFS= read -r output_line || [[ -n "$output_line" ]]; do
        printf '    %s\n' "$output_line"
    done < "$output_file"


    return 0
}


# ==============================================================================
# stoleus_test_runner_execute_one
# ==============================================================================

stoleus_test_runner_execute_one() {

    local test_index="${1:-0}"

    local test_file="${STOLEUS_TEST_FILES[$test_index]}"
    local test_name="${STOLEUS_TEST_NAMES[$test_index]}"
    local output_file="${STOLEUS_TEST_TEMP_ROOT}/test-${test_index}.log"

    local start_ms=0
    local end_ms=0
    local duration_ms=0
    local exit_code=0
    local result=""


    start_ms="$(
        stoleus_test_runner_now_ms
    )"


    set +e

    (
        cd -- "$PROJECT_ROOT" &&
        bash "$test_file"
    ) > "$output_file" 2>&1

    exit_code=$?

    set -e


    end_ms="$(
        stoleus_test_runner_now_ms
    )"

    duration_ms="$((end_ms - start_ms))"


    if (( duration_ms < 0 )); then
        duration_ms=0
    fi


    STOLEUS_TEST_EXECUTED_COUNT="$((STOLEUS_TEST_EXECUTED_COUNT + 1))"

    STOLEUS_TEST_OUTPUT_FILES[$test_index]="$output_file"
    STOLEUS_TEST_DURATIONS_MS[$test_index]="$duration_ms"
    STOLEUS_TEST_EXIT_CODES[$test_index]="$exit_code"


    if (( exit_code == 0 )); then

        result="PASS"
        STOLEUS_TEST_PASSED_COUNT="$((STOLEUS_TEST_PASSED_COUNT + 1))"

    else
        result="FAIL"
        STOLEUS_TEST_FAILED_COUNT="$((STOLEUS_TEST_FAILED_COUNT + 1))"
    fi


    STOLEUS_TEST_RESULTS[$test_index]="$result"


    printf '%-38s %-4s  %s\n' \
        "$test_name" \
        "$result" \
        "$(
            stoleus_test_runner_format_duration \
                "$duration_ms"
        )"


    if [[ "$STOLEUS_TEST_RUNNER_VERBOSE" == "true" ||
          "$result" == "FAIL" ]]; then

        stoleus_test_runner_print_test_output \
            "$output_file"

        printf '\n'
    fi


    return 0
}


# ==============================================================================
# stoleus_test_runner_execute_all
# ==============================================================================

stoleus_test_runner_execute_all() {

    local test_index=0


    STOLEUS_TEST_SUITE_START_MS="$(
        stoleus_test_runner_now_ms
    )"


    for test_index in "${!STOLEUS_TEST_FILES[@]}"; do

        stoleus_test_runner_execute_one \
            "$test_index" ||
            return $?
    done


    STOLEUS_TEST_SUITE_END_MS="$(
        stoleus_test_runner_now_ms
    )"


    return 0
}


# ==============================================================================
# stoleus_test_runner_print_failures
# ==============================================================================

stoleus_test_runner_print_failures() {

    local test_index=0
    local failure_number=0


    if (( STOLEUS_TEST_FAILED_COUNT == 0 )); then
        return 0
    fi


    printf '%s\n' \
        "Failed tests:"


    for test_index in "${!STOLEUS_TEST_FILES[@]}"; do

        if [[ "${STOLEUS_TEST_RESULTS[$test_index]:-}" != "FAIL" ]]; then
            continue
        fi


        failure_number="$((failure_number + 1))"

        printf '  %d. %s (exit code %s)\n' \
            "$failure_number" \
            "${STOLEUS_TEST_FILES[$test_index]#${PROJECT_ROOT}/}" \
            "${STOLEUS_TEST_EXIT_CODES[$test_index]}"
    done


    printf '\n'

    return 0
}


# ==============================================================================
# stoleus_test_runner_print_summary
# ==============================================================================

stoleus_test_runner_print_summary() {

    local suite_duration_ms=0


    suite_duration_ms="$((STOLEUS_TEST_SUITE_END_MS - STOLEUS_TEST_SUITE_START_MS))"


    if (( suite_duration_ms < 0 )); then
        suite_duration_ms=0
    fi


    printf '\n%s\n' \
        "============================================================"

    printf 'Executed : %s\n' \
        "$STOLEUS_TEST_EXECUTED_COUNT"

    printf 'Passed   : %s\n' \
        "$STOLEUS_TEST_PASSED_COUNT"

    printf 'Failed   : %s\n' \
        "$STOLEUS_TEST_FAILED_COUNT"

    printf 'Time     : %s\n' \
        "$(
            stoleus_test_runner_format_duration \
                "$suite_duration_ms"
        )"

    printf '%s\n' \
        "============================================================"


    stoleus_test_runner_print_failures


    if (( STOLEUS_TEST_FAILED_COUNT == 0 )); then

        printf '%s\n' "PASS"

        return 0
    fi


    printf '%s\n' "FAIL"

    return 1
}


# ==============================================================================
# stoleus_test_runner_main
# ==============================================================================

stoleus_test_runner_main() {

    stoleus_test_runner_parse_arguments "$@" || return $?
    stoleus_test_runner_discover || return $?


    if [[ "$STOLEUS_TEST_RUNNER_LIST_ONLY" == "true" ]]; then

        stoleus_test_runner_list

        return 0
    fi


    STOLEUS_TEST_TEMP_ROOT="$(
        mktemp -d
    )" || return 6


    stoleus_test_runner_print_header
    stoleus_test_runner_execute_all || return $?
    stoleus_test_runner_print_summary

    return $?
}


# ==============================================================================
# Entry Point
# ==============================================================================

trap stoleus_test_runner_cleanup EXIT


stoleus_test_runner_main "$@"
