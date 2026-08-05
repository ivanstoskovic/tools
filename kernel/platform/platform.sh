#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Platform Detection
# ==============================================================================
#
# Purpose:
#     Detect platform characteristics and publish them into Runtime Context.
#
# Detected facts:
#
#     kernel
#     os-family
#     distribution
#     distribution-version
#     architecture
#     init-system
#     container
#     privilege
#     execution-mode
#
# Test overrides:
#
#     STOLEUS_PLATFORM_OS_RELEASE_PATH
#     STOLEUS_PLATFORM_UNAME_SYSTEM_OVERRIDE
#     STOLEUS_PLATFORM_UNAME_MACHINE_OVERRIDE
#     STOLEUS_PLATFORM_INIT_SYSTEM_OVERRIDE
#     STOLEUS_PLATFORM_CONTAINER_OVERRIDE
#     STOLEUS_PLATFORM_PRIVILEGE_OVERRIDE
#     STOLEUS_PLATFORM_EXECUTION_MODE_OVERRIDE
#
# Public API:
#
#     stoleus_platform_initialize
#     stoleus_platform_detect
#     stoleus_platform_apply_context
#     stoleus_platform_refresh
#     stoleus_platform_get
#     stoleus_platform_get_status
#     stoleus_platform_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_PLATFORM_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_PLATFORM_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Platform State
# ==============================================================================

declare -a STOLEUS_PLATFORM_KEYS=()
declare -a STOLEUS_PLATFORM_VALUES=()
declare -A STOLEUS_PLATFORM_INDEX_BY_KEY=()

STOLEUS_PLATFORM_DETECTED="false"
STOLEUS_PLATFORM_APPLIED="false"
STOLEUS_PLATFORM_DETECTION_GENERATION=0


# ==============================================================================
# stoleus_platform_reset
# ==============================================================================

stoleus_platform_reset() {

    STOLEUS_PLATFORM_KEYS=()
    STOLEUS_PLATFORM_VALUES=()
    STOLEUS_PLATFORM_INDEX_BY_KEY=()

    STOLEUS_PLATFORM_DETECTED="false"
    STOLEUS_PLATFORM_APPLIED="false"

    STOLEUS_PLATFORM_DETECTION_GENERATION="$((${STOLEUS_PLATFORM_DETECTION_GENERATION:-0} + 1))"


    return 0
}


# ==============================================================================
# stoleus_platform_store
# ==============================================================================
#
# Internal helper for one detected platform field.
# ==============================================================================

stoleus_platform_store() {

    local platform_key="${1:-}"
    local platform_value="${2:-}"

    local platform_index=0


    if [[ -z "$platform_key" || -z "$platform_value" ]]; then

        printf '%s\n' \
            "ERROR: Platform storage requires key and value." >&2

        return 2
    fi


    if [[ -n "${STOLEUS_PLATFORM_INDEX_BY_KEY[$platform_key]+stored}" ]]; then

        platform_index="${STOLEUS_PLATFORM_INDEX_BY_KEY[$platform_key]}"
        STOLEUS_PLATFORM_VALUES[$platform_index]="$platform_value"

        return 0
    fi


    platform_index="${#STOLEUS_PLATFORM_KEYS[@]}"

    STOLEUS_PLATFORM_KEYS+=("$platform_key")
    STOLEUS_PLATFORM_VALUES+=("$platform_value")
    STOLEUS_PLATFORM_INDEX_BY_KEY["$platform_key"]="$platform_index"


    return 0
}


# ==============================================================================
# stoleus_platform_get
# ==============================================================================

stoleus_platform_get() {

    local platform_key="${1:-}"
    local platform_index=""


    if [[ -z "$platform_key" ]]; then

        printf '%s\n' \
            "ERROR: Platform lookup requires a key." >&2

        return 2
    fi


    if [[ -z "${STOLEUS_PLATFORM_INDEX_BY_KEY[$platform_key]+stored}" ]]; then

        printf '%s\n' \
            "ERROR: Unknown detected platform key: ${platform_key}" >&2

        return 6
    fi


    platform_index="${STOLEUS_PLATFORM_INDEX_BY_KEY[$platform_key]}"

    printf '%s\n' \
        "${STOLEUS_PLATFORM_VALUES[$platform_index]}"

    return 0
}


# ==============================================================================
# stoleus_platform_read_os_release_field
# ==============================================================================

