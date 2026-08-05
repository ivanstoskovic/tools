#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Contract Definition Subsystem
# ==============================================================================
#
# Purpose:
#     Discover and parse declarative framework contracts.
#
# A ContractDefinition describes behavior that another artifact may implement.
#
# Examples:
#
#     package-manager
#     service-manager
#     remote-executor
#     filesystem
#
# Processing flow:
#
#     Contract directory
#         ↓
#     contract.sh
#         ↓
#     Contract DSL
#         ↓
#     ContractDefinition
#         ↓
#     Frozen definition collection
#
# This subsystem does not:
#
#     - load provider implementations;
#     - resolve contract implementations;
#     - bind modules to providers;
#     - execute contract operations;
#     - modify infrastructure.
#
# Public API:
#
#     stoleus_contract_definition_initialize
#     stoleus_contract_definition_add_root
#     stoleus_contract_definition_build_all
#     stoleus_contract_definition_exists
#     stoleus_contract_definition_get_index
#     stoleus_contract_definition_get_field
#     stoleus_contract_definition_list
#     stoleus_contract_definition_list_operations
#     stoleus_contract_definition_is_frozen
#     stoleus_contract_definition_reset
#
# Contract DSL:
#
#     stoleus_contract_begin "package-manager"
#
#     stoleus_contract_description \
#         "Installs, removes, and inspects operating-system packages."
#
#     stoleus_contract_version "1.0.0"
#
#     stoleus_contract_operation \
#         "install" \
#         "Install one package."
#
#     stoleus_contract_operation \
#         "remove" \
#         "Remove one package."
#
#     stoleus_contract_end
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_CONTRACT_DEFINITION_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_CONTRACT_DEFINITION_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Contract Root State
# ==============================================================================

declare -a STOLEUS_CONTRACT_DEFINITION_ROOTS=()


# ==============================================================================
# ContractDefinition State
# ==============================================================================
#
# All arrays use the same numeric index.
#
# Operations and operation descriptions are stored as delimiter-separated
# normalized fields.
#
#     operations:
#         install,remove,exists
#
#     descriptions:
#         Install one package.;Remove one package.;Check package existence.
# ==============================================================================

declare -a STOLEUS_CONTRACT_DEFINITION_IDS=()
declare -a STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS=()
declare -a STOLEUS_CONTRACT_DEFINITION_VERSIONS=()
declare -a STOLEUS_CONTRACT_DEFINITION_PATHS=()
declare -a STOLEUS_CONTRACT_DEFINITION_OPERATIONS=()
declare -a STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS=()

declare -A STOLEUS_CONTRACT_DEFINITION_INDEX_BY_ID=()


# ==============================================================================
# Contract DSL Builder State
# ==============================================================================

STOLEUS_CONTRACT_BUILD_ACTIVE="false"
STOLEUS_CONTRACT_BUILD_COMPLETED="false"

STOLEUS_CONTRACT_BUILD_ID=""
STOLEUS_CONTRACT_BUILD_DESCRIPTION=""
STOLEUS_CONTRACT_BUILD_VERSION=""

declare -a STOLEUS_CONTRACT_BUILD_OPERATIONS=()
declare -a STOLEUS_CONTRACT_BUILD_OPERATION_DESCRIPTIONS=()

declare -A STOLEUS_CONTRACT_BUILD_OPERATION_SET=()


# ==============================================================================
# stoleus_contract_definition_is_frozen
# ==============================================================================

