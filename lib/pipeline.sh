#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Pipeline Execution Engine
# ==============================================================================
#
# Purpose:
#     Provide a reusable engine for running named operations in sequence.
#
# The pipeline engine is intentionally generic. It is not limited to server
# setup and can later be reused for:
#
#     - server provisioning
#     - deployments
#     - backups
#     - restores
#     - repair workflows
#     - maintenance operations
#
# Example:
#
#     pipeline_begin "Application server"
#
#     pipeline_step "Chrony" setup_chrony
#     pipeline_step "Firewall" setup_firewall
#     pipeline_step "Docker" setup_docker
#
#     pipeline_end
#
# The profile does not need to:
#
#     - manually count steps
#     - implement repeated if statements
#     - print progress
#     - produce failure summaries
#
# The pipeline engine handles those responsibilities centrally.
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
#
# -E
#     Preserve ERR traps inside functions and subshells.
#
# -e
#     Stop on unexpected failures.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     Make a pipeline fail when any important command inside it fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# Pipeline State
# ==============================================================================
#
# These variables describe the pipeline currently being constructed or run.
#
# They are reset every time:
#
#     pipeline_begin
#
# is called.
# ==============================================================================


# ------------------------------------------------------------------------------
# Human-readable pipeline name.
#
# Example:
#
#     Application server
# ------------------------------------------------------------------------------
PIPELINE_NAME=""


# ------------------------------------------------------------------------------
# Number of the step currently being executed.
# ------------------------------------------------------------------------------
PIPELINE_CURRENT_STEP=0


# ------------------------------------------------------------------------------
# Number of successfully completed steps.
# ------------------------------------------------------------------------------
PIPELINE_COMPLETED_STEPS=0


# ------------------------------------------------------------------------------
# Name of the failed step, if any.
# ------------------------------------------------------------------------------
PIPELINE_FAILED_STEP=""


# ------------------------------------------------------------------------------
# Exit code returned by the failed step.
#
# Zero means that no step has failed.
# ------------------------------------------------------------------------------
PIPELINE_FAILED_EXIT_CODE=0


# ------------------------------------------------------------------------------
# Arrays containing registered pipeline steps.
#
# The same array index connects:
#
#     step name
#     function name
#
# Example:
#
#     PIPELINE_STEP_NAMES[0]="Chrony"
#     PIPELINE_STEP_FUNCTIONS[0]="setup_chrony"
# ------------------------------------------------------------------------------
declare -a PIPELINE_STEP_NAMES=()
declare -a PIPELINE_STEP_FUNCTIONS=()


# ==============================================================================
# pipeline_reset
# ==============================================================================
#
# Purpose:
#     Clear all state from a previous pipeline.
#
# This is an internal helper called by:
#
#     pipeline_begin
# ==============================================================================
pipeline_reset() {

    PIPELINE_NAME=""

    PIPELINE_CURRENT_STEP=0
    PIPELINE_COMPLETED_STEPS=0

    PIPELINE_FAILED_STEP=""
    PIPELINE_FAILED_EXIT_CODE=0

    PIPELINE_STEP_NAMES=()
    PIPELINE_STEP_FUNCTIONS=()
}


# ==============================================================================
# pipeline_begin
# ==============================================================================
#
# Purpose:
#     Start defining a new pipeline.
#
# Usage:
#
#     pipeline_begin "Application server"
#
# `$1`
#     Human-readable pipeline name.
#
# This function does not execute anything yet. It only initializes the pipeline.
# ==============================================================================
pipeline_begin() {

    local pipeline_name="${1:-}"


    # --------------------------------------------------------------------------
    # A pipeline must have a meaningful name for progress and summary output.
    # --------------------------------------------------------------------------
    if [[ -z "$pipeline_name" ]]; then

        log_error "pipeline_begin was called without a pipeline name."

        return 2
    fi


    # --------------------------------------------------------------------------
    # Remove state left by any previously executed pipeline.
    # --------------------------------------------------------------------------
    pipeline_reset


    # --------------------------------------------------------------------------
    # Store the new pipeline name.
    # --------------------------------------------------------------------------
    PIPELINE_NAME="$pipeline_name"

    return 0
}


