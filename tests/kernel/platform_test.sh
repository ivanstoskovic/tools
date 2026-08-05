#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Platform Detection Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


TEST_TEMP_ROOT=""


cleanup() {

    if [[ -n "$TEST_TEMP_ROOT" && -d "$TEST_TEMP_ROOT" ]]; then
        rm -rf "$TEST_TEMP_ROOT"
    fi
}


fail() {

    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}


assert_equals() {

    local expected="${1:-}"
    local actual="${2:-}"
    local message="${3:-Values are not equal.}"


    if [[ "$expected" != "$actual" ]]; then

        printf 'FAIL: %s\n' "$message" >&2
        printf 'Expected: %s\n' "$expected" >&2
        printf 'Actual:   %s\n' "$actual" >&2

        exit 1
    fi
}


trap cleanup EXIT


stoleus_kernel_initialize


TEST_TEMP_ROOT="$(
    mktemp -d
)"


os_release_path="${TEST_TEMP_ROOT}/os-release"


cat > "$os_release_path" <<'OS_RELEASE'
NAME="Ubuntu"
ID=ubuntu
ID_LIKE="debian"
VERSION_ID="26.04"
OS_RELEASE


export STOLEUS_PLATFORM_OS_RELEASE_PATH="$os_release_path"
export STOLEUS_PLATFORM_UNAME_SYSTEM_OVERRIDE="Linux"
export STOLEUS_PLATFORM_UNAME_MACHINE_OVERRIDE="x86_64"
export STOLEUS_PLATFORM_INIT_SYSTEM_OVERRIDE="systemd"
export STOLEUS_PLATFORM_CONTAINER_OVERRIDE="false"
export STOLEUS_PLATFORM_PRIVILEGE_OVERRIDE="standard"
export STOLEUS_PLATFORM_EXECUTION_MODE_OVERRIDE="local"


stoleus_context_reset
stoleus_platform_reset

stoleus_platform_detect


assert_equals \
    "linux" \
    "$(stoleus_platform_get "kernel")" \
    "Detected kernel is incorrect."


assert_equals \
    "debian" \
    "$(stoleus_platform_get "os-family")" \
    "Detected OS family is incorrect."


assert_equals \
    "ubuntu" \
    "$(stoleus_platform_get "distribution")" \
    "Detected distribution is incorrect."


assert_equals \
    "26.04" \
    "$(stoleus_platform_get "distribution-version")" \
    "Detected distribution version is incorrect."


assert_equals \
    "x86_64" \
    "$(stoleus_platform_get "architecture")" \
    "Detected architecture is incorrect."


assert_equals \
    "systemd" \
    "$(stoleus_platform_get "init-system")" \
    "Detected init system is incorrect."


assert_equals \
    "false" \
    "$(stoleus_platform_get "container")" \
    "Detected container state is incorrect."


assert_equals \
    "standard" \
    "$(stoleus_platform_get "privilege")" \
    "Detected privilege state is incorrect."


assert_equals \
    "local" \
    "$(stoleus_platform_get "execution-mode")" \
    "Detected execution mode is incorrect."


# ==============================================================================
# Apply detected platform fields to Runtime Context.
# ==============================================================================

stoleus_platform_apply_context


assert_equals \
    "debian" \
    "$(stoleus_context_get "os-family")" \
    "Detected OS family was not applied to Runtime Context."


assert_equals \
    "ubuntu" \
    "$(stoleus_context_get "distribution")" \
    "Detected distribution was not applied to Runtime Context."


assert_equals \
    "x86_64" \
    "$(stoleus_context_get "architecture")" \
    "Detected architecture was not applied to Runtime Context."


# ==============================================================================
# Preserve mode must protect explicit context overrides.
# ==============================================================================

stoleus_context_set \
    "architecture" \
    "arm64"


stoleus_platform_apply_context \
    "preserve"


assert_equals \
    "arm64" \
    "$(stoleus_context_get "architecture")" \
    "Preserve mode should retain an explicit context value."


# ==============================================================================
# Overwrite mode replaces context with detected facts.
# ==============================================================================

stoleus_platform_apply_context \
    "overwrite"


assert_equals \
    "x86_64" \
    "$(stoleus_context_get "architecture")" \
    "Overwrite mode should restore the detected architecture."


# ==============================================================================
# Refresh performs detection and context application.
# ==============================================================================

cat > "$os_release_path" <<'OS_RELEASE'
NAME="Fedora Linux"
ID=fedora
ID_LIKE="rhel"
VERSION_ID="43"
OS_RELEASE


stoleus_platform_refresh \
    "overwrite"


assert_equals \
    "redhat" \
    "$(stoleus_context_get "os-family")" \
    "Platform refresh should update the OS family."


assert_equals \
    "fedora" \
    "$(stoleus_context_get "distribution")" \
    "Platform refresh should update the distribution."


assert_equals \
    "43" \
    "$(stoleus_context_get "distribution-version")" \
    "Platform refresh should update the distribution version."


# ==============================================================================
# Platform status.
# ==============================================================================

status="$(
    stoleus_platform_get_status
)"


case "$status" in

    $'true\ttrue\ttrue\t'*)
        ;;

    *)
        fail "Platform status is incorrect: ${status}"
        ;;
esac


printf '%s\n' \
    "PASS: Platform Detection tests completed successfully."
