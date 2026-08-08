#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Provider Policy Registry
# ==============================================================================
#
# Purpose:
#     Store provider decision metadata separately from provider facts.
#
# Provider facts belong to Service/Capability registries.
#
# Policy metadata:
#
#     subject-type
#     subject-id
#     provider-id
#     priority
#     enabled
#     conditions
#     tags
#
# Internal API:
#
#     stoleus_provider_policy_registry_initialize
#     stoleus_provider_policy_registry_reset
#     stoleus_provider_policy_registry_register
#     stoleus_provider_policy_registry_contains
#     stoleus_provider_policy_registry_get_field
#     stoleus_provider_policy_registry_get_count
#     stoleus_provider_policy_registry_list
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_PROVIDER_POLICY_REGISTRY_LOADED:-false}" == "true" ]]; then
    return 0
fi

STOLEUS_PROVIDER_POLICY_REGISTRY_LOADED="true"


readonly STOLEUS_PROVIDER_POLICY_COLLECTION_ID="provider-policy"


STOLEUS_PROVIDER_POLICY_REGISTRY_INITIALIZED="false"


stoleus_provider_policy_registry_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID" \
        "policy-key" \
        "policy-key" \
        "subject-type" \
        "subject-id" \
        "provider-id" \
        "priority" \
        "enabled" \
        "conditions" \
        "tags" ||
        return $?


    return 0
}


stoleus_provider_policy_registry_reset() {

    if [[ "${STOLEUS_PROVIDER_POLICY_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Provider Policy Registry must be initialized before reset." \
            >&2

        return 6
    fi


    stoleus_metadata_collection_reset \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID" ||
        return $?


    # Metadata reset removes the collection definition itself.
    # Recreate the empty schema so the registry remains immediately usable.
    stoleus_provider_policy_registry_create_collection || return $?


    return 0
}


stoleus_provider_policy_registry_validate_subject_type() {

    local subject_type="${1:-}"


    case "$subject_type" in
        capability|service)
            return 0
            ;;
    esac


    printf '%s\n' \
        "ERROR: Unsupported provider-policy subject type: ${subject_type}" \
        >&2

    return 6
}


stoleus_provider_policy_registry_register() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"
    local priority="${4:-0}"
    local enabled="${5:-true}"
    local conditions="${6:-}"
    local tags="${7:-}"

    local policy_key=""


    stoleus_provider_policy_registry_validate_subject_type \
        "$subject_type" ||
        return $?


    if [[ -z "$subject_id" ||
          ! "$subject_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Provider Policy requires a valid subject ID." >&2

        return 2
    fi


    if [[ -z "$provider_id" ||
          ! "$provider_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Provider Policy requires a valid provider ID." >&2

        return 2
    fi


    if [[ ! "$priority" =~ ^[0-9]+$ ||
          "$priority" -gt 100000 ]]; then

        printf '%s\n' \
            "ERROR: Provider Policy priority must be between 0 and 100000." \
            >&2

        return 6
    fi


    case "$enabled" in
        true|false)
            ;;
        *)
            printf '%s\n' \
                "ERROR: Provider Policy enabled flag must be true or false." \
                >&2
            return 6
            ;;
    esac


    policy_key="${subject_type}:${subject_id}@${provider_id}"


    if stoleus_provider_policy_registry_contains "$policy_key"; then

        printf '%s\n' \
            "ERROR: Duplicate provider policy registration: ${policy_key}" \
            >&2

        return 8
    fi


    stoleus_metadata_collection_append \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID" \
        "$policy_key" \
        "$subject_type" \
        "$subject_id" \
        "$provider_id" \
        "$priority" \
        "$enabled" \
        "$conditions" \
        "$tags" ||
        return $?


    return 0
}


stoleus_provider_policy_registry_contains() {

    local policy_key="${1:-}"


    if [[ -z "$policy_key" ]]; then
        return 2
    fi


    stoleus_metadata_collection_contains \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID" \
        "$policy_key"

    return $?
}


stoleus_provider_policy_registry_get_field() {

    local policy_key="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$policy_key" || -z "$field_name" ]]; then
        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID" \
        "$policy_key" \
        "$field_name"

    return $?
}


stoleus_provider_policy_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID"

    return $?
}


stoleus_provider_policy_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_PROVIDER_POLICY_COLLECTION_ID"

    return $?
}


stoleus_provider_policy_registry_initialize() {

    if [[ "${STOLEUS_PROVIDER_POLICY_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_provider_policy_registry_create_collection || return $?


    STOLEUS_PROVIDER_POLICY_REGISTRY_INITIALIZED="true"


    return 0
}
