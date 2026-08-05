#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Bash Manifest Provider
# ==============================================================================
#
# Purpose:
#     Parse side-effect-free Bash DSL manifests and produce normalized
#     PluginDefinitions.
#
# Manifest DSL:
#
#     stoleus_plugin_begin "plugin-id"
#
#     stoleus_plugin_description \
#         "Human-readable description"
#
#     stoleus_plugin_implementation \
#         "implementation.sh"
#
#     stoleus_plugin_dependencies \
#         "dependency-one" \
#         "dependency-two"
#
#     stoleus_plugin_capabilities \
#         "package-manager" \
#         "service-manager"
#
#     stoleus_plugin_lifecycle \
#         "install" \
#         "plugin_install"
#
#     stoleus_plugin_lifecycle \
#         "verify" \
#         "plugin_verify"
#
#     stoleus_plugin_end
#
# Manifest restrictions:
#
#     - metadata declarations only;
#     - no infrastructure changes;
#     - no network calls;
#     - no package installation;
#     - no implementation sourcing.
#
# The provider cannot completely sandbox arbitrary Bash. Manifest review and
# future static validation remain necessary security controls.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Bash Manifest Builder State
# ==============================================================================

STOLEUS_MANIFEST_BUILD_ACTIVE="false"
STOLEUS_MANIFEST_BUILD_COMPLETED="false"

STOLEUS_MANIFEST_PLUGIN_ID=""
STOLEUS_MANIFEST_DESCRIPTION=""
STOLEUS_MANIFEST_IMPLEMENTATION=""
STOLEUS_MANIFEST_DEPENDENCIES=""
STOLEUS_MANIFEST_CAPABILITIES=""

STOLEUS_MANIFEST_INSTALL_FUNCTION=""
STOLEUS_MANIFEST_CONFIGURE_FUNCTION=""
STOLEUS_MANIFEST_VERIFY_FUNCTION=""
STOLEUS_MANIFEST_UPGRADE_FUNCTION=""
STOLEUS_MANIFEST_REMOVE_FUNCTION=""


# ==============================================================================
# stoleus_manifest_bash_reset
# ==============================================================================

stoleus_manifest_bash_reset() {

    STOLEUS_MANIFEST_BUILD_ACTIVE="false"
    STOLEUS_MANIFEST_BUILD_COMPLETED="false"

    STOLEUS_MANIFEST_PLUGIN_ID=""
    STOLEUS_MANIFEST_DESCRIPTION=""
    STOLEUS_MANIFEST_IMPLEMENTATION=""
    STOLEUS_MANIFEST_DEPENDENCIES=""
    STOLEUS_MANIFEST_CAPABILITIES=""

    STOLEUS_MANIFEST_INSTALL_FUNCTION=""
    STOLEUS_MANIFEST_CONFIGURE_FUNCTION=""
    STOLEUS_MANIFEST_VERIFY_FUNCTION=""
    STOLEUS_MANIFEST_UPGRADE_FUNCTION=""
    STOLEUS_MANIFEST_REMOVE_FUNCTION=""


    return 0
}


# ==============================================================================
# stoleus_manifest_require_active
# ==============================================================================

stoleus_manifest_require_active() {

    if [[ "$STOLEUS_MANIFEST_BUILD_ACTIVE" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Manifest declaration used outside stoleus_plugin_begin/end." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_manifest_join_values
# ==============================================================================
#
# Purpose:
#     Normalize a list of DSL arguments into a comma-separated value.
# ==============================================================================

stoleus_manifest_join_values() {

    local value=""
    local result=""


    for value in "$@"; do

        if [[ -z "$value" ]]; then
            continue
        fi


        if [[ -n "$result" ]]; then
            result+=","
        fi


        result+="$value"
    done


    printf '%s' "$result"

    return 0
}


# ==============================================================================
# stoleus_plugin_begin
# ==============================================================================

stoleus_plugin_begin() {

    local plugin_id="${1:-}"


    if [[ "$STOLEUS_MANIFEST_BUILD_ACTIVE" == "true" ]]; then

        printf '%s\n' \
            "ERROR: A plugin manifest definition is already active." >&2

        return 8
    fi


    stoleus_manifest_bash_reset


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: stoleus_plugin_begin requires a plugin ID." >&2

        return 2
    fi


    STOLEUS_MANIFEST_PLUGIN_ID="$plugin_id"
    STOLEUS_MANIFEST_BUILD_ACTIVE="true"


    return 0
}


# ==============================================================================
# stoleus_plugin_description
# ==============================================================================

stoleus_plugin_description() {

    local description="${1:-}"


    stoleus_manifest_require_active || return $?


    if [[ -z "$description" ]]; then

        printf '%s\n' \
            "ERROR: Plugin description cannot be empty." >&2

        return 2
    fi


    STOLEUS_MANIFEST_DESCRIPTION="$description"

    return 0
}


# ==============================================================================
# stoleus_plugin_implementation
# ==============================================================================

stoleus_plugin_implementation() {

    local implementation="${1:-}"


    stoleus_manifest_require_active || return $?


    if [[ -z "$implementation" ]]; then

        printf '%s\n' \
            "ERROR: Plugin implementation reference cannot be empty." >&2

        return 2
    fi


    STOLEUS_MANIFEST_IMPLEMENTATION="$implementation"

    return 0
}


# ==============================================================================
# stoleus_plugin_dependencies
# ==============================================================================

stoleus_plugin_dependencies() {

    stoleus_manifest_require_active || return $?


    STOLEUS_MANIFEST_DEPENDENCIES="$(
        stoleus_manifest_join_values "$@"
    )" || return $?


    return 0
}


# ==============================================================================
# stoleus_plugin_capabilities
# ==============================================================================

stoleus_plugin_capabilities() {

    stoleus_manifest_require_active || return $?


    STOLEUS_MANIFEST_CAPABILITIES="$(
        stoleus_manifest_join_values "$@"
    )" || return $?


    return 0
}


# ==============================================================================
# stoleus_plugin_lifecycle
# ==============================================================================
#
# Arguments:
#
#     $1 = lifecycle stage
#     $2 = implementation function reference
#
# Supported stages:
#
#     install
#     configure
#     verify
#     upgrade
#     remove
# ==============================================================================

stoleus_plugin_lifecycle() {

    local lifecycle_stage="${1:-}"
    local function_reference="${2:-}"


    stoleus_manifest_require_active || return $?


    if [[ -z "$lifecycle_stage" || -z "$function_reference" ]]; then

        printf '%s\n' \
            "ERROR: Lifecycle stage and function reference are required." \
            >&2

        return 2
    fi


    case "$lifecycle_stage" in

        install)
            STOLEUS_MANIFEST_INSTALL_FUNCTION="$function_reference"
            ;;

        configure)
            STOLEUS_MANIFEST_CONFIGURE_FUNCTION="$function_reference"
            ;;

        verify)
            STOLEUS_MANIFEST_VERIFY_FUNCTION="$function_reference"
            ;;

        upgrade)
            STOLEUS_MANIFEST_UPGRADE_FUNCTION="$function_reference"
            ;;

        remove)
            STOLEUS_MANIFEST_REMOVE_FUNCTION="$function_reference"
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported plugin lifecycle stage: $lifecycle_stage" \
                >&2

            return 6

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_plugin_end
# ==============================================================================