# ==============================================================================
# pipeline_step
# ==============================================================================
#
# Purpose:
#     Register one named function as a pipeline step.
#
# Usage:
#
#     pipeline_step "Chrony" setup_chrony
#
# Arguments:
#
#     $1 = human-readable step name
#     $2 = Bash function that implements the step
#
# This function registers the step but does not run it yet.
#
# Registering every step first allows the engine to calculate the total number
# of steps automatically.
# ==============================================================================
pipeline_step() {

    local step_name="${1:-}"
    local step_function="${2:-}"


    # --------------------------------------------------------------------------
    # Verify that pipeline_begin was called first.
    # --------------------------------------------------------------------------
    if [[ -z "$PIPELINE_NAME" ]]; then

        log_error "No pipeline has been started."
        log_error "Call pipeline_begin before pipeline_step."

        return 2
    fi


    # --------------------------------------------------------------------------
    # Every step needs a human-readable name.
    # --------------------------------------------------------------------------
    if [[ -z "$step_name" ]]; then

        log_error "pipeline_step was called without a step name."

        return 2
    fi


    # --------------------------------------------------------------------------
    # Every step must reference a Bash function.
    # --------------------------------------------------------------------------
    if [[ -z "$step_function" ]]; then

        log_error "No function was provided for pipeline step: $step_name"

        return 2
    fi


    # --------------------------------------------------------------------------
    # Confirm that the requested implementation function currently exists.
    #
    # `declare -F`
    #     Checks whether a Bash function has been defined.
    # --------------------------------------------------------------------------
    if ! declare -F "$step_function" >/dev/null 2>&1; then

        log_error "Pipeline step function does not exist: $step_function"

        return 2
    fi


    # --------------------------------------------------------------------------
    # Add the step name and implementation function to matching array indexes.
    #
    # `+=`
    #     Appends a new element to a Bash array.
    # --------------------------------------------------------------------------
    PIPELINE_STEP_NAMES+=("$step_name")
    PIPELINE_STEP_FUNCTIONS+=("$step_function")

    return 0
}


# ==============================================================================
# pipeline_step_count
# ==============================================================================
#
# Purpose:
#     Return the number of registered pipeline steps.
#
# `${#array[@]}`
#     Returns the number of elements in a Bash array.
# ==============================================================================
pipeline_step_count() {

    printf '%s\n' "${#PIPELINE_STEP_NAMES[@]}"
}


