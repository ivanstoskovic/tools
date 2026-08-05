#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Component Registry
# ==============================================================================
#
# Purpose:
#     Register setup components and validate their metadata and entry functions.
#
# A component registration contains:
#
#     - a unique component ID;
#     - the entry function;
#     - a human-readable description;
#     - the implementation file;
#     - framework dependencies;
#     - component dependencies.
#
# Bash has no objects or classes, so associative arrays store component
# metadata by component ID.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Component Registry State
# ==============================================================================

declare -a STOLEUS_COMPONENT_IDS=()


# ==============================================================================
# Component Lifecycle Functions
# ==============================================================================
#
# Each lifecycle stage is optional.
#
# A component may expose:
#
#     install
#     configure
#     verify
#     upgrade
#     remove
#
# During migration, the existing entry function remains supported.
# ==============================================================================

declare -A STOLEUS_COMPONENT_INSTALL_FUNCTIONS=()
declare -A STOLEUS_COMPONENT_CONFIGURE_FUNCTIONS=()
declare -A STOLEUS_COMPONENT_VERIFY_FUNCTIONS=()
declare -A STOLEUS_COMPONENT_UPGRADE_FUNCTIONS=()
declare -A STOLEUS_COMPONENT_REMOVE_FUNCTIONS=()


declare -A STOLEUS_COMPONENT_ENTRY_FUNCTIONS=()
declare -A STOLEUS_COMPONENT_DESCRIPTIONS=()
declare -A STOLEUS_COMPONENT_IMPLEMENTATION_FILES=()
declare -A STOLEUS_COMPONENT_FRAMEWORK_DEPENDENCIES=()
declare -A STOLEUS_COMPONENT_DEPENDENCIES=()
declare -A STOLEUS_COMPONENT_ARGUMENT_VALIDATORS=()

# ==============================================================================
# Component Dependency Resolution State
# ==============================================================================
#
# STOLEUS_COMPONENT_RESOLUTION_VISITING
#     Components currently being traversed.
#
#     Encountering one of these components again indicates a dependency cycle.
#
# STOLEUS_COMPONENT_RESOLUTION_RESOLVED
#     Components whose complete dependency subtree has already been resolved.
#
# STOLEUS_COMPONENT_EXECUTION_PLAN
#     Ordered component IDs.
#
#     Dependencies appear before the components that require them.
# ==============================================================================
declare -A STOLEUS_COMPONENT_RESOLUTION_VISITING=()
declare -A STOLEUS_COMPONENT_RESOLUTION_RESOLVED=()

declare -a STOLEUS_COMPONENT_EXECUTION_PLAN=()


# ==============================================================================
# component_is_registered
# ==============================================================================
#
# Purpose:
#     Determine whether a component ID has already been registered.
#
# Arguments:
#
#     $1 = component ID
#
# Return codes:
#
#     0 = registered
#     1 = not registered
#     2 = invalid argument
# ==============================================================================
component_is_registered() {

    local component_id="${1:-}"


    if [[ -z "$component_id" ]]; then

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    [[ -n "${STOLEUS_COMPONENT_ENTRY_FUNCTIONS[$component_id]+registered}" ]]
}


