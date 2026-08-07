#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Generic Lifecycle Function Invocation Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

TEST_TEMP_ROOT="$(
    mktemp -d
)"

trap 'rm -rf -- "$TEST_TEMP_ROOT"' EXIT


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


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/example"


cat > "${TEST_TEMP_ROOT}/modules/example/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "example"

stoleus_plugin_description \
    "Example generic invocation plugin."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "install" \
    "example_install"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/example/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

STOLEUS_GENERIC_INVOCATION_LOAD_COUNT="$((\
${STOLEUS_GENERIC_INVOCATION_LOAD_COUNT:-0} + 1\
))"


example_install() {

    return 0
}


example_restore_configuration() {

    printf '%s\n' "$*" \
        >> "$STOLEUS_GENERIC_INVOCATION_LOG"

    return 0
}


example_fail_rollback() {

    return 19
}
IMPLEMENTATION


export STOLEUS_GENERIC_INVOCATION_LOG="${TEST_TEMP_ROOT}/invocation.log"

: > "$STOLEUS_GENERIC_INVOCATION_LOG"


source "${PROJECT_ROOT}/kernel/kernel.sh"


stoleus_kernel_initialize


# ==============================================================================
# Configure the test-specific discovery root.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()


stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset
stoleus_plugin_reset
stoleus_lifecycle_reset


stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


stoleus_kernel_bootstrap


example_index="$(
    stoleus_registry_get_index \
        "example"
)"


# ==============================================================================
# Arbitrary implementation function can be invoked.
# ==============================================================================

stoleus_lifecycle_invoke_function \
    "example" \
    "$example_index" \
    "example_restore_configuration" \
    "argument-one" \
    "argument-two"


assert_equals \
    "argument-one argument-two" \
    "$(cat "$STOLEUS_GENERIC_INVOCATION_LOG")" \
    "Generic lifecycle invocation did not forward arguments."


# ==============================================================================
# Implementation is loaded only once.
# ==============================================================================

stoleus_lifecycle_invoke_function \
    "example" \
    "$example_index" \
    "example_restore_configuration" \
    "second-call"


assert_equals \
    "1" \
    "${STOLEUS_GENERIC_INVOCATION_LOAD_COUNT:-0}" \
    "Plugin implementation should be loaded only once."


# ==============================================================================
# Function exit code is preserved.
# ==============================================================================

set +e

stoleus_lifecycle_invoke_function \
    "example" \
    "$example_index" \
    "example_fail_rollback"

failure_exit_code=$?

set -e


assert_equals \
    "19" \
    "$failure_exit_code" \
    "Generic lifecycle invocation should preserve function exit codes."


# ==============================================================================
# Registry identity mismatch is rejected.
# ==============================================================================

set +e

stoleus_lifecycle_invoke_function \
    "wrong-plugin" \
    "$example_index" \
    "example_restore_configuration" \
    >/dev/null 2>&1

identity_exit_code=$?

set -e


assert_equals \
    "8" \
    "$identity_exit_code" \
    "Plugin and Registry-index mismatch should return code 8."


# ==============================================================================
# Missing implementation functions are rejected.
# ==============================================================================

set +e

stoleus_lifecycle_invoke_function \
    "example" \
    "$example_index" \
    "example_missing_rollback" \
    >/dev/null 2>&1

missing_function_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_function_exit_code" \
    "Missing generic lifecycle function should return code 6."


# ==============================================================================
# Invalid metadata is rejected.
# ==============================================================================

set +e

stoleus_lifecycle_invoke_function \
    "example" \
    "$example_index" \
    "invalid-function()" \
    >/dev/null 2>&1

invalid_function_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_function_exit_code" \
    "Invalid generic function reference should return code 6."


set +e

stoleus_lifecycle_invoke_function \
    "example" \
    "not-an-index" \
    "example_restore_configuration" \
    >/dev/null 2>&1

invalid_index_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_index_exit_code" \
    "Invalid Registry index should return code 2."


printf '%s\n' \
    "PASS: Generic Lifecycle Function Invocation tests completed successfully."
