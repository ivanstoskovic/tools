#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel API Registry
# ==============================================================================
#
# Purpose:
#     Define and validate the supported Stoleus kernel function surface.
#
# API classifications:
#
#     public
#         Stable functions intended for commands, platform integrations, tests,
#         and future external consumers.
#
#     dsl
#         Declarative functions available while parsing plugin or contract
#         manifests.
#
#     internal
#         Explicit cross-subsystem integration points. These are not supported
#         external APIs, but they are registered so architectural dependencies
#         remain visible and verifiable.
#
# The API Registry is the single machine-readable source of truth for:
#
#     - function ownership;
#     - visibility;
#     - subsystem;
#     - stability;
#     - API compatibility snapshots.
#
# Public API:
#
#     stoleus_api_initialize
#     stoleus_api_register
#     stoleus_api_exists
#     stoleus_api_get_field
#     stoleus_api_list
#     stoleus_api_list_subsystems
#     stoleus_api_validate
#     stoleus_api_write_snapshot
#     stoleus_api_compare_snapshot
#     stoleus_api_get_count
#     stoleus_api_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_API_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_API_SUBSYSTEM_LOADED="true"


# ==============================================================================
# API Registry State
# ==============================================================================

declare -a STOLEUS_API_FUNCTIONS=()
declare -a STOLEUS_API_SUBSYSTEMS=()
declare -a STOLEUS_API_VISIBILITIES=()
declare -a STOLEUS_API_STABILITIES=()
declare -a STOLEUS_API_OWNERS=()

declare -A STOLEUS_API_INDEX_BY_FUNCTION=()


# ==============================================================================
# stoleus_api_reset
# ==============================================================================

stoleus_api_reset() {

    STOLEUS_API_FUNCTIONS=()
    STOLEUS_API_SUBSYSTEMS=()
    STOLEUS_API_VISIBILITIES=()
    STOLEUS_API_STABILITIES=()
    STOLEUS_API_OWNERS=()

    STOLEUS_API_INDEX_BY_FUNCTION=()

    STOLEUS_API_REGISTERED="false"
    STOLEUS_API_VALIDATED="false"


    return 0
}


# ==============================================================================
# stoleus_api_validate_identifier
# ==============================================================================

