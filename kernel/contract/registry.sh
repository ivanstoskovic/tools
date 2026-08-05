#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Contract Registry
# ==============================================================================
#
# Purpose:
#     Import validated ContractDefinitions into an immutable contract metadata
#     collection.
#
# Processing flow:
#
#     ContractDefinition collection
#         ↓
#     Contract-specific validation
#         ↓
#     Generic Metadata Collection
#         ↓
#     Frozen Contract Registry
#
# The generic metadata subsystem owns:
#
#     - row storage;
#     - schema enforcement;
#     - insertion order;
#     - key indexing;
#     - collection freezing;
#     - generic field lookup.
#
# The Contract Registry owns:
#
#     - contract-specific schema;
#     - ContractDefinition import;
#     - contract semantic validation;
#     - contract-oriented lookup APIs;
#     - operation and description projection.
#
# The Contract Registry does not:
#
#     - discover contract files;
#     - parse contract manifests;
#     - resolve provider implementations;
#     - bind plugins to contracts;
#     - load implementation code;
#     - execute contract operations.
#
# Public API:
#
#     stoleus_contract_registry_initialize
#     stoleus_contract_registry_import_definitions
#     stoleus_contract_registry_contains
#     stoleus_contract_registry_get_index
#     stoleus_contract_registry_get_field
#     stoleus_contract_registry_list
#     stoleus_contract_registry_list_operations
#     stoleus_contract_registry_freeze
#     stoleus_contract_registry_is_frozen
#     stoleus_contract_registry_get_count
#     stoleus_contract_registry_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_CONTRACT_REGISTRY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_CONTRACT_REGISTRY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Contract Registry Constants
# ==============================================================================

readonly STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID="contracts"


# ==============================================================================
# stoleus_contract_registry_is_frozen
# ==============================================================================

stoleus_contract_registry_is_frozen() {

    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID"; then

        return 1
    fi


    stoleus_metadata_collection_is_frozen \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID"
}


# ==============================================================================
# stoleus_contract_registry_reset
# ==============================================================================
#
# Purpose:
#     Remove the Contract Registry collection and reset adapter state.
#
# ContractDefinition state is not modified.
# ==============================================================================

stoleus_contract_registry_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_CONTRACT_REGISTRY_IMPORTED="false"
    STOLEUS_CONTRACT_REGISTRY_READY="false"


    return 0
}


# ==============================================================================
# stoleus_contract_registry_create_collection
# ==============================================================================
#
# Purpose:
#     Create the empty mutable generic metadata collection used by the adapter.
#
# Schema:
#
#     id
#     version
#     description
#     path
#     operations
#     operation-descriptions
# ==============================================================================

stoleus_contract_registry_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" \
        "id" \
        "id" \
        "version" \
        "description" \
        "path" \
        "operations" \
        "operation-descriptions" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_contract_registry_contains
# ==============================================================================

stoleus_contract_registry_contains() {

    local contract_id="${1:-}"


    if [[ -z "$contract_id" ]]; then
        return 2
    fi


    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID"; then

        return 6
    fi


    stoleus_metadata_collection_contains \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" \
        "$contract_id"
}


# ==============================================================================
# stoleus_contract_registry_get_index
# ==============================================================================

stoleus_contract_registry_get_index() {

    local contract_id="${1:-}"


    if [[ -z "$contract_id" ]]; then

        printf '%s\n' \
            "ERROR: Contract Registry lookup requires a contract ID." >&2

        return 2
    fi


    stoleus_metadata_collection_get_index \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" \
        "$contract_id"

    return $?
}


# ==============================================================================
# stoleus_contract_registry_validate_operation_metadata
# ==============================================================================
#
# Purpose:
#     Verify that contract operation IDs and descriptions are complete and
#     aligned before import.
#
# Arguments:
#
#     $1 = contract ID
#     $2 = comma-separated operation IDs
#     $3 = semicolon-separated operation descriptions
# ==============================================================================

