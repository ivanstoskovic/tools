#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Registry
# ==============================================================================
#
# Purpose:
#     Import service requirements and provider declarations from the immutable
#     Plugin Registry, validate them against the immutable Contract Registry,
#     and expose normalized provider records.
#
# Processing flow:
#
#     Plugin Registry
#         ↓
#     Required-service validation
#         ↓
#     Provided-service parsing
#         ↓
#     Contract operation validation
#         ↓
#     Generic Metadata Collection: service-providers
#         ↓
#     Frozen Service Registry
#
# Public API:
#
#     stoleus_service_registry_initialize
#     stoleus_service_registry_import_plugins
#     stoleus_service_registry_contains
#     stoleus_service_registry_get_count
#     stoleus_service_registry_get_field
#     stoleus_service_registry_get_provider
#     stoleus_service_registry_get_operation_binding
#     stoleus_service_registry_list
#     stoleus_service_registry_list_providers
#     stoleus_service_registry_is_frozen
#     stoleus_service_registry_reset
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_SERVICE_REGISTRY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_SERVICE_REGISTRY_SUBSYSTEM_LOADED="true"


readonly STOLEUS_SERVICE_REGISTRY_COLLECTION_ID="service-providers"


# ==============================================================================
# stoleus_service_registry_is_frozen
# ==============================================================================

stoleus_service_registry_is_frozen() {

    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID"; then

        return 1
    fi


    stoleus_metadata_collection_is_frozen \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID"
}


# ==============================================================================
# stoleus_service_registry_create_collection
# ==============================================================================

stoleus_service_registry_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
        "provider-key" \
        "provider-key" \
        "service-id" \
        "provider-plugin-id" \
        "contract-version" \
        "priority" \
        "operation-bindings" \
        "conditions" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_service_registry_reset
# ==============================================================================

stoleus_service_registry_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_SERVICE_REGISTRY_IMPORTED="false"
    STOLEUS_SERVICE_REGISTRY_READY="false"


    stoleus_service_registry_create_collection || return $?


    return 0
}


# ==============================================================================
# stoleus_service_registry_contains
# ==============================================================================

stoleus_service_registry_contains() {

    local provider_key="${1:-}"


    if [[ -z "$provider_key" ]]; then
        return 2
    fi


    stoleus_metadata_collection_contains \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
        "$provider_key"
}


# ==============================================================================
# stoleus_service_registry_get_count
# ==============================================================================

stoleus_service_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_service_registry_get_field
# ==============================================================================