stoleus_api_validate_identifier() {

    local value="${1:-}"
    local label="${2:-identifier}"


    if [[ -z "$value" ]]; then

        printf '%s\n' \
            "ERROR: API ${label} cannot be empty." >&2

        return 2
    fi


    if [[ ! "$value" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid API ${label}: ${value}" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_api_exists
# ==============================================================================

stoleus_api_exists() {

    local function_name="${1:-}"


    if [[ -z "$function_name" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_API_INDEX_BY_FUNCTION[$function_name]+registered}" ]]
}


# ==============================================================================
# stoleus_api_register
# ==============================================================================
#
# Arguments:
#
#     $1 = subsystem
#     $2 = function name
#     $3 = visibility: public, dsl, internal
#     $4 = stability: stable, experimental, internal
#     $5 = owning source file relative to PROJECT_ROOT
# ==============================================================================

stoleus_api_register() {

    local subsystem="${1:-}"
    local function_name="${2:-}"
    local visibility="${3:-}"
    local stability="${4:-}"
    local owner="${5:-}"

    local api_index=0


    stoleus_api_validate_identifier \
        "$subsystem" \
        "subsystem" ||
        return $?


    if [[ -z "$function_name" ||
          ! "$function_name" =~ ^stoleus_[a-zA-Z0-9_]+$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid Stoleus API function name: ${function_name}" \
            >&2

        return 6
    fi


    case "$visibility" in
        public|dsl|internal)
            ;;
        *)

            printf '%s\n' \
                "ERROR: Invalid API visibility for '${function_name}': ${visibility}" \
                >&2

            return 6

            ;;
    esac


    case "$stability" in
        stable|experimental|internal)
            ;;
        *)

            printf '%s\n' \
                "ERROR: Invalid API stability for '${function_name}': ${stability}" \
                >&2

            return 6

            ;;
    esac


    if [[ -z "$owner" ]]; then

        printf '%s\n' \
            "ERROR: API function '${function_name}' requires an owner file." \
            >&2

        return 2
    fi


    if stoleus_api_exists "$function_name"; then

        printf '%s\n' \
            "ERROR: API function is already registered: ${function_name}" \
            >&2

        return 8
    fi


    api_index="${#STOLEUS_API_FUNCTIONS[@]}"

    STOLEUS_API_FUNCTIONS+=("$function_name")
    STOLEUS_API_SUBSYSTEMS+=("$subsystem")
    STOLEUS_API_VISIBILITIES+=("$visibility")
    STOLEUS_API_STABILITIES+=("$stability")
    STOLEUS_API_OWNERS+=("$owner")

    STOLEUS_API_INDEX_BY_FUNCTION["$function_name"]="$api_index"


    return 0
}


# ==============================================================================
# stoleus_api_get_field
# ==============================================================================

stoleus_api_get_field() {

    local function_name="${1:-}"
    local field_name="${2:-}"

    local api_index=""


    if [[ -z "$function_name" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: API lookup requires function name and field name." >&2

        return 2
    fi


    if ! stoleus_api_exists "$function_name"; then

        printf '%s\n' \
            "ERROR: Unknown registered API function: ${function_name}" >&2

        return 6
    fi


    api_index="${STOLEUS_API_INDEX_BY_FUNCTION[$function_name]}"


    case "$field_name" in

        function)
            printf '%s\n' "${STOLEUS_API_FUNCTIONS[$api_index]}"
            ;;

        subsystem)
            printf '%s\n' "${STOLEUS_API_SUBSYSTEMS[$api_index]}"
            ;;

        visibility)
            printf '%s\n' "${STOLEUS_API_VISIBILITIES[$api_index]}"
            ;;

        stability)
            printf '%s\n' "${STOLEUS_API_STABILITIES[$api_index]}"
            ;;

        owner)
            printf '%s\n' "${STOLEUS_API_OWNERS[$api_index]}"
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported API Registry field: ${field_name}" >&2

            return 2

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_api_list
# ==============================================================================
#
# Optional filters:
#
#     $1 = subsystem
#     $2 = visibility
#
# Output:
#
#     subsystem<TAB>function<TAB>visibility<TAB>stability<TAB>owner
# ==============================================================================

stoleus_api_list() {

    local subsystem_filter="${1:-}"
    local visibility_filter="${2:-}"

    local api_index=0


    for api_index in "${!STOLEUS_API_FUNCTIONS[@]}"; do

        if [[ -n "$subsystem_filter" ]] &&
           [[ "${STOLEUS_API_SUBSYSTEMS[$api_index]}" != "$subsystem_filter" ]]; then

            continue
        fi


        if [[ -n "$visibility_filter" ]] &&
           [[ "${STOLEUS_API_VISIBILITIES[$api_index]}" != "$visibility_filter" ]]; then

            continue
        fi


        printf '%s\t%s\t%s\t%s\t%s\n' \
            "${STOLEUS_API_SUBSYSTEMS[$api_index]}" \
            "${STOLEUS_API_FUNCTIONS[$api_index]}" \
            "${STOLEUS_API_VISIBILITIES[$api_index]}" \
            "${STOLEUS_API_STABILITIES[$api_index]}" \
            "${STOLEUS_API_OWNERS[$api_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_api_list_subsystems
# ==============================================================================

stoleus_api_list_subsystems() {

    local subsystem=""
    local -A seen_subsystems=()


    for subsystem in "${STOLEUS_API_SUBSYSTEMS[@]}"; do

        if [[ -n "${seen_subsystems[$subsystem]+seen}" ]]; then
            continue
        fi


        seen_subsystems["$subsystem"]="true"

        printf '%s\n' "$subsystem"
    done


    return 0
}


# ==============================================================================
# stoleus_api_get_count
# ==============================================================================

stoleus_api_get_count() {

    local visibility_filter="${1:-}"
    local api_index=0
    local count=0


    if [[ -z "$visibility_filter" ]]; then

        printf '%s\n' "${#STOLEUS_API_FUNCTIONS[@]}"

        return 0
    fi


    case "$visibility_filter" in
        public|dsl|internal)
            ;;
        *)
            return 2
            ;;
    esac


    for api_index in "${!STOLEUS_API_FUNCTIONS[@]}"; do

        if [[ "${STOLEUS_API_VISIBILITIES[$api_index]}" == "$visibility_filter" ]]; then
            count="$((count + 1))"
        fi
    done


    printf '%s\n' "$count"

    return 0
}


