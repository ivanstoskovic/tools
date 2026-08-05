#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Generic Metadata Collection
# ==============================================================================
#
# Purpose:
#     Provide reusable schema-based, indexed, immutable metadata collections.
#
# Intended consumers:
#
#     - Plugin Registry
#     - Contract Registry
#     - Command Registry
#     - Generator Registry
#     - Policy Registry
#     - Template Registry
#
# A collection contains:
#
#     collection ID
#     ordered field schema
#     key field
#     ordered rows
#     O(1) key-to-row lookup
#     mutable/frozen state
#
# Example:
#
#     stoleus_metadata_collection_create \
#         "contracts" \
#         "id" \
#         "id" \
#         "version" \
#         "description"
#
#     stoleus_metadata_collection_append \
#         "contracts" \
#         "package-manager" \
#         "1.0.0" \
#         "Installs and removes packages."
#
#     stoleus_metadata_collection_freeze \
#         "contracts"
#
# The service stores metadata only.
#
# It does not:
#
#     - discover files;
#     - parse manifests;
#     - understand plugin or contract semantics;
#     - load implementations;
#     - resolve dependencies;
#     - execute infrastructure operations.
#
# Public API:
#
#     stoleus_metadata_initialize
#     stoleus_metadata_collection_create
#     stoleus_metadata_collection_exists
#     stoleus_metadata_collection_is_frozen
#     stoleus_metadata_collection_append
#     stoleus_metadata_collection_freeze
#     stoleus_metadata_collection_contains
#     stoleus_metadata_collection_get_index
#     stoleus_metadata_collection_get_field
#     stoleus_metadata_collection_get_schema
#     stoleus_metadata_collection_get_count
#     stoleus_metadata_collection_list
#     stoleus_metadata_collection_reset
#     stoleus_metadata_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_METADATA_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_METADATA_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Collection State
# ==============================================================================

declare -A STOLEUS_METADATA_COLLECTION_DEFINED=()
declare -A STOLEUS_METADATA_COLLECTION_KEY_FIELDS=()
declare -A STOLEUS_METADATA_COLLECTION_SCHEMAS=()
declare -A STOLEUS_METADATA_COLLECTION_FIELD_COUNTS=()
declare -A STOLEUS_METADATA_COLLECTION_ROW_COUNTS=()
declare -A STOLEUS_METADATA_COLLECTION_FROZEN=()


# ==============================================================================
# Row and Value State
# ==============================================================================
#
# Composite-key formats:
#
#     row lookup:
#         collection-id|record-key
#
#     ordered row key:
#         collection-id|row-index
#
#     field value:
#         collection-id|row-index|field-name
# ==============================================================================

declare -A STOLEUS_METADATA_ROW_INDEX_BY_KEY=()
declare -A STOLEUS_METADATA_ROW_KEYS=()
declare -A STOLEUS_METADATA_VALUES=()


# ==============================================================================
# stoleus_metadata_validate_collection_id
# ==============================================================================