stoleus_platform_read_os_release_field() {

    local os_release_path="${1:-}"
    local requested_field="${2:-}"

    local line=""
    local field_name=""
    local field_value=""


    if [[ -z "$os_release_path" ||
          -z "$requested_field" ||
          ! -f "$os_release_path" ]]; then

        return 1
    fi


    while IFS= read -r line || [[ -n "$line" ]]; do

        [[ "$line" == \#* ]] && continue
        [[ "$line" != *=* ]] && continue


        field_name="${line%%=*}"
        field_value="${line#*=}"


        if [[ "$field_name" != "$requested_field" ]]; then
            continue
        fi


        if [[ "$field_value" == \"*\" &&
              "$field_value" == *\" ]]; then

            field_value="${field_value:1:${#field_value}-2}"
        fi


        if [[ "$field_value" == \'*\' &&
              "$field_value" == *\' ]]; then

            field_value="${field_value:1:${#field_value}-2}"
        fi


        printf '%s\n' "$field_value"

        return 0

    done < "$os_release_path"


    return 1
}


# ==============================================================================
# stoleus_platform_map_os_family
# ==============================================================================

stoleus_platform_map_os_family() {

    local distribution="${1:-}"
    local distribution_like="${2:-}"
    local kernel_name="${3:-}"

    local candidate=""


    if [[ "$kernel_name" == "darwin" ]]; then

        printf '%s\n' "darwin"

        return 0
    fi


    if [[ "$kernel_name" != "linux" ]]; then

        printf '%s\n' "$kernel_name"

        return 0
    fi


    for candidate in \
        "$distribution" \
        ${distribution_like// / }; do

        case "$candidate" in

            debian|ubuntu|linuxmint|pop|raspbian)

                printf '%s\n' "debian"

                return 0

                ;;


            rhel|fedora|centos|rocky|almalinux|ol)

                printf '%s\n' "redhat"

                return 0

                ;;


            arch|manjaro)

                printf '%s\n' "arch"

                return 0

                ;;


            alpine)

                printf '%s\n' "alpine"

                return 0

                ;;


            suse|opensuse|opensuse-leap|opensuse-tumbleweed|sles)

                printf '%s\n' "suse"

                return 0

                ;;
        esac
    done


    printf '%s\n' "linux"

    return 0
}


# ==============================================================================
# stoleus_platform_detect_init_system
# ==============================================================================

stoleus_platform_detect_init_system() {

    local override="${STOLEUS_PLATFORM_INIT_SYSTEM_OVERRIDE:-}"


    if [[ -n "$override" ]]; then

        printf '%s\n' "$override"

        return 0
    fi


    if [[ -d /run/systemd/system ]] ||
       command -v systemctl >/dev/null 2>&1; then

        printf '%s\n' "systemd"

        return 0
    fi


    if command -v rc-service >/dev/null 2>&1; then

        printf '%s\n' "openrc"

        return 0
    fi


    if command -v launchctl >/dev/null 2>&1; then

        printf '%s\n' "launchd"

        return 0
    fi


    if command -v service >/dev/null 2>&1; then

        printf '%s\n' "sysv"

        return 0
    fi


    printf '%s\n' "unknown"

    return 0
}


# ==============================================================================
# stoleus_platform_detect_container
# ==============================================================================

stoleus_platform_detect_container() {

    local override="${STOLEUS_PLATFORM_CONTAINER_OVERRIDE:-}"


    if [[ -n "$override" ]]; then

        printf '%s\n' "$override"

        return 0
    fi


    if [[ -f /.dockerenv ||
          -f /run/.containerenv ]]; then

        printf '%s\n' "true"

        return 0
    fi


    if [[ -r /proc/1/cgroup ]] &&
       grep -qE \
           '(docker|containerd|kubepods|podman|lxc)' \
           /proc/1/cgroup; then

        printf '%s\n' "true"

        return 0
    fi


    printf '%s\n' "false"

    return 0
}


# ==============================================================================
# stoleus_platform_detect_privilege
# ==============================================================================

stoleus_platform_detect_privilege() {

    local override="${STOLEUS_PLATFORM_PRIVILEGE_OVERRIDE:-}"


    if [[ -n "$override" ]]; then

        printf '%s\n' "$override"

        return 0
    fi


    if (( EUID == 0 )); then

        printf '%s\n' "root"
    else
        printf '%s\n' "standard"
    fi


    return 0
}


# ==============================================================================
# stoleus_platform_detect
# ==============================================================================

stoleus_platform_detect() {

    local os_release_path=""
    local kernel_name=""
    local architecture=""

    local distribution=""
    local distribution_like=""
    local distribution_version=""

    local os_family=""
    local init_system=""
    local container_state=""
    local privilege=""
    local execution_mode=""


    if [[ "${STOLEUS_PLATFORM_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Platform subsystem must be initialized before detection." \
            >&2

        return 6
    fi


    STOLEUS_PLATFORM_KEYS=()
    STOLEUS_PLATFORM_VALUES=()
    STOLEUS_PLATFORM_INDEX_BY_KEY=()


    os_release_path="${STOLEUS_PLATFORM_OS_RELEASE_PATH:-/etc/os-release}"

    kernel_name="${STOLEUS_PLATFORM_UNAME_SYSTEM_OVERRIDE:-}"

    if [[ -z "$kernel_name" ]]; then
        kernel_name="$(uname -s 2>/dev/null || printf '%s' unknown)"
    fi

    kernel_name="${kernel_name,,}"


    architecture="${STOLEUS_PLATFORM_UNAME_MACHINE_OVERRIDE:-}"

    if [[ -z "$architecture" ]]; then
        architecture="$(uname -m 2>/dev/null || printf '%s' unknown)"
    fi


    distribution="$(
        stoleus_platform_read_os_release_field \
            "$os_release_path" \
            "ID" ||
            true
    )"

    distribution_like="$(
        stoleus_platform_read_os_release_field \
            "$os_release_path" \
            "ID_LIKE" ||
            true
    )"

    distribution_version="$(
        stoleus_platform_read_os_release_field \
            "$os_release_path" \
            "VERSION_ID" ||
            true
    )"


    if [[ -z "$distribution" ]]; then

        case "$kernel_name" in

            darwin)
                distribution="macos"
                ;;

            *)
                distribution="$kernel_name"
                ;;
        esac
    fi


    if [[ -z "$distribution_version" ]]; then
        distribution_version="unknown"
    fi


    os_family="$(
        stoleus_platform_map_os_family \
            "$distribution" \
            "$distribution_like" \
            "$kernel_name"
    )" || return $?


    init_system="$(
        stoleus_platform_detect_init_system
    )" || return $?


    container_state="$(
        stoleus_platform_detect_container
    )" || return $?


    privilege="$(
        stoleus_platform_detect_privilege
    )" || return $?


    execution_mode="${STOLEUS_PLATFORM_EXECUTION_MODE_OVERRIDE:-local}"


    stoleus_platform_store \
        "kernel" \
        "$kernel_name" ||
        return $?


    stoleus_platform_store \
        "os-family" \
        "$os_family" ||
        return $?


    stoleus_platform_store \
        "distribution" \
        "$distribution" ||
        return $?


    stoleus_platform_store \
        "distribution-version" \
        "$distribution_version" ||
        return $?


    stoleus_platform_store \
        "architecture" \
        "$architecture" ||
        return $?


    stoleus_platform_store \
        "init-system" \
        "$init_system" ||
        return $?


    stoleus_platform_store \
        "container" \
        "$container_state" ||
        return $?


    stoleus_platform_store \
        "privilege" \
        "$privilege" ||
        return $?


    stoleus_platform_store \
        "execution-mode" \
        "$execution_mode" ||
        return $?


    STOLEUS_PLATFORM_DETECTED="true"
    STOLEUS_PLATFORM_APPLIED="false"

    STOLEUS_PLATFORM_DETECTION_GENERATION="$((${STOLEUS_PLATFORM_DETECTION_GENERATION:-0} + 1))"


    return 0
}