stoleus_contract_registry_validate_operation_metadata() {

    local contract_id="${1:-}"
    local operations="${2:-}"
    local operation_descriptions="${3:-}"

    local operation_id=""
    local operation_description=""

    local -a operation_array=()
    local -a description_array=()

    local -A seen_operations=()

    local operation_index=0


    if [[ -z "$operations" ]]; then

        printf '%s\n' \
            "ERROR: Contract '${contract_id}' requires at least one operation." \
            >&2

        return 6
    fi


    IFS=',' read -r -a operation_array <<< "$operations"
    IFS=';' read -r -a description_array <<< "$operation_descriptions"


    if (( ${#operation_array[@]} != ${#description_array[@]} )); then

        printf '%s\n' \
            "ERROR: Contract '${contract_id}' has mismatched operation and description counts." \
            >&2

        return 6
    fi


    for operation_index in "${!operation_array[@]}"; do

        operation_id="${operation_array[$operation_index]}"
        operation_description="${description_array[$operation_index]:-}"


        if [[ ! "$operation_id" =~ ^[a-z][a-z0-9-]*$ ]]; then

            printf '%s\n' \
                "ERROR: Contract '${contract_id}' has an invalid operation ID: ${operation_id}" \
                >&2

            return 6
        fi


        if [[ -n "${seen_operations[$operation_id]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Contract '${contract_id}' contains duplicate operation: ${operation_id}" \
                >&2

            return 8
        fi


        if [[ -z "$operation_description" ]]; then

            printf '%s\n' \
                "ERROR: Contract '${contract_id}' operation '${operation_id}' requires a description." \
                >&2

            return 6
        fi


        seen_operations["$operation_id"]="true"
    done


    return 0
}


# ==============================================================================
# stoleus_contract_registry_validate_definition
# ==============================================================================
#
# Purpose:
#     Validate one ContractDefinition before generic metadata import.
#
# Arguments:
#
#     $1 = ContractDefinition array index
# ==============================================================================

stoleus_contract_registry_validate_definition() {

    local definition_index="${1:-}"

    local contract_id=""
    local description=""
    local version=""
    local contract_path=""
    local operations=""
    local operation_descriptions=""


    if [[ -z "$definition_index" ||
          ! "$definition_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Contract Registry import received an invalid definition index." \
            >&2

        return 2
    fi


    contract_id="${STOLEUS_CONTRACT_DEFINITION_IDS[$definition_index]:-}"
    description="${STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS[$definition_index]:-}"
    version="${STOLEUS_CONTRACT_DEFINITION_VERSIONS[$definition_index]:-}"
    contract_path="${STOLEUS_CONTRACT_DEFINITION_PATHS[$definition_index]:-}"
    operations="${STOLEUS_CONTRACT_DEFINITION_OPERATIONS[$definition_index]:-}"
    operation_descriptions="${STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS[$definition_index]:-}"


    if [[ -z "$contract_id" ||
          ! "$contract_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Contract Registry import found an invalid contract ID: ${contract_id}" \
            >&2

        return 6
    fi


    if stoleus_contract_registry_contains "$contract_id"; then

        printf '%s\n' \
            "ERROR: Duplicate Contract Registry ID: $contract_id" >&2

        return 8
    fi


    if [[ -z "$description" ]]; then

        printf '%s\n' \
            "ERROR: Contract '${contract_id}' requires a description." >&2

        return 6
    fi


    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Contract '${contract_id}' has an invalid semantic version: ${version}" \
            >&2

        return 6
    fi


    if [[ -z "$contract_path" || ! -f "$contract_path" ]]; then

        printf '%s\n' \
            "ERROR: Contract '${contract_id}' manifest is unavailable: ${contract_path}" \
            >&2

        return 6
    fi


    stoleus_contract_registry_validate_operation_metadata \
        "$contract_id" \
        "$operations" \
        "$operation_descriptions" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_contract_registry_append_definition
# ==============================================================================
#
# Purpose:
#     Import one validated ContractDefinition into the generic metadata
#     collection.
#
# Arguments:
#
#     $1 = ContractDefinition array index
# ==============================================================================

stoleus_contract_registry_append_definition() {

    local definition_index="${1:-}"


    if stoleus_contract_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Contract Registry is immutable after freeze." >&2

        return 8
    fi


    stoleus_contract_registry_validate_definition \
        "$definition_index" ||
        return $?


    stoleus_metadata_collection_append \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" \
        "${STOLEUS_CONTRACT_DEFINITION_IDS[$definition_index]}" \
        "${STOLEUS_CONTRACT_DEFINITION_VERSIONS[$definition_index]}" \
        "${STOLEUS_CONTRACT_DEFINITION_DESCRIPTIONS[$definition_index]}" \
        "${STOLEUS_CONTRACT_DEFINITION_PATHS[$definition_index]}" \
        "${STOLEUS_CONTRACT_DEFINITION_OPERATIONS[$definition_index]}" \
        "${STOLEUS_CONTRACT_DEFINITION_OPERATION_DESCRIPTIONS[$definition_index]}" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_contract_registry_freeze
# ==============================================================================

stoleus_contract_registry_freeze() {

    if stoleus_contract_registry_is_frozen; then
        return 0
    fi


    stoleus_metadata_collection_freeze \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_CONTRACT_REGISTRY_READY="true"


    return 0
}


# ==============================================================================
# stoleus_contract_registry_import_definitions
# ==============================================================================
#
# Purpose:
#     Import the complete frozen ContractDefinition collection and freeze the
#     Contract Registry.
#
# Requirements:
#
#     - Metadata subsystem initialized;
#     - Contract Definition subsystem initialized;
#     - ContractDefinitions frozen;
#     - Contract Registry mutable and empty.
#
# Empty ContractDefinition collections are valid.
# ==============================================================================

stoleus_contract_registry_import_definitions() {

    local definition_index=0
    local existing_count=0


    if [[ "${STOLEUS_CONTRACT_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Contract Registry must be initialized before import." >&2

        return 6
    fi


    if [[ "${STOLEUS_CONTRACT_DEFINITION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Contract Definition subsystem must be initialized before Registry import." \
            >&2

        return 6
    fi


    if ! stoleus_contract_definition_is_frozen; then

        printf '%s\n' \
            "ERROR: ContractDefinitions must be frozen before Registry import." \
            >&2

        return 6
    fi


    if stoleus_contract_registry_is_frozen; then
        return 0
    fi


    if [[ "${STOLEUS_CONTRACT_REGISTRY_IMPORTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: ContractDefinitions were already imported." >&2

        return 8
    fi


    existing_count="$(
        stoleus_metadata_collection_get_count \
            "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID"
    )" || return $?


    if (( existing_count != 0 )); then

        printf '%s\n' \
            "ERROR: Contract Registry must be empty before import." >&2

        return 8
    fi


    for definition_index in "${!STOLEUS_CONTRACT_DEFINITION_IDS[@]}"; do

        stoleus_contract_registry_append_definition \
            "$definition_index" ||
            return $?
    done


    STOLEUS_CONTRACT_REGISTRY_IMPORTED="true"

    stoleus_contract_registry_freeze || return $?


    return 0
}


# ==============================================================================
# stoleus_contract_registry_get_field
# ==============================================================================

stoleus_contract_registry_get_field() {

    local contract_id="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$contract_id" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Contract Registry field lookup requires contract ID and field name." \
            >&2

        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" \
        "$contract_id" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_contract_registry_get_count
# ==============================================================================

stoleus_contract_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_contract_registry_list
# ==============================================================================
#
# Output format:
#
#     id<TAB>version<TAB>description
# ==============================================================================

stoleus_contract_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_CONTRACT_REGISTRY_COLLECTION_ID" \
        "id" \
        "version" \
        "description"

    return $?
}


# ==============================================================================
# stoleus_contract_registry_list_operations
# ==============================================================================
#
# Purpose:
#     List operations declared by one registered contract.
#
# Output format:
#
#     operation-id<TAB>description
# ==============================================================================

stoleus_contract_registry_list_operations() {

    local contract_id="${1:-}"

    local operations=""
    local operation_descriptions=""

    local operation_id=""
    local operation_description=""

    local -a operation_array=()
    local -a description_array=()

    local operation_index=0


    if [[ -z "$contract_id" ]]; then

        printf '%s\n' \
            "ERROR: Contract operation listing requires a contract ID." >&2

        return 2
    fi


    operations="$(
        stoleus_contract_registry_get_field \
            "$contract_id" \
            "operations"
    )" || return $?


    operation_descriptions="$(
        stoleus_contract_registry_get_field \
            "$contract_id" \
            "operation-descriptions"
    )" || return $?


    IFS=',' read -r -a operation_array <<< "$operations"
    IFS=';' read -r -a description_array <<< "$operation_descriptions"


    for operation_index in "${!operation_array[@]}"; do

        operation_id="${operation_array[$operation_index]}"
        operation_description="${description_array[$operation_index]:-}"


        printf '%s\t%s\n' \
            "$operation_id" \
            "$operation_description"
    done


    return 0
}


# ==============================================================================
# stoleus_contract_registry_initialize
# ==============================================================================

stoleus_contract_registry_initialize() {

    if [[ "${STOLEUS_CONTRACT_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_contract_registry_reset || return $?
    stoleus_contract_registry_create_collection || return $?


    STOLEUS_CONTRACT_REGISTRY_INITIALIZED="true"

    return 0
}