stoleus_plugin_end() {

    stoleus_manifest_require_active || return $?


    STOLEUS_MANIFEST_BUILD_ACTIVE="false"
    STOLEUS_MANIFEST_BUILD_COMPLETED="true"


    return 0
}


# ==============================================================================
# stoleus_manifest_bash_load
# ==============================================================================
#
# Purpose:
#     Parse one Bash manifest and register its normalized PluginDefinition.
#
# Arguments:
#
#     $1 = absolute manifest path
#     $2 = discovery category
#     $3 = discovered directory name
#     $4 = absolute plugin directory
#
# The implementation reference is resolved relative to the plugin directory.
# The implementation file is validated but never sourced.
# ==============================================================================

stoleus_manifest_bash_load() {

    local manifest_path="${1:-}"
    local category="${2:-}"
    local discovered_name="${3:-}"
    local plugin_path="${4:-}"

    local implementation_path=""


    if [[ -z "$manifest_path" ||
          -z "$category" ||
          -z "$discovered_name" ||
          -z "$plugin_path" ]]; then

        printf '%s\n' \
            "ERROR: Bash manifest provider received incomplete input." >&2

        return 2
    fi


    if [[ ! -f "$manifest_path" ]]; then

        printf '%s\n' \
            "ERROR: Bash manifest does not exist: $manifest_path" >&2

        return 6
    fi


    stoleus_manifest_bash_reset


    # --------------------------------------------------------------------------
    # Source metadata declarations only.
    #
    # Plugin implementation files are deliberately not sourced here.
    # --------------------------------------------------------------------------
    source "$manifest_path"


    if [[ "$STOLEUS_MANIFEST_BUILD_ACTIVE" == "true" ]]; then

        printf '%s\n' \
            "ERROR: Manifest did not call stoleus_plugin_end: $manifest_path" \
            >&2

        return 6
    fi


    if [[ "$STOLEUS_MANIFEST_BUILD_COMPLETED" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Manifest did not define a plugin: $manifest_path" >&2

        return 6
    fi


    if [[ "$STOLEUS_MANIFEST_PLUGIN_ID" != "$discovered_name" ]]; then

        printf '%s\n' \
            "ERROR: Manifest plugin ID '${STOLEUS_MANIFEST_PLUGIN_ID}' does not match directory '${discovered_name}'." \
            >&2

        return 6
    fi


    if [[ -z "$STOLEUS_MANIFEST_IMPLEMENTATION" ]]; then

        printf '%s\n' \
            "ERROR: Manifest '${manifest_path}' does not declare an implementation." \
            >&2

        return 6
    fi


    if [[ "$STOLEUS_MANIFEST_IMPLEMENTATION" == /* ]]; then
        implementation_path="$STOLEUS_MANIFEST_IMPLEMENTATION"
    else
        implementation_path="${plugin_path}/${STOLEUS_MANIFEST_IMPLEMENTATION}"
    fi


    stoleus_definition_register \
        "$STOLEUS_MANIFEST_PLUGIN_ID" \
        "$category" \
        "$STOLEUS_MANIFEST_DESCRIPTION" \
        "$plugin_path" \
        "$implementation_path" \
        "$STOLEUS_MANIFEST_DEPENDENCIES" \
        "$STOLEUS_MANIFEST_CAPABILITIES" \
        "$manifest_path" \
        "bash" \
        "$STOLEUS_MANIFEST_INSTALL_FUNCTION" \
        "$STOLEUS_MANIFEST_CONFIGURE_FUNCTION" \
        "$STOLEUS_MANIFEST_VERIFY_FUNCTION" \
        "$STOLEUS_MANIFEST_UPGRADE_FUNCTION" \
        "$STOLEUS_MANIFEST_REMOVE_FUNCTION" ||
        return $?


    return 0
}