# ==============================================================================
# stoleus_platform_apply_context
# ==============================================================================
#
# Arguments:
#
#     optional $1 = mode
#
# Modes:
#
#     preserve    Set only context keys that do not already exist.
#                 This is the default and protects explicit user values.
#
#     overwrite   Replace existing context values with detected platform facts.
# ==============================================================================

stoleus_platform_apply_context() {

    local mode="${1:-preserve}"

    local platform_index=0
    local platform_key=""
    local platform_value=""


    if [[ "$mode" != "preserve" &&
          "$mode" != "overwrite" ]]; then

        printf '%s\n' \
            "ERROR: Unsupported platform context application mode: ${mode}" \
            >&2

        return 2
    fi


    if [[ "$STOLEUS_PLATFORM_DETECTED" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Platform must be detected before applying context." >&2

        return 6
    fi


    for platform_index in "${!STOLEUS_PLATFORM_KEYS[@]}"; do

        platform_key="${STOLEUS_PLATFORM_KEYS[$platform_index]}"
        platform_value="${STOLEUS_PLATFORM_VALUES[$platform_index]}"


        if [[ "$mode" == "preserve" ]] &&
           stoleus_context_contains "$platform_key"; then

            continue
        fi


        stoleus_context_set \
            "$platform_key" \
            "$platform_value" ||
            return $?
    done


    STOLEUS_PLATFORM_APPLIED="true"


    return 0
}


# ==============================================================================
# stoleus_platform_refresh
# ==============================================================================

stoleus_platform_refresh() {

    local mode="${1:-preserve}"


    stoleus_platform_detect || return $?
    stoleus_platform_apply_context "$mode" || return $?


    return 0
}


# ==============================================================================
# stoleus_platform_get_status
# ==============================================================================

stoleus_platform_get_status() {

    printf '%s\t%s\t%s\t%s\n' \
        "${STOLEUS_PLATFORM_INITIALIZED:-false}" \
        "${STOLEUS_PLATFORM_DETECTED:-false}" \
        "${STOLEUS_PLATFORM_APPLIED:-false}" \
        "${STOLEUS_PLATFORM_DETECTION_GENERATION:-0}"

    return 0
}


# ==============================================================================
# stoleus_platform_initialize
# ==============================================================================

stoleus_platform_initialize() {

    if [[ "${STOLEUS_PLATFORM_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_PLATFORM_KEYS=()
    STOLEUS_PLATFORM_VALUES=()
    STOLEUS_PLATFORM_INDEX_BY_KEY=()

    STOLEUS_PLATFORM_DETECTED="false"
    STOLEUS_PLATFORM_APPLIED="false"
    STOLEUS_PLATFORM_DETECTION_GENERATION=0


    STOLEUS_PLATFORM_INITIALIZED="true"

    return 0
}