stoleus_metadata_validate_collection_id() {

    local collection_id="${1:-}"


    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata collection ID is required." >&2

        return 2
    fi


    if [[ ! "$collection_id" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid metadata collection ID: $collection_id" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_metadata_validate_field_name
# ==============================================================================

stoleus_metadata_validate_field_name() {

    local field_name="${1:-}"


    if [[ -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Metadata field name is required." >&2

        return 2
    fi


    if [[ ! "$field_name" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid metadata field name: $field_name" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_metadata_collection_exists
# ==============================================================================

stoleus_metadata_collection_exists() {

    local collection_id="${1:-}"


    if [[ -z "$collection_id" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_METADATA_COLLECTION_DEFINED[$collection_id]+defined}" ]]
}


# ==============================================================================
# stoleus_metadata_collection_is_frozen
# ==============================================================================

stoleus_metadata_collection_is_frozen() {

    local collection_id="${1:-}"


    if [[ -z "$collection_id" ]]; then
        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then
        return 6
    fi


    [[ "${STOLEUS_METADATA_COLLECTION_FROZEN[$collection_id]:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_metadata_schema_contains_field
# ==============================================================================
#
# Arguments:
#
#     $1 = comma-separated schema
#     $2 = field name
# ==============================================================================

stoleus_metadata_schema_contains_field() {

    local schema="${1:-}"
    local requested_field="${2:-}"
    local field_name=""


    while IFS= read -r field_name; do

        if [[ "$field_name" == "$requested_field" ]]; then
            return 0
        fi

    done < <(
        printf '%s\n' "$schema" |
            tr ',' '\n'
    )


    return 1
}


# ==============================================================================
# stoleus_metadata_collection_create
# ==============================================================================
#
# Purpose:
#     Create one empty mutable metadata collection.
#
# Arguments:
#
#     $1 = collection ID
#     $2 = key field
#     remaining arguments = ordered schema fields
#
# Rules:
#
#     - collection IDs are globally unique;
#     - schema fields are unique;
#     - the key field must be part of the schema;
#     - a collection requires at least one field.
# ==============================================================================

stoleus_metadata_collection_create() {

    local collection_id="${1:-}"
    local key_field="${2:-}"

    local field_name=""
    local schema=""

    local -A seen_fields=()


    stoleus_metadata_validate_collection_id \
        "$collection_id" ||
        return $?


    if stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Metadata collection already exists: $collection_id" >&2

        return 8
    fi


    stoleus_metadata_validate_field_name \
        "$key_field" ||
        return $?


    shift 2


    if (( $# == 0 )); then

        printf '%s\n' \
            "ERROR: Metadata collection '${collection_id}' requires a schema." \
            >&2

        return 2
    fi


    for field_name in "$@"; do

        stoleus_metadata_validate_field_name \
            "$field_name" ||
            return $?


        if [[ -n "${seen_fields[$field_name]+seen}" ]]; then

            printf '%s\n' \
                "ERROR: Metadata collection '${collection_id}' contains duplicate field: ${field_name}" \
                >&2

            return 8
        fi


        seen_fields["$field_name"]="true"


        if [[ -n "$schema" ]]; then
            schema+=","
        fi


        schema+="$field_name"
    done


    if [[ -z "${seen_fields[$key_field]+present}" ]]; then

        printf '%s\n' \
            "ERROR: Metadata collection '${collection_id}' key field '${key_field}' is not part of its schema." \
            >&2

        return 6
    fi


    STOLEUS_METADATA_COLLECTION_DEFINED["$collection_id"]="true"
    STOLEUS_METADATA_COLLECTION_KEY_FIELDS["$collection_id"]="$key_field"
    STOLEUS_METADATA_COLLECTION_SCHEMAS["$collection_id"]="$schema"
    STOLEUS_METADATA_COLLECTION_FIELD_COUNTS["$collection_id"]="$#"
    STOLEUS_METADATA_COLLECTION_ROW_COUNTS["$collection_id"]="0"
    STOLEUS_METADATA_COLLECTION_FROZEN["$collection_id"]="false"


    return 0
}


# ==============================================================================
# stoleus_metadata_collection_contains
# ==============================================================================

stoleus_metadata_collection_contains() {

    local collection_id="${1:-}"
    local record_key="${2:-}"
    local lookup_key=""


    if [[ -z "$collection_id" || -z "$record_key" ]]; then
        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then
        return 6
    fi


    lookup_key="${collection_id}|${record_key}"


    [[ -n "${STOLEUS_METADATA_ROW_INDEX_BY_KEY[$lookup_key]+stored}" ]]
}


# ==============================================================================
# stoleus_metadata_collection_append
# ==============================================================================
#
# Purpose:
#     Append one row to a mutable metadata collection.
#
# Arguments:
#
#     $1 = collection ID
#     remaining arguments = values in exact schema order
#
# The key value is determined from the collection's configured key field.
# ==============================================================================

stoleus_metadata_collection_append() {

    local collection_id="${1:-}"

    local schema=""
    local key_field=""
    local expected_field_count=0
    local actual_field_count=0
    local row_index=0

    local field_name=""
    local field_value=""
    local record_key=""
    local lookup_key=""
    local value_key=""

    local -a schema_fields=()
    local -a row_values=()

    local field_index=0


    # --------------------------------------------------------------------------
    # Validate the requested collection.
    # --------------------------------------------------------------------------
    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata append requires a collection ID." >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    if stoleus_metadata_collection_is_frozen "$collection_id"; then

        printf '%s\n' \
            "ERROR: Metadata collection '${collection_id}' is immutable after freeze." \
            >&2

        return 8
    fi


    shift


    schema="${STOLEUS_METADATA_COLLECTION_SCHEMAS[$collection_id]}"
    key_field="${STOLEUS_METADATA_COLLECTION_KEY_FIELDS[$collection_id]}"
    expected_field_count="${STOLEUS_METADATA_COLLECTION_FIELD_COUNTS[$collection_id]}"
    actual_field_count="$#"

    row_values=("$@")


    # --------------------------------------------------------------------------
    # Every row must supply exactly one value for every schema field.
    # --------------------------------------------------------------------------
    if (( actual_field_count != expected_field_count )); then

        printf '%s\n' \
            "ERROR: Metadata collection '${collection_id}' expects ${expected_field_count} values but received ${actual_field_count}." \
            >&2

        return 2
    fi


    IFS=',' read -r -a schema_fields <<< "$schema"


    # --------------------------------------------------------------------------
    # Extract the configured record key from the incoming row.
    # --------------------------------------------------------------------------
    for field_index in "${!schema_fields[@]}"; do

        field_name="${schema_fields[$field_index]}"
        field_value="${row_values[$field_index]}"


        if [[ "$field_name" == "$key_field" ]]; then
            record_key="$field_value"
        fi
    done


    if [[ -z "$record_key" ]]; then

        printf '%s\n' \
            "ERROR: Metadata collection '${collection_id}' requires a non-empty key field '${key_field}'." \
            >&2

        return 6
    fi


    if stoleus_metadata_collection_contains \
        "$collection_id" \
        "$record_key"; then

        printf '%s\n' \
            "ERROR: Duplicate metadata key '${record_key}' in collection '${collection_id}'." \
            >&2

        return 8
    fi


    # --------------------------------------------------------------------------
    # Allocate the next deterministic row index.
    # --------------------------------------------------------------------------
    row_index="${STOLEUS_METADATA_COLLECTION_ROW_COUNTS[$collection_id]}"
    lookup_key="${collection_id}|${record_key}"


    STOLEUS_METADATA_ROW_INDEX_BY_KEY["$lookup_key"]="$row_index"
    STOLEUS_METADATA_ROW_KEYS["${collection_id}|${row_index}"]="$record_key"


    # --------------------------------------------------------------------------
    # Store every field using an exact composite associative-array key.
    #
    # Keep the complete subscript expression on one line. Splitting an
    # associative-array subscript across formatted lines can insert whitespace
    # into the actual key.
    # --------------------------------------------------------------------------
    for field_index in "${!schema_fields[@]}"; do

        field_name="${schema_fields[$field_index]}"
        field_value="${row_values[$field_index]}"
        value_key="${collection_id}|${row_index}|${field_name}"


        STOLEUS_METADATA_VALUES["$value_key"]="$field_value"
    done


    STOLEUS_METADATA_COLLECTION_ROW_COUNTS["$collection_id"]="$((row_index + 1))"


    return 0
}


# ==============================================================================
# stoleus_metadata_collection_freeze
# ==============================================================================

stoleus_metadata_collection_freeze() {

    local collection_id="${1:-}"


    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata freeze requires a collection ID." >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    STOLEUS_METADATA_COLLECTION_FROZEN["$collection_id"]="true"


    return 0
}


# ==============================================================================
# stoleus_metadata_collection_get_index
# ==============================================================================

stoleus_metadata_collection_get_index() {

    local collection_id="${1:-}"
    local record_key="${2:-}"
    local lookup_key=""


    if [[ -z "$collection_id" || -z "$record_key" ]]; then

        printf '%s\n' \
            "ERROR: Metadata index lookup requires collection ID and record key." \
            >&2

        return 2
    fi


    if ! stoleus_metadata_collection_contains \
        "$collection_id" \
        "$record_key"; then

        printf '%s\n' \
            "ERROR: Unknown metadata key '${record_key}' in collection '${collection_id}'." \
            >&2

        return 6
    fi


    lookup_key="${collection_id}|${record_key}"


    printf '%s\n' \
        "${STOLEUS_METADATA_ROW_INDEX_BY_KEY[$lookup_key]}"

    return 0
}


# ==============================================================================
# stoleus_metadata_collection_get_key_by_index
# ==============================================================================
#
# Purpose:
#     Return the record key stored at one numeric row index.
#
# Arguments:
#
#     $1 = collection ID
#     $2 = numeric row index
# ==============================================================================

stoleus_metadata_collection_get_key_by_index() {

    local collection_id="${1:-}"
    local row_index="${2:-}"

    local row_count=0
    local row_key=""


    if [[ -z "$collection_id" ||
          -z "$row_index" ||
          ! "$row_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Metadata indexed-key lookup requires collection ID and numeric row index." \
            >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    row_count="${STOLEUS_METADATA_COLLECTION_ROW_COUNTS[$collection_id]}"


    if (( row_index >= row_count )); then

        printf '%s\n' \
            "ERROR: Metadata row index is outside the valid range: ${row_index}" \
            >&2

        return 6
    fi


    row_key="${STOLEUS_METADATA_ROW_KEYS["${collection_id}|${row_index}"]:-}"


    if [[ -z "$row_key" ]]; then

        printf '%s\n' \
            "ERROR: Metadata row key is unavailable at index ${row_index} in collection '${collection_id}'." \
            >&2

        return 6
    fi


    printf '%s\n' "$row_key"

    return 0
}


# ==============================================================================
# stoleus_metadata_collection_get_field
# ==============================================================================

stoleus_metadata_collection_get_field() {

    local collection_id="${1:-}"
    local record_key="${2:-}"
    local field_name="${3:-}"

    local schema=""
    local row_index=""
    local value_key=""


    if [[ -z "$collection_id" ||
          -z "$record_key" ||
          -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Metadata field lookup requires collection ID, key, and field name." \
            >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    schema="${STOLEUS_METADATA_COLLECTION_SCHEMAS[$collection_id]}"


    if ! stoleus_metadata_schema_contains_field \
        "$schema" \
        "$field_name"; then

        printf '%s\n' \
            "ERROR: Unknown field '${field_name}' in metadata collection '${collection_id}'." \
            >&2

        return 2
    fi


    row_index="$(
        stoleus_metadata_collection_get_index \
            "$collection_id" \
            "$record_key"
    )" || return $?


    value_key="${collection_id}|${row_index}|${field_name}"


    printf '%s\n' \
        "${STOLEUS_METADATA_VALUES[$value_key]:-}"

    return 0
}


# ==============================================================================
# stoleus_metadata_collection_get_schema
# ==============================================================================

stoleus_metadata_collection_get_schema() {

    local collection_id="${1:-}"


    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata schema lookup requires a collection ID." >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    printf '%s\n' \
        "${STOLEUS_METADATA_COLLECTION_SCHEMAS[$collection_id]}"

    return 0
}


# ==============================================================================
# stoleus_metadata_collection_get_count
# ==============================================================================

stoleus_metadata_collection_get_count() {

    local collection_id="${1:-}"


    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata count lookup requires a collection ID." >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    printf '%s\n' \
        "${STOLEUS_METADATA_COLLECTION_ROW_COUNTS[$collection_id]}"

    return 0
}


# ==============================================================================
# stoleus_metadata_collection_list
# ==============================================================================
#
# Purpose:
#     Print every row in deterministic insertion order.
#
# Arguments:
#
#     $1 = collection ID
#     optional remaining arguments = selected fields
#
# When no selected fields are supplied, the complete schema is printed.
#
# Output:
#
#     Tab-separated field values, one row per line.
# ==============================================================================

stoleus_metadata_collection_list() {

    local collection_id="${1:-}"

    local schema=""
    local row_count=0
    local row_index=0

    local field_name=""
    local field_value=""
    local value_key=""
    local output_line=""

    local -a selected_fields=()


    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata listing requires a collection ID." >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then

        printf '%s\n' \
            "ERROR: Unknown metadata collection: $collection_id" >&2

        return 6
    fi


    shift


    schema="${STOLEUS_METADATA_COLLECTION_SCHEMAS[$collection_id]}"
    row_count="${STOLEUS_METADATA_COLLECTION_ROW_COUNTS[$collection_id]}"


    if (( $# == 0 )); then
        IFS=',' read -r -a selected_fields <<< "$schema"
    else
        selected_fields=("$@")
    fi


    for field_name in "${selected_fields[@]}"; do

        if ! stoleus_metadata_schema_contains_field \
            "$schema" \
            "$field_name"; then

            printf '%s\n' \
                "ERROR: Unknown field '${field_name}' in metadata collection '${collection_id}'." \
                >&2

            return 2
        fi
    done


    for ((row_index = 0; row_index < row_count; row_index++)); do

        output_line=""


        for field_name in "${selected_fields[@]}"; do

            value_key="${collection_id}|${row_index}|${field_name}"
            field_value="${STOLEUS_METADATA_VALUES[$value_key]:-}"


            if [[ -n "$output_line" ]]; then
                output_line+=$'\t'
            fi


            output_line+="$field_value"
        done


        printf '%s\n' "$output_line"
    done


    return 0
}


# ==============================================================================
# stoleus_metadata_collection_reset
# ==============================================================================
#
# Purpose:
#     Delete one collection and all of its rows.
#
# Primarily intended for tests and explicit framework resets.
# ==============================================================================

stoleus_metadata_collection_reset() {

    local collection_id="${1:-}"

    local composite_key=""
    local prefix=""


    if [[ -z "$collection_id" ]]; then

        printf '%s\n' \
            "ERROR: Metadata collection reset requires a collection ID." >&2

        return 2
    fi


    if ! stoleus_metadata_collection_exists "$collection_id"; then
        return 0
    fi


    prefix="${collection_id}|"


    for composite_key in "${!STOLEUS_METADATA_ROW_INDEX_BY_KEY[@]}"; do

        if [[ "$composite_key" == "$prefix"* ]]; then
            unset 'STOLEUS_METADATA_ROW_INDEX_BY_KEY[$composite_key]'
        fi
    done


    for composite_key in "${!STOLEUS_METADATA_ROW_KEYS[@]}"; do

        if [[ "$composite_key" == "$prefix"* ]]; then
            unset 'STOLEUS_METADATA_ROW_KEYS[$composite_key]'
        fi
    done


    for composite_key in "${!STOLEUS_METADATA_VALUES[@]}"; do

        if [[ "$composite_key" == "$prefix"* ]]; then
            unset 'STOLEUS_METADATA_VALUES[$composite_key]'
        fi
    done


    unset 'STOLEUS_METADATA_COLLECTION_DEFINED[$collection_id]'
    unset 'STOLEUS_METADATA_COLLECTION_KEY_FIELDS[$collection_id]'
    unset 'STOLEUS_METADATA_COLLECTION_SCHEMAS[$collection_id]'
    unset 'STOLEUS_METADATA_COLLECTION_FIELD_COUNTS[$collection_id]'
    unset 'STOLEUS_METADATA_COLLECTION_ROW_COUNTS[$collection_id]'
    unset 'STOLEUS_METADATA_COLLECTION_FROZEN[$collection_id]'


    return 0
}


# ==============================================================================
# stoleus_metadata_reset
# ==============================================================================

stoleus_metadata_reset() {

    STOLEUS_METADATA_COLLECTION_DEFINED=()
    STOLEUS_METADATA_COLLECTION_KEY_FIELDS=()
    STOLEUS_METADATA_COLLECTION_SCHEMAS=()
    STOLEUS_METADATA_COLLECTION_FIELD_COUNTS=()
    STOLEUS_METADATA_COLLECTION_ROW_COUNTS=()
    STOLEUS_METADATA_COLLECTION_FROZEN=()

    STOLEUS_METADATA_ROW_INDEX_BY_KEY=()
    STOLEUS_METADATA_ROW_KEYS=()
    STOLEUS_METADATA_VALUES=()


    return 0
}


# ==============================================================================
# stoleus_metadata_initialize
# ==============================================================================

stoleus_metadata_initialize() {

    if [[ "${STOLEUS_METADATA_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_metadata_reset || return $?


    STOLEUS_METADATA_INITIALIZED="true"

    return 0
}