# ==============================================================================
# stoleus_api_validate
# ==============================================================================
#
# Validation:
#
#     - every registered function exists;
#     - every owner file exists;
#     - every function is defined by its declared owner;
#     - public and DSL functions cannot use internal stability;
#     - internal functions must use internal stability.
# ==============================================================================

stoleus_api_validate() {

    local api_index=0

    local function_name=""
    local visibility=""
    local stability=""
    local owner=""
    local owner_path=""


    for api_index in "${!STOLEUS_API_FUNCTIONS[@]}"; do

        function_name="${STOLEUS_API_FUNCTIONS[$api_index]}"
        visibility="${STOLEUS_API_VISIBILITIES[$api_index]}"
        stability="${STOLEUS_API_STABILITIES[$api_index]}"
        owner="${STOLEUS_API_OWNERS[$api_index]}"
        owner_path="${PROJECT_ROOT}/${owner}"


        if ! declare -F "$function_name" >/dev/null 2>&1; then

            printf '%s\n' \
                "ERROR: Registered API function is not loaded: ${function_name}" \
                >&2

            return 6
        fi


        if [[ ! -f "$owner_path" ]]; then

            printf '%s\n' \
                "ERROR: Registered API owner file is missing: ${owner}" \
                >&2

            return 6
        fi


        if ! grep -qE \
            "^${function_name}\\(\\)[[:space:]]*\\{" \
            "$owner_path"; then

            printf '%s\n' \
                "ERROR: API owner mismatch for '${function_name}': ${owner}" \
                >&2

            return 6
        fi


        if [[ "$visibility" == "internal" ]] &&
           [[ "$stability" != "internal" ]]; then

            printf '%s\n' \
                "ERROR: Internal API '${function_name}' must use internal stability." \
                >&2

            return 6
        fi


        if [[ "$visibility" != "internal" ]] &&
           [[ "$stability" == "internal" ]]; then

            printf '%s\n' \
                "ERROR: Supported API '${function_name}' cannot use internal stability." \
                >&2

            return 6
        fi
    done


    STOLEUS_API_VALIDATED="true"

    return 0
}


# ==============================================================================
# stoleus_api_write_snapshot
# ==============================================================================
#
# Arguments:
#
#     $1 = output path
#
# The snapshot contains public and DSL APIs only. Internal integration points
# are intentionally excluded from external compatibility guarantees.
# ==============================================================================

stoleus_api_write_snapshot() {

    local output_path="${1:-}"
    local api_index=0


    if [[ -z "$output_path" ]]; then

        printf '%s\n' \
            "ERROR: API snapshot output path is required." >&2

        return 2
    fi


    mkdir -p "$(dirname -- "$output_path")" || return $?


    {
        printf '%s\n' \
            $'subsystem\tfunction\tvisibility\tstability\towner'


        for api_index in "${!STOLEUS_API_FUNCTIONS[@]}"; do

            if [[ "${STOLEUS_API_VISIBILITIES[$api_index]}" == "internal" ]]; then
                continue
            fi


            printf '%s\t%s\t%s\t%s\t%s\n' \
                "${STOLEUS_API_SUBSYSTEMS[$api_index]}" \
                "${STOLEUS_API_FUNCTIONS[$api_index]}" \
                "${STOLEUS_API_VISIBILITIES[$api_index]}" \
                "${STOLEUS_API_STABILITIES[$api_index]}" \
                "${STOLEUS_API_OWNERS[$api_index]}"

        done

    } > "$output_path"


    return 0
}


# ==============================================================================
# stoleus_api_validate_snapshot
# ==============================================================================
#
# Purpose:
#     Validate the basic structure of one API compatibility snapshot.
#
# Arguments:
#
#     $1 = snapshot path
#
# Required header:
#
#     subsystem
#     function
#     visibility
#     stability
#     owner
#
# Fields are tab-separated.
# ==============================================================================