stoleus_service_registry_get_field() {

    local provider_key="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$provider_key" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Service Registry field lookup requires provider key and field name." \
            >&2

        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
        "$provider_key" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_service_registry_parse_list
# ==============================================================================

stoleus_service_registry_parse_list() {

    local values="${1:-}"
    local delimiter="${2:-,}"


    if [[ -z "$values" ]]; then
        return 0
    fi


    printf '%s\n' "$values" |
        tr "$delimiter" '\n'

    return 0
}


# ==============================================================================
# stoleus_service_registry_validate_required_services
# ==============================================================================

stoleus_service_registry_validate_required_services() {

    local plugin_id="${1:-}"
    local required_services="${2:-}"

    local service_id=""
    local -A seen_services=()


    while IFS= read -r service_id; do

        [[ -z "$service_id" ]] && continue


        if [[ ! "$service_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' requires an invalid service ID: ${service_id}" \
                >&2

            return 6
        fi


        if [[ -n "${seen_services[$service_id]+seen}" ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' declares duplicate required service: ${service_id}" \
                >&2

            return 8
        fi


        seen_services["$service_id"]="true"


        if ! stoleus_contract_registry_contains "$service_id"; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' requires an unknown service contract: ${service_id}" \
                >&2

            return 6
        fi

    done < <(
        stoleus_service_registry_parse_list \
            "$required_services" \
            ","
    )


    return 0
}


# ==============================================================================
# stoleus_service_registry_binding_exists
# ==============================================================================

stoleus_service_registry_binding_exists() {

    local bindings="${1:-}"
    local requested_operation="${2:-}"

    local binding=""
    local operation_id=""
    local function_name=""


    while IFS= read -r binding; do

        [[ -z "$binding" ]] && continue


        IFS='|' read -r \
            operation_id \
            function_name \
            <<< "$binding"


        if [[ "$operation_id" == "$requested_operation" ]]; then
            return 0
        fi

    done < <(
        stoleus_service_registry_parse_list \
            "$bindings" \
            ";"
    )


    return 1
}


# ==============================================================================
# stoleus_service_registry_validate_bindings
# ==============================================================================

stoleus_service_registry_validate_bindings() {

    local plugin_id="${1:-}"
    local service_id="${2:-}"
    local bindings="${3:-}"

    local contract_operations=""
    local contract_operation=""

    local binding=""
    local operation_id=""
    local function_name=""

    local normalized_bindings=""

    local -A contract_operation_set=()
    local -A bound_operation_set=()


    contract_operations="$(
        stoleus_contract_registry_get_field \
            "$service_id" \
            "operations"
    )" || return $?


    while IFS= read -r contract_operation; do

        [[ -z "$contract_operation" ]] && continue

        contract_operation_set["$contract_operation"]="true"

    done < <(
        stoleus_service_registry_parse_list \
            "$contract_operations" \
            ","
    )


    while IFS= read -r binding; do

        [[ -z "$binding" ]] && continue


        IFS='|' read -r \
            operation_id \
            function_name \
            <<< "$binding"


        if [[ -z "$operation_id" || -z "$function_name" ]]; then

            printf '%s\n' \
                "ERROR: Provider '${plugin_id}' has malformed bindings for service '${service_id}'." \
                >&2

            return 6
        fi


        if [[ -z "${contract_operation_set[$operation_id]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Provider '${plugin_id}' binds unknown operation '${operation_id}' for service '${service_id}'." \
                >&2

            return 6
        fi


        if [[ -n "${bound_operation_set[$operation_id]+bound}" ]]; then

            printf '%s\n' \
                "ERROR: Provider '${plugin_id}' binds service operation more than once: ${service_id}.${operation_id}" \
                >&2

            return 8
        fi


        if [[ ! "$function_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

            printf '%s\n' \
                "ERROR: Provider '${plugin_id}' has an invalid function binding for ${service_id}.${operation_id}: ${function_name}" \
                >&2

            return 6
        fi


        bound_operation_set["$operation_id"]="true"


        if [[ -n "$normalized_bindings" ]]; then
            normalized_bindings+=";"
        fi


        normalized_bindings+="${operation_id}|${function_name}"

    done < <(
        stoleus_service_registry_parse_list \
            "$bindings" \
            ";"
    )


    for contract_operation in "${!contract_operation_set[@]}"; do

        if [[ -z "${bound_operation_set[$contract_operation]+bound}" ]]; then

            printf '%s\n' \
                "ERROR: Provider '${plugin_id}' does not bind required operation: ${service_id}.${contract_operation}" \
                >&2

            return 6
        fi
    done


    printf '%s\n' "$normalized_bindings"

    return 0
}


# ==============================================================================
# stoleus_service_registry_extract_bindings
# ==============================================================================

stoleus_service_registry_extract_bindings() {

    local service_id="${1:-}"
    local all_bindings="${2:-}"

    local binding=""
    local binding_service=""
    local operation_id=""
    local function_name=""

    local filtered=""


    while IFS= read -r binding; do

        [[ -z "$binding" ]] && continue


        IFS='|' read -r \
            binding_service \
            operation_id \
            function_name \
            <<< "$binding"


        if [[ "$binding_service" != "$service_id" ]]; then
            continue
        fi


        if [[ -n "$filtered" ]]; then
            filtered+=";"
        fi


        filtered+="${operation_id}|${function_name}"

    done < <(
        stoleus_service_registry_parse_list \
            "$all_bindings" \
            ";"
    )


    printf '%s\n' "$filtered"

    return 0
}


# ==============================================================================
# stoleus_service_registry_extract_conditions
# ==============================================================================

stoleus_service_registry_extract_conditions() {

    local service_id="${1:-}"
    local all_conditions="${2:-}"

    local condition=""
    local condition_service=""
    local context_key=""
    local expected_value=""

    local normalized=""
    local condition_key=""

    local -A seen_conditions=()


    while IFS= read -r condition; do

        [[ -z "$condition" ]] && continue


        IFS='|' read -r \
            condition_service \
            context_key \
            expected_value \
            <<< "$condition"


        [[ "$condition_service" != "$service_id" ]] && continue


        if [[ -z "$context_key" || -z "$expected_value" ]]; then

            printf '%s\n' \
                "ERROR: Service '${service_id}' contains malformed provider-condition metadata." \
                >&2

            return 6
        fi


        if [[ ! "$context_key" =~ ^[a-z][a-z0-9-]*$ ]]; then

            printf '%s\n' \
                "ERROR: Service '${service_id}' contains an invalid provider-condition key: ${context_key}" \
                >&2

            return 6
        fi


        condition_key="${service_id}|${context_key}"


        if [[ -n "${seen_conditions[$condition_key]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Service '${service_id}' contains duplicate provider condition: ${context_key}" \
                >&2

            return 8
        fi


        seen_conditions["$condition_key"]="true"


        if [[ -n "$normalized" ]]; then
            normalized+=";"
        fi


        normalized+="${context_key}=${expected_value}"

    done < <(
        stoleus_service_registry_parse_list \
            "$all_conditions" \
            ";"
    )


    printf '%s\n' "$normalized"

    return 0
}


# ==============================================================================
# stoleus_service_registry_import_provider
# ==============================================================================

stoleus_service_registry_import_provider() {

    local plugin_id="${1:-}"
    local provider_record="${2:-}"
    local all_bindings="${3:-}"
    local all_conditions="${4:-}"

    local service_id=""
    local contract_version=""
    local priority=""
    local registered_contract_version=""

    local provider_key=""
    local service_bindings=""
    local normalized_bindings=""
    local normalized_conditions=""


    IFS='|' read -r \
        service_id \
        contract_version \
        priority \
        <<< "$provider_record"


    if [[ -z "$service_id" ||
          -z "$contract_version" ||
          -z "$priority" ]]; then

        printf '%s\n' \
            "ERROR: Plugin '${plugin_id}' contains a malformed provided-service record." \
            >&2

        return 6
    fi


    if ! stoleus_contract_registry_contains "$service_id"; then

        printf '%s\n' \
            "ERROR: Provider '${plugin_id}' implements an unknown service contract: ${service_id}" \
            >&2

        return 6
    fi


    if [[ ! "$contract_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Provider '${plugin_id}' declares an invalid contract version for '${service_id}': ${contract_version}" \
            >&2

        return 6
    fi


    if [[ ! "$priority" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Provider '${plugin_id}' declares an invalid priority for '${service_id}': ${priority}" \
            >&2

        return 6
    fi


    registered_contract_version="$(
        stoleus_contract_registry_get_field \
            "$service_id" \
            "version"
    )" || return $?


    if [[ "$contract_version" != "$registered_contract_version" ]]; then

        printf '%s\n' \
            "ERROR: Provider '${plugin_id}' implements contract '${service_id}' version ${contract_version}, but the registered version is ${registered_contract_version}." \
            >&2

        return 6
    fi


    provider_key="${service_id}@${plugin_id}"


    if stoleus_service_registry_contains "$provider_key"; then

        printf '%s\n' \
            "ERROR: Duplicate service provider registration: ${provider_key}" \
            >&2

        return 8
    fi


    service_bindings="$(
        stoleus_service_registry_extract_bindings \
            "$service_id" \
            "$all_bindings"
    )" || return $?


    normalized_bindings="$(
        stoleus_service_registry_validate_bindings \
            "$plugin_id" \
            "$service_id" \
            "$service_bindings"
    )" || return $?


    normalized_conditions="$(
        stoleus_service_registry_extract_conditions \
            "$service_id" \
            "$all_conditions"
    )" || return $?


    stoleus_metadata_collection_append \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
        "$provider_key" \
        "$service_id" \
        "$plugin_id" \
        "$contract_version" \
        "$priority" \
        "$normalized_bindings" \
        "$normalized_conditions" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_service_registry_import_plugin
# ==============================================================================

stoleus_service_registry_import_plugin() {

    local plugin_id="${1:-}"

    local required_services=""
    local provided_services=""
    local all_bindings=""
    local all_conditions=""

    local provider_record=""


    required_services="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "required-services"
    )" || return $?


    provided_services="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "provided-services"
    )" || return $?


    all_bindings="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "service-operation-bindings"
    )" || return $?


    all_conditions="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "service-conditions"
    )" || return $?


    stoleus_service_registry_validate_required_services \
        "$plugin_id" \
        "$required_services" ||
        return $?


    while IFS= read -r provider_record; do

        [[ -z "$provider_record" ]] && continue


        stoleus_service_registry_import_provider \
            "$plugin_id" \
            "$provider_record" \
            "$all_bindings" \
            "$all_conditions" ||
            return $?

    done < <(
        stoleus_service_registry_parse_list \
            "$provided_services" \
            ";"
    )


    return 0
}


# ==============================================================================
# stoleus_service_registry_import_plugins
# ==============================================================================

stoleus_service_registry_import_plugins() {

    local plugin_id=""


    if [[ "${STOLEUS_SERVICE_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Service Registry must be initialized before import." >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Plugin Registry must be frozen before Service Registry import." \
            >&2

        return 6
    fi


    if ! stoleus_contract_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Contract Registry must be frozen before Service Registry import." \
            >&2

        return 6
    fi


    if stoleus_service_registry_is_frozen; then
        return 0
    fi


    if [[ "${STOLEUS_SERVICE_REGISTRY_IMPORTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: Plugins were already imported into the Service Registry." \
            >&2

        return 8
    fi


    while IFS= read -r plugin_id; do

        [[ -z "$plugin_id" ]] && continue


        stoleus_service_registry_import_plugin \
            "$plugin_id" ||
            return $?

    done < <(
        stoleus_registry_list_ids
    )


    STOLEUS_SERVICE_REGISTRY_IMPORTED="true"


    stoleus_metadata_collection_freeze \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_SERVICE_REGISTRY_READY="true"


    return 0
}


# ==============================================================================
# stoleus_service_registry_get_provider
# ==============================================================================

stoleus_service_registry_get_provider() {

    local service_id="${1:-}"
    local plugin_id="${2:-}"


    if [[ -z "$service_id" || -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Service provider lookup requires service ID and plugin ID." \
            >&2

        return 2
    fi


    stoleus_service_registry_get_field \
        "${service_id}@${plugin_id}" \
        "provider-plugin-id"

    return $?
}


# ==============================================================================
# stoleus_service_registry_get_operation_binding
# ==============================================================================

stoleus_service_registry_get_operation_binding() {

    local service_id="${1:-}"
    local plugin_id="${2:-}"
    local requested_operation="${3:-}"

    local bindings=""
    local binding=""
    local operation_id=""
    local function_name=""


    if [[ -z "$service_id" ||
          -z "$plugin_id" ||
          -z "$requested_operation" ]]; then

        printf '%s\n' \
            "ERROR: Service binding lookup requires service ID, plugin ID, and operation ID." \
            >&2

        return 2
    fi


    bindings="$(
        stoleus_service_registry_get_field \
            "${service_id}@${plugin_id}" \
            "operation-bindings"
    )" || return $?


    while IFS= read -r binding; do

        [[ -z "$binding" ]] && continue


        IFS='|' read -r \
            operation_id \
            function_name \
            <<< "$binding"


        if [[ "$operation_id" == "$requested_operation" ]]; then

            printf '%s\n' "$function_name"

            return 0
        fi

    done < <(
        stoleus_service_registry_parse_list \
            "$bindings" \
            ";"
    )


    printf '%s\n' \
        "ERROR: Provider '${plugin_id}' does not expose operation '${service_id}.${requested_operation}'." \
        >&2

    return 6
}


# ==============================================================================
# stoleus_service_registry_list
# ==============================================================================

stoleus_service_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
        "service-id" \
        "provider-plugin-id" \
        "contract-version" \
        "priority"

    return $?
}


# ==============================================================================
# stoleus_service_registry_list_providers
# ==============================================================================

stoleus_service_registry_list_providers() {

    local requested_service="${1:-}"

    local row_count=0
    local row_index=0

    local provider_key=""
    local service_id=""
    local provider_plugin_id=""
    local contract_version=""
    local priority=""


    if [[ -z "$requested_service" ]]; then

        printf '%s\n' \
            "ERROR: Provider listing requires a service ID." >&2

        return 2
    fi


    row_count="$(
        stoleus_service_registry_get_count
    )" || return $?


    for ((row_index = 0; row_index < row_count; row_index++)); do

        provider_key="$(
            stoleus_metadata_collection_get_key_by_index \
                "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
                "$row_index"
        )" || return $?


        service_id="$(
            stoleus_service_registry_get_field \
                "$provider_key" \
                "service-id"
        )" || return $?


        [[ "$service_id" != "$requested_service" ]] && continue


        provider_plugin_id="$(
            stoleus_service_registry_get_field \
                "$provider_key" \
                "provider-plugin-id"
        )" || return $?


        contract_version="$(
            stoleus_service_registry_get_field \
                "$provider_key" \
                "contract-version"
        )" || return $?


        priority="$(
            stoleus_service_registry_get_field \
                "$provider_key" \
                "priority"
        )" || return $?


        printf '%s\t%s\t%s\n' \
            "$provider_plugin_id" \
            "$contract_version" \
            "$priority"
    done


    return 0
}


# ==============================================================================
# stoleus_service_registry_initialize
# ==============================================================================

stoleus_service_registry_initialize() {

    if [[ "${STOLEUS_SERVICE_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_service_registry_reset || return $?


    STOLEUS_SERVICE_REGISTRY_INITIALIZED="true"

    return 0
}