stoleus_contract_definition_is_frozen() {

    [[ "${STOLEUS_CONTRACT_DEFINITIONS_FROZEN:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_contract_definition_reset_builder
# ==============================================================================

stoleus_contract_definition_reset_builder() {

    STOLEUS_CONTRACT_BUILD_ACTIVE="false"
    STOLEUS_CONTRACT_BUILD_COMPLETED="false"

    STOLEUS_CONTRACT_BUILD_ID=""
    STOLEUS_CONTRACT_BUILD_DESCRIPTION=""
    STOLEUS_CONTRACT_BUILD_VERSION=""

    STOLEUS_CONTRACT_BUILD_OPERATIONS=()
    STOLEUS_CONTRACT_BUILD_OPERATION_DESCRIPTIONS=()
    STOLEUS_CONTRACT_BUILD_OPERATION_SET=()


    return 0
}


# ==============================================================================
# stoleus_contract_definition_reset
# ==============================================================================
#
# Purpose:
#     Clear definitions and return the subsystem to a mutable state.
#
# Registered discovery roots are preserved.
# ==============================================================================

stoleus_contract_definition_reset() {

    STOLEUS_CONTRACT_DEFINITION_IDS=()
    STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS=()
    STOLEUS_CONTRACT_DEFINITION_VERSIONS=()
    STOLEUS_CONTRACT_DEFINITION_PATHS=()
    STOLEUS_CONTRACT_DEFINITION_OPERATIONS=()
    STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS=()

    STOLEUS_CONTRACT_DEFINITION_INDEX_BY_ID=()

    STOLEUS_CONTRACT_DEFINITIONS_FROZEN="false"

    stoleus_contract_definition_reset_builder || return $?


    return 0
}


# ==============================================================================
# stoleus_contract_definition_add_root
# ==============================================================================
#
# Purpose:
#     Add one contract-definition discovery root.
#
# Arguments:
#
#     $1 = absolute or PROJECT_ROOT-relative directory
#
# Duplicate roots are ignored.
# Roots cannot change after definitions are frozen.
# ==============================================================================

stoleus_contract_definition_add_root() {

    local root_path="${1:-}"
    local normalized_root=""
    local existing_root=""


    if [[ -z "$root_path" ]]; then

        printf '%s\n' \
            "ERROR: Contract definition root path is required." >&2

        return 2
    fi


    if stoleus_contract_definition_is_frozen; then

        printf '%s\n' \
            "ERROR: Contract definition roots cannot change after freeze." \
            >&2

        return 8
    fi


    if [[ "$root_path" == /* ]]; then
        normalized_root="$root_path"
    else
        normalized_root="${PROJECT_ROOT}/${root_path}"
    fi


    if [[ "$normalized_root" != "/" ]]; then
        normalized_root="${normalized_root%/}"
    fi


    for existing_root in "${STOLEUS_CONTRACT_DEFINITION_ROOTS[@]}"; do

        if [[ "$existing_root" == "$normalized_root" ]]; then
            return 0
        fi
    done


    STOLEUS_CONTRACT_DEFINITION_ROOTS+=("$normalized_root")

    return 0
}


# ==============================================================================
# stoleus_contract_definition_exists
# ==============================================================================

stoleus_contract_definition_exists() {

    local contract_id="${1:-}"


    if [[ -z "$contract_id" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_CONTRACT_DEFINITION_INDEX_BY_ID[$contract_id]+defined}" ]]
}


# ==============================================================================
# stoleus_contract_definition_get_index
# ==============================================================================

stoleus_contract_definition_get_index() {

    local contract_id="${1:-}"


    if [[ -z "$contract_id" ]]; then

        printf '%s\n' \
            "ERROR: Contract lookup requires a contract ID." >&2

        return 2
    fi


    if ! stoleus_contract_definition_exists "$contract_id"; then

        printf '%s\n' \
            "ERROR: Unknown contract definition: $contract_id" >&2

        return 6
    fi


    printf '%s\n' \
        "${STOLEUS_CONTRACT_DEFINITION_INDEX_BY_ID[$contract_id]}"

    return 0
}


# ==============================================================================
# stoleus_contract_definition_require_active_builder
# ==============================================================================

stoleus_contract_definition_require_active_builder() {

    if [[ "$STOLEUS_CONTRACT_BUILD_ACTIVE" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Contract declaration used outside stoleus_contract_begin/end." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_contract_begin
# ==============================================================================

stoleus_contract_begin() {

    local contract_id="${1:-}"


    if [[ "$STOLEUS_CONTRACT_BUILD_ACTIVE" == "true" ]]; then

        printf '%s\n' \
            "ERROR: A contract declaration is already active." >&2

        return 8
    fi


    stoleus_contract_definition_reset_builder || return $?


    if [[ -z "$contract_id" ]]; then

        printf '%s\n' \
            "ERROR: stoleus_contract_begin requires a contract ID." >&2

        return 2
    fi


    if [[ ! "$contract_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid contract ID: $contract_id" >&2

        return 6
    fi


    STOLEUS_CONTRACT_BUILD_ID="$contract_id"
    STOLEUS_CONTRACT_BUILD_ACTIVE="true"


    return 0
}


# ==============================================================================
# stoleus_contract_description
# ==============================================================================

stoleus_contract_description() {

    local description="${1:-}"


    stoleus_contract_definition_require_active_builder || return $?


    if [[ -z "$description" ]]; then

        printf '%s\n' \
            "ERROR: Contract description cannot be empty." >&2

        return 2
    fi


    STOLEUS_CONTRACT_BUILD_DESCRIPTION="$description"

    return 0
}


# ==============================================================================
# stoleus_contract_version
# ==============================================================================

stoleus_contract_version() {

    local version="${1:-}"


    stoleus_contract_definition_require_active_builder || return $?


    if [[ -z "$version" ]]; then

        printf '%s\n' \
            "ERROR: Contract version cannot be empty." >&2

        return 2
    fi


    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Contract version must use semantic version format: $version" \
            >&2

        return 6
    fi


    STOLEUS_CONTRACT_BUILD_VERSION="$version"

    return 0
}


# ==============================================================================
# stoleus_contract_operation
# ==============================================================================
#
# Arguments:
#
#     $1 = operation ID
#     $2 = operation description
# ==============================================================================

stoleus_contract_operation() {

    local operation_id="${1:-}"
    local operation_description="${2:-}"


    stoleus_contract_definition_require_active_builder || return $?


    if [[ -z "$operation_id" || -z "$operation_description" ]]; then

        printf '%s\n' \
            "ERROR: Contract operation requires ID and description." >&2

        return 2
    fi


    if [[ ! "$operation_id" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid contract operation ID: $operation_id" >&2

        return 6
    fi


    if [[ -n "${STOLEUS_CONTRACT_BUILD_OPERATION_SET[$operation_id]+declared}" ]]; then

        printf '%s\n' \
            "ERROR: Duplicate contract operation: $operation_id" >&2

        return 8
    fi


    STOLEUS_CONTRACT_BUILD_OPERATION_SET["$operation_id"]="true"

    STOLEUS_CONTRACT_BUILD_OPERATIONS+=("$operation_id")
    STOLEUS_CONTRACT_BUILD_OPERATION_DESCRIPTIONS+=(
        "$operation_description"
    )


    return 0
}


# ==============================================================================
# stoleus_contract_end
# ==============================================================================

stoleus_contract_end() {

    stoleus_contract_definition_require_active_builder || return $?


    STOLEUS_CONTRACT_BUILD_ACTIVE="false"
    STOLEUS_CONTRACT_BUILD_COMPLETED="true"


    return 0
}


# ==============================================================================
# stoleus_contract_definition_join
# ==============================================================================
#
# Arguments:
#
#     $1 = delimiter
#     remaining arguments = values
# ==============================================================================

stoleus_contract_definition_join() {

    local delimiter="${1:-}"
    shift || true

    local value=""
    local result=""


    for value in "$@"; do

        if [[ -n "$result" ]]; then
            result+="$delimiter"
        fi

        result+="$value"
    done


    printf '%s' "$result"

    return 0
}


# ==============================================================================
# stoleus_contract_definition_register_builder
# ==============================================================================
#
# Purpose:
#     Validate and register the current normalized builder state.
#
# Arguments:
#
#     $1 = absolute contract manifest path
# ==============================================================================

stoleus_contract_definition_register_builder() {

    local contract_path="${1:-}"

    local contract_index=0
    local operations=""
    local operation_descriptions=""


    # --------------------------------------------------------------------------
    # Contract definitions cannot change after the collection is frozen.
    # --------------------------------------------------------------------------
    if stoleus_contract_definition_is_frozen; then

        printf '%s\n' \
            "ERROR: ContractDefinitions are immutable after freeze." >&2

        return 8
    fi


    # --------------------------------------------------------------------------
    # The manifest must have completed the begin/end DSL block.
    # --------------------------------------------------------------------------
    if [[ "$STOLEUS_CONTRACT_BUILD_COMPLETED" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Contract manifest did not complete its declaration: $contract_path" \
            >&2

        return 6
    fi


    # --------------------------------------------------------------------------
    # Validate required contract metadata.
    # --------------------------------------------------------------------------
    if [[ -z "$STOLEUS_CONTRACT_BUILD_ID" ]]; then

        printf '%s\n' \
            "ERROR: Contract manifest does not define an ID: $contract_path" \
            >&2

        return 6
    fi


    if stoleus_contract_definition_exists \
        "$STOLEUS_CONTRACT_BUILD_ID"; then

        printf '%s\n' \
            "ERROR: Duplicate ContractDefinition ID: ${STOLEUS_CONTRACT_BUILD_ID}" \
            >&2

        return 8
    fi


    if [[ -z "$STOLEUS_CONTRACT_BUILD_DESCRIPTION" ]]; then

        printf '%s\n' \
            "ERROR: Contract '${STOLEUS_CONTRACT_BUILD_ID}' requires a description." \
            >&2

        return 6
    fi


    if [[ -z "$STOLEUS_CONTRACT_BUILD_VERSION" ]]; then

        printf '%s\n' \
            "ERROR: Contract '${STOLEUS_CONTRACT_BUILD_ID}' requires a version." \
            >&2

        return 6
    fi


    if (( ${#STOLEUS_CONTRACT_BUILD_OPERATIONS[@]} == 0 )); then

        printf '%s\n' \
            "ERROR: Contract '${STOLEUS_CONTRACT_BUILD_ID}' requires at least one operation." \
            >&2

        return 6
    fi


    if [[ -z "$contract_path" || ! -f "$contract_path" ]]; then

        printf '%s\n' \
            "ERROR: Contract manifest path is invalid: $contract_path" >&2

        return 6
    fi


    # --------------------------------------------------------------------------
    # Normalize operation metadata into stable Registry-friendly fields.
    # --------------------------------------------------------------------------
    operations="$(
        stoleus_contract_definition_join \
            "," \
            "${STOLEUS_CONTRACT_BUILD_OPERATIONS[@]}"
    )" || return $?


    operation_descriptions="$(
        stoleus_contract_definition_join \
            ";" \
            "${STOLEUS_CONTRACT_BUILD_OPERATION_DESCRIPTIONS[@]}"
    )" || return $?


    # --------------------------------------------------------------------------
    # Allocate the next immutable definition index.
    # --------------------------------------------------------------------------
    contract_index="${#STOLEUS_CONTRACT_DEFINITION_IDS[@]}"


    STOLEUS_CONTRACT_DEFINITION_IDS+=(
        "$STOLEUS_CONTRACT_BUILD_ID"
    )

    STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS+=(
        "$STOLEUS_CONTRACT_BUILD_DESCRIPTION"
    )

    STOLEUS_CONTRACT_DEFINITION_VERSIONS+=(
        "$STOLEUS_CONTRACT_BUILD_VERSION"
    )

    STOLEUS_CONTRACT_DEFINITION_PATHS+=(
        "$contract_path"
    )

    STOLEUS_CONTRACT_DEFINITION_OPERATIONS+=(
        "$operations"
    )

    STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS+=(
        "$operation_descriptions"
    )


    # --------------------------------------------------------------------------
    # Map the exact contract ID to its metadata-array index.
    #
    # Keep the complete associative-array subscript on one line. Splitting the
    # subscript across formatted lines may introduce whitespace into the key.
    # --------------------------------------------------------------------------
    STOLEUS_CONTRACT_DEFINITION_INDEX_BY_ID["$STOLEUS_CONTRACT_BUILD_ID"]="$contract_index"


    return 0
}


# ==============================================================================
# stoleus_contract_definition_load
# ==============================================================================
#
# Purpose:
#     Load one metadata-only Bash contract manifest.
# ==============================================================================

stoleus_contract_definition_load() {

    local contract_path="${1:-}"


    if [[ -z "$contract_path" || ! -f "$contract_path" ]]; then

        printf '%s\n' \
            "ERROR: Contract manifest does not exist: $contract_path" >&2

        return 6
    fi


    stoleus_contract_definition_reset_builder || return $?


    source "$contract_path"


    if [[ "$STOLEUS_CONTRACT_BUILD_ACTIVE" == "true" ]]; then

        printf '%s\n' \
            "ERROR: Contract manifest did not call stoleus_contract_end: $contract_path" \
            >&2

        return 6
    fi


    stoleus_contract_definition_register_builder \
        "$contract_path" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_contract_definition_build_root
# ==============================================================================
#
# Purpose:
#     Discover contract.sh files one directory below one configured root.
#
# Ordering is lexical and deterministic.
# Missing optional roots are valid.
# ==============================================================================

stoleus_contract_definition_build_root() {

    local root_path="${1:-}"
    local contract_path=""


    if [[ -z "$root_path" ]]; then

        printf '%s\n' \
            "ERROR: Contract-definition build root is required." >&2

        return 2
    fi


    if [[ ! -d "$root_path" ]]; then
        return 0
    fi


    while IFS= read -r contract_path; do

        [[ -z "$contract_path" ]] && continue


        stoleus_contract_definition_load \
            "$contract_path" ||
            return $?

    done < <(
        find "$root_path" \
            -mindepth 2 \
            -maxdepth 2 \
            -type f \
            -name "contract.sh" \
            -print |
            LC_ALL=C sort
    )


    return 0
}


# ==============================================================================
# stoleus_contract_definition_build_all
# ==============================================================================
#
# Purpose:
#     Build and freeze all configured ContractDefinitions.
#
# Successful repeated calls are idempotent.
# ==============================================================================

stoleus_contract_definition_build_all() {

    local root_path=""


    if [[ "${STOLEUS_CONTRACT_DEFINITION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Contract Definition subsystem must be initialized before building." \
            >&2

        return 6
    fi


    if stoleus_contract_definition_is_frozen; then
        return 0
    fi


    stoleus_contract_definition_reset || return $?


    for root_path in "${STOLEUS_CONTRACT_DEFINITION_ROOTS[@]}"; do

        stoleus_contract_definition_build_root \
            "$root_path" ||
            return $?
    done


    STOLEUS_CONTRACT_DEFINITIONS_FROZEN="true"

    return 0
}


# ==============================================================================
# stoleus_contract_definition_get_field
# ==============================================================================

stoleus_contract_definition_get_field() {

    local contract_id="${1:-}"
    local field_name="${2:-}"

    local contract_index=""


    if [[ -z "$contract_id" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Contract field lookup requires contract ID and field name." \
            >&2

        return 2
    fi


    contract_index="$(
        stoleus_contract_definition_get_index "$contract_id"
    )" || return $?


    case "$field_name" in

        id)
            printf '%s\n' \
                "${STOLEUS_CONTRACT_DEFINITION_IDS[$contract_index]}"
            ;;

        description)
            printf '%s\n' \
                "${STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS[$contract_index]}"
            ;;

        version)
            printf '%s\n' \
                "${STOLEUS_CONTRACT_DEFINITION_VERSIONS[$contract_index]}"
            ;;

        path)
            printf '%s\n' \
                "${STOLEUS_CONTRACT_DEFINITION_PATHS[$contract_index]}"
            ;;

        operations)
            printf '%s\n' \
                "${STOLEUS_CONTRACT_DEFINITION_OPERATIONS[$contract_index]}"
            ;;

        operation-descriptions)
            printf '%s\n' \
                "${STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS[$contract_index]}"
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported ContractDefinition field: $field_name" \
                >&2

            return 2

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_contract_definition_list_operations
# ==============================================================================
#
# Output format:
#
#     operation-id<TAB>description
# ==============================================================================

stoleus_contract_definition_list_operations() {

    local contract_id="${1:-}"
    local contract_index=""

    local operations=""
    local descriptions=""

    local operation=""
    local description=""

    local -a operation_array=()
    local -a description_array=()

    local operation_index=0


    contract_index="$(
        stoleus_contract_definition_get_index "$contract_id"
    )" || return $?


    operations="${STOLEUS_CONTRACT_DEFINITION_OPERATIONS[$contract_index]}"
    descriptions="${STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS[$contract_index]}"


    IFS=',' read -r -a operation_array <<< "$operations"
    IFS=';' read -r -a description_array <<< "$descriptions"


    for operation_index in "${!operation_array[@]}"; do

        operation="${operation_array[$operation_index]}"
        description="${description_array[$operation_index]:-}"


        printf '%s\t%s\n' \
            "$operation" \
            "$description"
    done


    return 0
}


# ==============================================================================
# stoleus_contract_definition_list
# ==============================================================================
#
# Output format:
#
#     id<TAB>version<TAB>description
# ==============================================================================

stoleus_contract_definition_list() {

    local contract_index=0


    for contract_index in "${!STOLEUS_CONTRACT_DEFINITION_IDS[@]}"; do

        printf '%s\t%s\t%s\n' \
            "${STOLEUS_CONTRACT_DEFINITION_IDS[$contract_index]}" \
            "${STOLEUS_CONTRACT_DEFINITION_VERSIONS[$contract_index]}" \
            "${STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS[$contract_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_contract_definition_initialize
# ==============================================================================

stoleus_contract_definition_initialize() {

    if [[ "${STOLEUS_CONTRACT_DEFINITION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_CONTRACT_DEFINITION_ROOTS=()

    stoleus_contract_definition_reset || return $?


    stoleus_contract_definition_add_root \
        "${PROJECT_ROOT}/contracts/definitions" ||
        return $?


    STOLEUS_CONTRACT_DEFINITION_INITIALIZED="true"

    return 0
}