stoleus_api_validate_snapshot() {

    local snapshot_path="${1:-}"
    local expected_header=""
    local actual_header=""

    local line_number=0
    local subsystem=""
    local function_name=""
    local visibility=""
    local stability=""
    local owner=""
    local extra_field=""


    if [[ -z "$snapshot_path" ]]; then

        printf '%s\n' \
            "ERROR: API snapshot validation requires a path." >&2

        return 2
    fi


    if [[ ! -f "$snapshot_path" ]]; then

        printf '%s\n' \
            "ERROR: API compatibility snapshot does not exist: ${snapshot_path}" \
            >&2

        return 6
    fi


    if [[ ! -s "$snapshot_path" ]]; then

        printf '%s\n' \
            "ERROR: API compatibility snapshot is empty: ${snapshot_path}" \
            >&2

        return 6
    fi


    expected_header=$'subsystem\tfunction\tvisibility\tstability\towner'

    IFS= read -r actual_header < "$snapshot_path" || true


    if [[ "$actual_header" != "$expected_header" ]]; then

        printf '%s\n' \
            "ERROR: API compatibility snapshot has an invalid header: ${snapshot_path}" \
            >&2

        return 6
    fi


    line_number=1


    while IFS=$'\t' read -r \
        subsystem \
        function_name \
        visibility \
        stability \
        owner \
        extra_field; do

        line_number="$((line_number + 1))"


        if [[ -z "$subsystem" &&
              -z "$function_name" &&
              -z "$visibility" &&
              -z "$stability" &&
              -z "$owner" ]]; then

            printf '%s\n' \
                "ERROR: API compatibility snapshot contains an empty record at line ${line_number}." \
                >&2

            return 6
        fi


        if [[ -n "$extra_field" ]]; then

            printf '%s\n' \
                "ERROR: API compatibility snapshot contains too many fields at line ${line_number}." \
                >&2

            return 6
        fi


        if [[ -z "$subsystem" ||
              -z "$function_name" ||
              -z "$visibility" ||
              -z "$stability" ||
              -z "$owner" ]]; then

            printf '%s\n' \
                "ERROR: API compatibility snapshot contains incomplete metadata at line ${line_number}." \
                >&2

            return 6
        fi


        stoleus_api_validate_identifier \
            "$subsystem" \
            "snapshot subsystem" ||
            return $?


        if [[ ! "$function_name" =~ ^stoleus_[a-zA-Z0-9_]+$ ]]; then

            printf '%s\n' \
                "ERROR: API compatibility snapshot contains an invalid function at line ${line_number}: ${function_name}" \
                >&2

            return 6
        fi


        case "$visibility" in
            public|dsl)
                ;;
            *)

                printf '%s\n' \
                    "ERROR: API compatibility snapshot contains unsupported visibility at line ${line_number}: ${visibility}" \
                    >&2

                return 6

                ;;
        esac


        case "$stability" in
            stable|experimental)
                ;;
            *)

                printf '%s\n' \
                    "ERROR: API compatibility snapshot contains unsupported stability at line ${line_number}: ${stability}" \
                    >&2

                return 6

                ;;
        esac

    done < <(
        tail -n +2 "$snapshot_path"
    )


    return 0
}


# ==============================================================================
# stoleus_api_compare_snapshot
# ==============================================================================
#
# Purpose:
#     Compare the live supported API surface with a committed compatibility
#     snapshot.
#
# Arguments:
#
#     $1 = committed baseline path
#     $2 = optional path where the generated live snapshot should be preserved
#
# Return codes:
#
#     0 = live API matches the baseline exactly
#     2 = invalid arguments
#     6 = invalid or unavailable baseline
#     8 = compatibility difference detected
#
# Comparison includes:
#
#     - subsystem ownership;
#     - function name;
#     - visibility;
#     - stability;
#     - owner file.
# ==============================================================================