# ==============================================================================
# component_register
# ==============================================================================
#
# Purpose:
#     Register one setup component.
#
# Arguments:
#
#     $1 = unique component ID
#     $2 = entry function
#     $3 = human-readable description
#     $4 = implementation file
#     $5 = comma-separated framework dependencies
#     $6 = comma-separated component dependencies
#     $7 = optional argument-validator function
#
# Example:
#
#     component_register \
#         "chrony" \
#         "setup_chrony" \
#         "Install and verify Chrony" \
#         "lib/components/chrony.sh" \
#         "" \
#         ""
# ==============================================================================
component_register() {

    local component_id="${1:-}"
    local entry_function="${2:-}"
    local description="${3:-}"
    local implementation_file="${4:-}"
    local framework_dependencies="${5:-}"
    local component_dependencies="${6:-}"
	local argument_validator="${7:-}"


    if [[ -z "$component_id" ]]; then

        log_error "Component registration requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ ! "$component_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        log_error "Invalid component ID: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    if [[ -z "$entry_function" ]]; then

        log_error \
            "Component '${component_id}' requires an entry function."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ ! "$entry_function" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

        log_error \
            "Component '${component_id}' has an invalid entry function: $entry_function"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    if [[ -z "$description" ]]; then

        log_error \
            "Component '${component_id}' requires a description."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$implementation_file" ]]; then

        log_error \
            "Component '${component_id}' requires an implementation file."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if component_is_registered "$component_id"; then

        log_error "Component is already registered: $component_id"

        return "${STOLEUS_EXIT_CONFLICT:-8}"
    fi
	
	
	if [[ -n "$argument_validator" ]] &&
	   [[ ! "$argument_validator" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

		log_error \
			"Component '${component_id}' has an invalid argument validator: $argument_validator"

		return "${STOLEUS_EXIT_CONFIGURATION:-6}"
	fi


    STOLEUS_COMPONENT_IDS+=("$component_id")

    STOLEUS_COMPONENT_ENTRY_FUNCTIONS["$component_id"]="$entry_function"
    STOLEUS_COMPONENT_DESCRIPTIONS["$component_id"]="$description"
    STOLEUS_COMPONENT_IMPLEMENTATION_FILES["$component_id"]="$implementation_file"
    STOLEUS_COMPONENT_FRAMEWORK_DEPENDENCIES["$component_id"]="$framework_dependencies"
    STOLEUS_COMPONENT_DEPENDENCIES["$component_id"]="$component_dependencies"
	STOLEUS_COMPONENT_ARGUMENT_VALIDATORS["$component_id"]="$argument_validator"


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_verify_framework_dependencies
# ==============================================================================
#
# Purpose:
#     Verify that every framework module declared by a component exists.
#
# Arguments:
#
#     $1 = component ID
#
# Example manifest value:
#
#     text,filesystem,os,process
#
# Every dependency must be registered in:
#
#     STOLEUS_FRAMEWORK_API_MODULES
# ==============================================================================
component_verify_framework_dependencies() {

    local component_id="${1:-}"
    local framework_dependencies=""
    local dependency=""

    local failure_count=0


    if [[ -z "$component_id" ]]; then

        log_error \
            "Framework dependency verification requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$component_id"; then

        log_error \
            "Cannot verify dependencies for an unknown component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    framework_dependencies="$(
        printf '%s' \
            "${STOLEUS_COMPONENT_FRAMEWORK_DEPENDENCIES[$component_id]}"
    )"


    # --------------------------------------------------------------------------
    # An empty dependency declaration is valid.
    # --------------------------------------------------------------------------
    if [[ -z "$framework_dependencies" ]]; then

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    while IFS= read -r dependency; do

        # ----------------------------------------------------------------------
        # Remove surrounding whitespace.
        # ----------------------------------------------------------------------
        dependency="$(
            printf '%s' "$dependency" |
                sed -E \
                    's/^[[:space:]]+//; s/[[:space:]]+$//'
        )"


        [[ -z "$dependency" ]] && continue


        if ! framework_is_registered_module "$dependency"; then

            log_error \
                "Component '${component_id}' depends on an unknown framework module: ${dependency}"

            failure_count=$((failure_count + 1))
        fi

    done < <(
        printf '%s\n' "$framework_dependencies" |
            tr ',' '\n'
    )


    if (( failure_count > 0 )); then

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_verify_component_dependencies
# ==============================================================================
#
# Purpose:
#     Verify that every component dependency:
#
#         - references a registered component;
#         - does not reference the component itself.
#
# Arguments:
#
#     $1 = component ID
# ==============================================================================
component_verify_component_dependencies() {

    local component_id="${1:-}"
    local component_dependencies=""
    local dependency=""

    local failure_count=0


    if [[ -z "$component_id" ]]; then

        log_error \
            "Component dependency verification requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$component_id"; then

        log_error \
            "Cannot verify dependencies for an unknown component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    component_dependencies="$(
        printf '%s' \
            "${STOLEUS_COMPONENT_DEPENDENCIES[$component_id]}"
    )"


    if [[ -z "$component_dependencies" ]]; then

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    while IFS= read -r dependency; do

        dependency="$(
            printf '%s' "$dependency" |
                sed -E \
                    's/^[[:space:]]+//; s/[[:space:]]+$//'
        )"


        [[ -z "$dependency" ]] && continue


        if [[ "$dependency" == "$component_id" ]]; then

            log_error \
                "Component '${component_id}' cannot depend on itself."

            failure_count=$((failure_count + 1))

            continue
        fi


        if ! component_is_registered "$dependency"; then

            log_error \
                "Component '${component_id}' depends on an unknown component: ${dependency}"

            failure_count=$((failure_count + 1))
        fi

    done < <(
        printf '%s\n' "$component_dependencies" |
            tr ',' '\n'
    )


    if (( failure_count > 0 )); then

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_verify_dependencies
# ==============================================================================
#
# Purpose:
#     Verify all dependencies declared by one component.
#
# Arguments:
#
#     $1 = component ID
# ==============================================================================
component_verify_dependencies() {

    local component_id="${1:-}"


    if [[ -z "$component_id" ]]; then

        log_error \
            "Component dependency verification requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    component_verify_framework_dependencies \
        "$component_id" ||
        return $?


    component_verify_component_dependencies \
        "$component_id" ||
        return $?


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_verify_registry
# ==============================================================================
#
# Purpose:
#     Verify the complete component registry.
#
# Verification:
#
#     - at least one component is registered;
#     - every implementation file exists;
#     - every entry function exists;
#     - every framework dependency exists;
#     - every component dependency exists;
#     - no component depends on itself.
# ==============================================================================
component_verify_registry() {

    local component_id=""
    local entry_function=""
    local implementation_file=""
	local argument_validator=""
	
    local failure_count=0


    log_debug "Verifying Stoleus component registry."


    if (( ${#STOLEUS_COMPONENT_IDS[@]} == 0 )); then

        log_error "No Stoleus components were registered."

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    for component_id in "${STOLEUS_COMPONENT_IDS[@]}"; do

        entry_function="$(
            printf '%s' \
                "${STOLEUS_COMPONENT_ENTRY_FUNCTIONS[$component_id]}"
        )"

        implementation_file="$(
            printf '%s' \
                "${STOLEUS_COMPONENT_IMPLEMENTATION_FILES[$component_id]}"
        )"
		
		argument_validator="$(
			printf '%s' \
				"${STOLEUS_COMPONENT_ARGUMENT_VALIDATORS[$component_id]}"
		)"


        # ----------------------------------------------------------------------
        # Verify implementation file.
        # ----------------------------------------------------------------------
        if [[ ! -f "${PROJECT_ROOT}/${implementation_file}" ]]; then

            log_error \
                "Component '${component_id}' implementation file is missing: ${implementation_file}"

            failure_count=$((failure_count + 1))
        fi


        # ----------------------------------------------------------------------
        # Verify registered entry function.
        # ----------------------------------------------------------------------
        if ! declare -F "$entry_function" >/dev/null 2>&1; then

            log_error \
                "Component '${component_id}' entry function is missing: ${entry_function}"

            failure_count=$((failure_count + 1))
        fi


        # ----------------------------------------------------------------------
        # Verify framework and component dependency declarations.
        # ----------------------------------------------------------------------
        if ! component_verify_dependencies "$component_id"; then

            failure_count=$((failure_count + 1))
        fi
		
		
		if [[ -n "$argument_validator" ]] &&
		   ! declare -F "$argument_validator" >/dev/null 2>&1; then

			log_error \
				"Component '${component_id}' argument validator is missing: ${argument_validator}"

			failure_count=$((failure_count + 1))
		fi
    done


    if (( failure_count > 0 )); then

        log_error \
            "Component registry verification failed with ${failure_count} component error(s)."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    log_debug \
        "Component registry verification passed for ${#STOLEUS_COMPONENT_IDS[@]} components."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_get_entry_function
# ==============================================================================
#
# Purpose:
#     Return the entry function registered for a component.
# ==============================================================================
component_get_entry_function() {

    local component_id="${1:-}"


    if ! component_is_registered "$component_id"; then

        log_error "Unknown component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    printf '%s\n' \
        "${STOLEUS_COMPONENT_ENTRY_FUNCTIONS[$component_id]}"

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_print_registered
# ==============================================================================
#
# Purpose:
#     Print all registered setup components in a help-friendly format.
#
# Output format:
#
#     component-id    Description
#
# Example:
#
#     chrony          Install, enable, and verify Chrony
#     docker          Install Docker Engine, Buildx, and Docker Compose
#
# Arguments:
#
#     $1
#         Optional indentation string.
#
#     $2
#         Optional component-name column width.
#
# Defaults:
#
#     indentation = four spaces
#     column width = 16 characters
# ==============================================================================
component_print_registered() {

    local indentation="${1:-    }"
    local column_width="${2:-16}"

    local component_id
    local description


    if [[ ! "$column_width" =~ ^[1-9][0-9]*$ ]]; then

        log_error \
            "Component help column width must be a positive integer."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if (( ${#STOLEUS_COMPONENT_IDS[@]} == 0 )); then

        log_error \
            "No setup components are registered."

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    for component_id in "${STOLEUS_COMPONENT_IDS[@]}"; do

        description="${STOLEUS_COMPONENT_DESCRIPTIONS[$component_id]}"


        printf '%s%-*s%s\n' \
            "$indentation" \
            "$column_width" \
            "$component_id" \
            "$description"
    done


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_execute
# ==============================================================================
#
# Purpose:
#     Validate, resolve, and execute a registered setup component together with
#     all declared component dependencies.
#
# Execution lifecycle:
#
#     1. Validate the requested component.
#     2. Validate its command-line arguments.
#     3. Verify its dependency declarations.
#     4. Build a dependency-first execution plan.
#     5. Execute every dependency exactly once.
#     6. Execute the requested component last.
#
# Argument forwarding:
#
#     Component arguments are forwarded only to the originally requested
#     component.
#
#     Dependencies receive no arguments.
#
# Example:
#
#     component_execute "server" "stage"
#
# Plan:
#
#     chrony
#     firewall
#     docker
#     directories
#     server stage
# ==============================================================================
component_execute() {

    local requested_component="${1:-}"
    local planned_component=""

    local -a requested_arguments=()


    if [[ -z "$requested_component" ]]; then

        log_error \
            "component_execute requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$requested_component"; then

        log_error \
            "Unknown setup component: $requested_component"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    shift

    requested_arguments=("$@")


    # --------------------------------------------------------------------------
    # Validate before dependencies run.
    #
    # This prevents invalid input such as:
    #
    #     stoleus setup server unknown
    #
    # from modifying the server.
    # --------------------------------------------------------------------------
    component_validate_arguments \
        "$requested_component" \
        "${requested_arguments[@]}" ||
        return $?


    component_verify_dependencies \
        "$requested_component" ||
        return $?


    component_build_execution_plan \
        "$requested_component" ||
        return $?


    log_debug \
        "Resolved component execution plan: ${STOLEUS_COMPONENT_EXECUTION_PLAN[*]}"


    for planned_component in "${STOLEUS_COMPONENT_EXECUTION_PLAN[@]}"; do

        if [[ "$planned_component" == "$requested_component" ]]; then

            component_execute_single \
                "$planned_component" \
                "${requested_arguments[@]}" ||
                return $?

        else

            component_execute_single \
                "$planned_component" ||
                return $?
        fi
    done


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_parse_dependency_list
# ==============================================================================
#
# Purpose:
#     Convert a comma-separated dependency declaration into one normalized
#     dependency per output line.
#
# Arguments:
#
#     $1 = comma-separated dependency list
#
# Example:
#
#     component_parse_dependency_list \
#         "chrony, firewall,docker"
#
# Output:
#
#     chrony
#     firewall
#     docker
#
# Empty input produces no output and succeeds.
# ==============================================================================
component_parse_dependency_list() {

    local dependency_list="${1:-}"
    local dependency=""


    if [[ -z "$dependency_list" ]]; then

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    while IFS= read -r dependency; do

        # ----------------------------------------------------------------------
        # Remove leading and trailing whitespace.
        # ----------------------------------------------------------------------
        dependency="$(
            printf '%s' "$dependency" |
                sed -E \
                    's/^[[:space:]]+//; s/[[:space:]]+$//'
        )"


        if [[ -n "$dependency" ]]; then

            printf '%s\n' "$dependency"
        fi

    done < <(
        printf '%s\n' "$dependency_list" |
            tr ',' '\n'
    )


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_resolve_dependency_node
# ==============================================================================
#
# Purpose:
#     Recursively resolve one component and its dependencies.
#
# Algorithm:
#
#     Depth-first traversal with three logical states:
#
#         unvisited
#             The component has not yet been processed.
#
#         visiting
#             The component is currently in the recursion path.
#
#         resolved
#             The component and all its dependencies are already ordered.
#
# Cycle example:
#
#     component-a → component-b → component-a
#
# When component-a is encountered for the second time while still marked as
# visiting, the resolver reports a circular dependency.
#
# Ordering:
#
#     A component is appended only after all of its dependencies.
#
# Example:
#
#     server → chrony,firewall,docker,directories
#
# produces:
#
#     chrony
#     firewall
#     docker
#     directories
#     server
#
# Arguments:
#
#     $1 = registered component ID
# ==============================================================================
component_resolve_dependency_node() {

    local component_id="${1:-}"
    local dependency_list=""
    local dependency=""


    if [[ -z "$component_id" ]]; then

        log_error \
            "Dependency resolution requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$component_id"; then

        log_error \
            "Cannot resolve dependencies for an unknown component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    # --------------------------------------------------------------------------
    # Already completely resolved.
    #
    # This also ensures that a shared dependency appears only once.
    # --------------------------------------------------------------------------
    if [[ -n "${STOLEUS_COMPONENT_RESOLUTION_RESOLVED[$component_id]+resolved}" ]]; then

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    # --------------------------------------------------------------------------
    # Encountering a currently visiting component means the dependency graph
    # contains a cycle.
    # --------------------------------------------------------------------------
    if [[ -n "${STOLEUS_COMPONENT_RESOLUTION_VISITING[$component_id]+visiting}" ]]; then

        log_error \
            "Circular component dependency detected at: $component_id"

        return "${STOLEUS_EXIT_CONFLICT:-8}"
    fi


    STOLEUS_COMPONENT_RESOLUTION_VISITING["$component_id"]="true"


    dependency_list="$(
        printf '%s' \
            "${STOLEUS_COMPONENT_DEPENDENCIES[$component_id]}"
    )"


    # --------------------------------------------------------------------------
    # Resolve every dependency before the current component.
    # --------------------------------------------------------------------------
    while IFS= read -r dependency; do

        [[ -z "$dependency" ]] && continue


        component_resolve_dependency_node \
            "$dependency" ||
            return $?

    done < <(
        component_parse_dependency_list \
            "$dependency_list"
    )


    # --------------------------------------------------------------------------
    # The component is no longer part of the active recursion path.
    # --------------------------------------------------------------------------
    unset \
        'STOLEUS_COMPONENT_RESOLUTION_VISITING[$component_id]'


    STOLEUS_COMPONENT_RESOLUTION_RESOLVED["$component_id"]="true"

    STOLEUS_COMPONENT_EXECUTION_PLAN+=("$component_id")


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_build_execution_plan
# ==============================================================================
#
# Purpose:
#     Build an ordered, duplicate-free execution plan for one component.
#
# Arguments:
#
#     $1 = requested component ID
#
# Generated state:
#
#     STOLEUS_COMPONENT_EXECUTION_PLAN
#
# Output:
#
#     No normal stdout output.
#
# Example:
#
#     component_build_execution_plan "server"
#
# Result:
#
#     STOLEUS_COMPONENT_EXECUTION_PLAN=(
#         chrony
#         firewall
#         docker
#         directories
#         server
#     )
# ==============================================================================
component_build_execution_plan() {

    local component_id="${1:-}"


    if [[ -z "$component_id" ]]; then

        log_error \
            "Execution-plan generation requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$component_id"; then

        log_error \
            "Unknown setup component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    # --------------------------------------------------------------------------
    # Reset all resolution state before creating a new plan.
    # --------------------------------------------------------------------------
    STOLEUS_COMPONENT_RESOLUTION_VISITING=()
    STOLEUS_COMPONENT_RESOLUTION_RESOLVED=()
    STOLEUS_COMPONENT_EXECUTION_PLAN=()


    component_resolve_dependency_node \
        "$component_id" ||
        return $?


    if (( ${#STOLEUS_COMPONENT_EXECUTION_PLAN[@]} == 0 )); then

        log_error \
            "Dependency resolution produced an empty execution plan."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_print_execution_plan
# ==============================================================================
#
# Purpose:
#     Print the resolved execution plan for diagnostics and testing.
#
# Arguments:
#
#     $1 = requested component ID
#
# Example:
#
#     component_print_execution_plan "server"
#
# Output:
#
#     chrony
#     firewall
#     docker
#     directories
#     server
# ==============================================================================
component_print_execution_plan() {

    local component_id="${1:-}"
    local planned_component=""


    component_build_execution_plan \
        "$component_id" ||
        return $?


    for planned_component in "${STOLEUS_COMPONENT_EXECUTION_PLAN[@]}"; do

        printf '%s\n' "$planned_component"
    done


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_validate_arguments
# ==============================================================================
#
# Purpose:
#     Run the optional argument validator registered for a component.
#
# Arguments:
#
#     $1
#         Component ID.
#
#     Remaining arguments
#         Original component arguments.
#
# Components without a registered validator succeed immediately.
# ==============================================================================
component_validate_arguments() {

    local component_id="${1:-}"
    local argument_validator=""


    if [[ -z "$component_id" ]]; then

        log_error \
            "Component argument validation requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$component_id"; then

        log_error \
            "Cannot validate arguments for an unknown component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    shift


    argument_validator="$(
        printf '%s' \
            "${STOLEUS_COMPONENT_ARGUMENT_VALIDATORS[$component_id]}"
    )"


    # --------------------------------------------------------------------------
    # Components without a validator accept their arguments unchanged.
    # --------------------------------------------------------------------------
    if [[ -z "$argument_validator" ]]; then

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    if ! declare -F "$argument_validator" >/dev/null 2>&1; then

        log_error \
            "Component argument validator is unavailable: ${component_id} -> ${argument_validator}"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    "$argument_validator" "$@" || return $?


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# component_execute_single
# ==============================================================================
#
# Purpose:
#     Execute exactly one registered component without resolving dependencies.
#
# This is used internally after the dependency execution plan has already been
# generated.
#
# Arguments:
#
#     $1
#         Component ID.
#
#     Remaining arguments
#         Arguments forwarded to the component entry function.
# ==============================================================================
component_execute_single() {

    local component_id="${1:-}"
    local entry_function=""


    if [[ -z "$component_id" ]]; then

        log_error \
            "Single-component execution requires a component ID."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if ! component_is_registered "$component_id"; then

        log_error \
            "Unknown setup component: $component_id"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    shift


    entry_function="$(
        component_get_entry_function "$component_id"
    )" || return $?


    if ! declare -F "$entry_function" >/dev/null 2>&1; then

        log_error \
            "Component entry function is unavailable: ${component_id} -> ${entry_function}"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    run_with_log_context \
        "$component_id" \
        "$entry_function" \
        "$@" ||
        return $?


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}