# ==============================================================================
# pipeline_validate
# ==============================================================================
#
# Purpose:
#     Verify that a pipeline is ready to execute.
# ==============================================================================
pipeline_validate() {

    local total_steps


    if [[ -z "$PIPELINE_NAME" ]]; then

        log_error "No pipeline has been defined."

        return 2
    fi


    total_steps="$(pipeline_step_count)"


    if (( total_steps == 0 )); then

        log_error "Pipeline has no registered steps: $PIPELINE_NAME"

        return 2
    fi


    # --------------------------------------------------------------------------
    # Both arrays must always contain the same number of elements.
    #
    # If they differ, the internal pipeline state is inconsistent.
    # --------------------------------------------------------------------------
    if (( ${#PIPELINE_STEP_NAMES[@]} != ${#PIPELINE_STEP_FUNCTIONS[@]} )); then

        log_error "Pipeline step metadata is inconsistent."

        return 2
    fi


    return 0
}


# ==============================================================================
# pipeline_print_start
# ==============================================================================
#
# Purpose:
#     Print the pipeline header before execution begins.
# ==============================================================================
pipeline_print_start() {

    local total_steps

    total_steps="$(pipeline_step_count)"

    echo
    log_info "Starting pipeline: $PIPELINE_NAME"
    log_info "Total steps: $total_steps"
}


# ==============================================================================
# pipeline_print_failure_summary
# ==============================================================================
#
# Purpose:
#     Print a consistent summary when a pipeline step fails.
# ==============================================================================
pipeline_print_failure_summary() {

    local total_steps

    total_steps="$(pipeline_step_count)"

    echo

    log_error "Pipeline failed: $PIPELINE_NAME"
    log_error "Completed ${PIPELINE_COMPLETED_STEPS}/${total_steps} steps."


    if [[ -n "$PIPELINE_FAILED_STEP" ]]; then

        log_error "Failed step: $PIPELINE_FAILED_STEP"
    fi


    if (( PIPELINE_FAILED_EXIT_CODE != 0 )); then

        log_error "Step exit code: $PIPELINE_FAILED_EXIT_CODE"
    fi
}


# ==============================================================================
# pipeline_print_success_summary
# ==============================================================================
#
# Purpose:
#     Print a consistent summary after every step succeeds.
# ==============================================================================
pipeline_print_success_summary() {

    local total_steps

    total_steps="$(pipeline_step_count)"

    echo

    log_success \
        "${PIPELINE_NAME} pipeline completed successfully: ${PIPELINE_COMPLETED_STEPS}/${total_steps} steps."
}


# ==============================================================================
# pipeline_end
# ==============================================================================
#
# Purpose:
#     Execute every registered step in order.
#
# Behavior:
#
#     - calculates the step count automatically
#     - prints progress
#     - stops after the first failed step
#     - colors successful step results green
#     - colors failed step results red
#     - prints a final summary
#
# Return values:
#
#     0 = every step completed successfully
#     non-zero = a step failed or the pipeline definition is invalid
# ==============================================================================
pipeline_end() {

    local total_steps
    local step_index
    local step_name
    local step_function
    local step_exit_code


    # --------------------------------------------------------------------------
    # Validate the complete definition before executing system changes.
    # --------------------------------------------------------------------------
    pipeline_validate || return $?


    total_steps="$(pipeline_step_count)"


    # --------------------------------------------------------------------------
    # Reset execution-specific counters.
    #
    # Registered steps and the pipeline name remain unchanged.
    # --------------------------------------------------------------------------
    PIPELINE_CURRENT_STEP=0
    PIPELINE_COMPLETED_STEPS=0
    PIPELINE_FAILED_STEP=""
    PIPELINE_FAILED_EXIT_CODE=0


    pipeline_print_start


    # --------------------------------------------------------------------------
    # Iterate over every registered array index.
    #
    # `${!PIPELINE_STEP_NAMES[@]}`
    #     Expands to all indexes currently present in the array.
    #
    # Example:
    #
    #     0 1 2
    # --------------------------------------------------------------------------
    for step_index in "${!PIPELINE_STEP_NAMES[@]}"; do

        step_name="${PIPELINE_STEP_NAMES[$step_index]}"
        step_function="${PIPELINE_STEP_FUNCTIONS[$step_index]}"

        PIPELINE_CURRENT_STEP=$((PIPELINE_CURRENT_STEP + 1))


        # ----------------------------------------------------------------------
        # Print a neutral heading before execution.
        #
        # We do not color this heading green or red because the result is not
        # known yet.
        # ----------------------------------------------------------------------
        echo
        printf '[%d/%d] %s\n' \
            "$PIPELINE_CURRENT_STEP" \
            "$total_steps" \
            "$step_name"


        # ----------------------------------------------------------------------
        # Execute the implementation inside an if statement so a non-zero result
        # can be captured and reported rather than terminating without a summary.
        #
        # Setup functions should explicitly propagate nested failures with:
        #
        #     command || return 1
        # ----------------------------------------------------------------------
        if "$step_function"; then

            PIPELINE_COMPLETED_STEPS=$((PIPELINE_COMPLETED_STEPS + 1))


            # ------------------------------------------------------------------
            # Print the completed counter in green.
            # ------------------------------------------------------------------
            print_step_success \
                "$PIPELINE_CURRENT_STEP" \
                "$total_steps" \
                "$step_name"

            continue
        else

            step_exit_code=$?

            PIPELINE_FAILED_STEP="$step_name"
            PIPELINE_FAILED_EXIT_CODE="$step_exit_code"


            # ------------------------------------------------------------------
            # Print the failed counter in red.
            # ------------------------------------------------------------------
            print_step_failure \
                "$PIPELINE_CURRENT_STEP" \
                "$total_steps" \
                "$step_name"

            pipeline_print_failure_summary

            return "$step_exit_code"
        fi
    done


    pipeline_print_success_summary

    return 0
}