stoleus_api_compare_snapshot() {

    local baseline_path="${1:-}"
    local preserved_live_path="${2:-}"

    local temporary_root=""
    local live_snapshot=""
    local exit_code=0


    if [[ -z "$baseline_path" ]]; then

        printf '%s\n' \
            "ERROR: API compatibility comparison requires a baseline path." \
            >&2

        return 2
    fi


    if [[ "${STOLEUS_API_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: API Registry must be initialized before compatibility comparison." \
            >&2

        return 6
    fi


    stoleus_api_validate_snapshot \
        "$baseline_path" ||
        return $?


    temporary_root="$(
        mktemp -d
    )" || return $?


    live_snapshot="${temporary_root}/live-kernel-api.tsv"


    if ! stoleus_api_write_snapshot "$live_snapshot"; then

        exit_code=$?

        rm -rf "$temporary_root"

        return "$exit_code"
    fi


    if [[ -n "$preserved_live_path" ]]; then

        mkdir -p \
            "$(dirname -- "$preserved_live_path")" ||
            {
                exit_code=$?
                rm -rf "$temporary_root"
                return "$exit_code"
            }


        cp \
            "$live_snapshot" \
            "$preserved_live_path" ||
            {
                exit_code=$?
                rm -rf "$temporary_root"
                return "$exit_code"
            }
    fi


    if cmp -s \
        "$baseline_path" \
        "$live_snapshot"; then

        rm -rf "$temporary_root"

        return 0
    fi


    printf '%s\n' \
        "ERROR: Kernel API compatibility difference detected." \
        "Baseline: ${baseline_path}" \
        >&2


    if command -v diff >/dev/null 2>&1; then

        printf '%s\n' \
            "Compatibility diff:" \
            >&2

        diff -u \
            "$baseline_path" \
            "$live_snapshot" \
            >&2 ||
            true
    fi


    rm -rf "$temporary_root"

    return 8
}


# ==============================================================================
# stoleus_api_register_defaults
# ==============================================================================
#
# Purpose:
#     Register the supported kernel surface and explicit internal integration
#     points.
# ==============================================================================

stoleus_api_register_defaults() {

    # Kernel
    stoleus_api_register kernel stoleus_kernel_initialize public stable kernel/kernel.sh
    stoleus_api_register kernel stoleus_kernel_bootstrap public stable kernel/kernel.sh
    stoleus_api_register kernel stoleus_kernel_is_ready public stable kernel/kernel.sh
    stoleus_api_register kernel stoleus_kernel_get_status public stable kernel/kernel.sh

    # Runtime Context
    stoleus_api_register context stoleus_context_initialize internal internal kernel/context/context.sh
    stoleus_api_register context stoleus_context_set public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_get public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_contains public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_list public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_matches_conditions internal internal kernel/context/context.sh
    stoleus_api_register context stoleus_context_set_provider_override public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_get_provider_override public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_clear_provider_override public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_list_provider_overrides public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_get_generation public experimental kernel/context/context.sh
    stoleus_api_register context stoleus_context_reset public experimental kernel/context/context.sh

    # Platform Detection
    stoleus_api_register platform stoleus_platform_initialize internal internal kernel/platform/platform.sh
    stoleus_api_register platform stoleus_platform_detect public experimental kernel/platform/platform.sh
    stoleus_api_register platform stoleus_platform_apply_context public experimental kernel/platform/platform.sh
    stoleus_api_register platform stoleus_platform_refresh public experimental kernel/platform/platform.sh
    stoleus_api_register platform stoleus_platform_get public experimental kernel/platform/platform.sh
    stoleus_api_register platform stoleus_platform_get_status public experimental kernel/platform/platform.sh
    stoleus_api_register platform stoleus_platform_reset public experimental kernel/platform/platform.sh

    # Runtime
    stoleus_api_register runtime stoleus_runtime_initialize internal internal kernel/runtime/runtime.sh

    # Metadata
    stoleus_api_register metadata stoleus_metadata_initialize public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_create public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_exists public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_is_frozen public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_append public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_freeze public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_contains public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_get_index public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_get_key_by_index public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_get_field public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_get_schema public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_get_count public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_list public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_collection_reset public stable kernel/metadata/collection.sh
    stoleus_api_register metadata stoleus_metadata_reset public stable kernel/metadata/collection.sh

    # Discovery
    stoleus_api_register discovery stoleus_discovery_initialize internal internal kernel/discovery/discovery.sh
    stoleus_api_register discovery stoleus_discovery_add_root public stable kernel/discovery/discovery.sh
    stoleus_api_register discovery stoleus_discovery_scan public stable kernel/discovery/discovery.sh
    stoleus_api_register discovery stoleus_discovery_get_records public stable kernel/discovery/discovery.sh
    stoleus_api_register discovery stoleus_discovery_reset public stable kernel/discovery/discovery.sh
    stoleus_api_register discovery stoleus_discovery_is_scanned internal internal kernel/discovery/discovery.sh

    # Plugin Definition
    stoleus_api_register definition stoleus_definition_initialize internal internal kernel/definition/definition.sh
    stoleus_api_register definition stoleus_definition_build_all public stable kernel/definition/definition.sh
    stoleus_api_register definition stoleus_definition_get_records public stable kernel/definition/definition.sh
    stoleus_api_register definition stoleus_definition_reset public stable kernel/definition/definition.sh
    stoleus_api_register definition stoleus_definition_is_frozen internal internal kernel/definition/definition.sh
    stoleus_api_register definition stoleus_definition_register internal internal kernel/definition/definition.sh
    stoleus_api_register definition stoleus_manifest_bash_load internal internal kernel/definition/providers/bash.sh

    # Plugin Manifest DSL
    stoleus_api_register plugin-manifest stoleus_plugin_begin dsl stable kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_description dsl stable kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_implementation dsl stable kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_dependencies dsl stable kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_capabilities dsl stable kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_requires_services dsl experimental kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_provides_service dsl experimental kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_service_operation dsl experimental kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_service_condition dsl experimental kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_lifecycle dsl stable kernel/definition/providers/bash.sh
    stoleus_api_register plugin-manifest stoleus_plugin_end dsl stable kernel/definition/providers/bash.sh

    # Plugin Registry
    stoleus_api_register registry stoleus_registry_initialize internal internal kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_import_definitions internal internal kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_contains public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_get_index public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_get_count public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_get_id_by_index public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_get_field public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_get_field_by_index public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_list public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_list_ids public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_is_frozen public stable kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_freeze internal internal kernel/registry/registry.sh
    stoleus_api_register registry stoleus_registry_reset public stable kernel/registry/registry.sh

    # Contract Definition
    stoleus_api_register contract-definition stoleus_contract_definition_initialize internal internal kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_add_root public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_build_all public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_exists public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_get_index public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_get_field public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_list public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_list_operations public stable kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_is_frozen internal internal kernel/contract/definition.sh
    stoleus_api_register contract-definition stoleus_contract_definition_reset public stable kernel/contract/definition.sh

    # Contract DSL
    stoleus_api_register contract-manifest stoleus_contract_begin dsl stable kernel/contract/definition.sh
    stoleus_api_register contract-manifest stoleus_contract_description dsl stable kernel/contract/definition.sh
    stoleus_api_register contract-manifest stoleus_contract_version dsl stable kernel/contract/definition.sh
    stoleus_api_register contract-manifest stoleus_contract_operation dsl stable kernel/contract/definition.sh
    stoleus_api_register contract-manifest stoleus_contract_end dsl stable kernel/contract/definition.sh

    # Contract Registry
    stoleus_api_register contract-registry stoleus_contract_registry_initialize internal internal kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_import_definitions internal internal kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_contains public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_get_index public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_get_field public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_get_count public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_list public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_list_operations public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_is_frozen public stable kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_freeze internal internal kernel/contract/registry.sh
    stoleus_api_register contract-registry stoleus_contract_registry_reset public stable kernel/contract/registry.sh

    # Service Registry
    stoleus_api_register service-registry stoleus_service_registry_initialize internal internal kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_import_plugins internal internal kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_contains public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_get_count public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_get_field public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_get_provider public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_get_operation_binding public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_list public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_list_providers public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_is_frozen public experimental kernel/service/registry.sh
    stoleus_api_register service-registry stoleus_service_registry_reset public experimental kernel/service/registry.sh

    # Service Provider Resolver
    stoleus_api_register service-resolver stoleus_service_resolver_initialize internal internal kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_resolve public experimental kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_get_provider public experimental kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_get_provider_plugin public experimental kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_get_operation_binding public experimental kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_validate_registry internal internal kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_get_resolved public experimental kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_is_resolved public experimental kernel/service/resolver.sh
    stoleus_api_register service-resolver stoleus_service_resolver_reset public experimental kernel/service/resolver.sh

    # Service Invocation Runtime
    stoleus_api_register service-runtime stoleus_service_runtime_initialize internal internal kernel/service/runtime.sh
    stoleus_api_register service-runtime stoleus_service_call public experimental kernel/service/runtime.sh
    stoleus_api_register service-runtime stoleus_service_get_provider public experimental kernel/service/runtime.sh
    stoleus_api_register service-runtime stoleus_service_get_operation public experimental kernel/service/runtime.sh
    stoleus_api_register service-runtime stoleus_service_runtime_get_last_call public experimental kernel/service/runtime.sh
    stoleus_api_register service-runtime stoleus_service_runtime_reset public experimental kernel/service/runtime.sh

    # Resolver
    stoleus_api_register resolver stoleus_resolver_initialize internal internal kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_resolve public stable kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_resolve_index public stable kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_resolve_dependencies public stable kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_validate_plugin public stable kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_validate_registry internal internal kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_get_resolved public stable kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_reset public stable kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_parse_reference_list internal internal kernel/resolver/resolver.sh
    stoleus_api_register resolver stoleus_resolver_require_registry internal internal kernel/resolver/resolver.sh

    # Plugin Manager
    stoleus_api_register plugin stoleus_plugin_initialize internal internal kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_activate internal internal kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_is_active public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_exists public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_get public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_get_field public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_list public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_list_operations public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_supports_operation public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_get_dependencies public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_get_capabilities public stable kernel/plugin/plugin.sh
    stoleus_api_register plugin stoleus_plugin_get_runtime_state public stable kernel/plugin/plugin.sh

    # Planning
    stoleus_api_register planning stoleus_planning_initialize internal internal kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_create_request public stable kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_build_plan public stable kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_get_request public stable kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_get_plugins public stable kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_get_steps public stable kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_is_plan_frozen internal internal kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_get_lifecycle_function internal internal kernel/planning/planning.sh
    stoleus_api_register planning stoleus_planning_reset public stable kernel/planning/planning.sh

    # Lifecycle
    stoleus_api_register lifecycle stoleus_lifecycle_initialize internal internal kernel/lifecycle/lifecycle.sh
    stoleus_api_register lifecycle stoleus_lifecycle_load_plugin public stable kernel/lifecycle/lifecycle.sh
    stoleus_api_register lifecycle stoleus_lifecycle_is_plugin_loaded public stable kernel/lifecycle/lifecycle.sh
    stoleus_api_register lifecycle stoleus_lifecycle_invoke internal internal kernel/lifecycle/lifecycle.sh
    stoleus_api_register lifecycle stoleus_lifecycle_get_loaded public stable kernel/lifecycle/lifecycle.sh
    stoleus_api_register lifecycle stoleus_lifecycle_reset public stable kernel/lifecycle/lifecycle.sh

    # Execution
    stoleus_api_register execution stoleus_execution_initialize internal internal kernel/execution/execution.sh
    stoleus_api_register execution stoleus_execution_execute_plan public stable kernel/execution/execution.sh
    stoleus_api_register execution stoleus_execution_get_results public stable kernel/execution/execution.sh
    stoleus_api_register execution stoleus_execution_reset public stable kernel/execution/execution.sh

    # API Registry
    stoleus_api_register api stoleus_api_initialize public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_register public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_exists public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_get_field public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_list public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_list_subsystems public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_validate public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_write_snapshot public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_compare_snapshot public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_get_count public stable kernel/api/api.sh
    stoleus_api_register api stoleus_api_reset public stable kernel/api/api.sh


    STOLEUS_API_REGISTERED="true"

    return 0
}


# ==============================================================================
# stoleus_api_initialize
# ==============================================================================

stoleus_api_initialize() {

    if [[ "${STOLEUS_API_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_api_reset || return $?
    stoleus_api_register_defaults || return $?
    stoleus_api_validate || return $?


    STOLEUS_API_INITIALIZED="true"

    return 0
}
