#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Composition Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


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


# ==============================================================================
# Reset before initialization is safe.
# ==============================================================================

stoleus_composition_reset


assert_equals \
    "0" \
    "$(stoleus_composition_get_count)" \
    "Composition should be empty before initialization."


if stoleus_composition_is_initialized; then
    fail "Composition should not report initialized before kernel initialization."
fi


# ==============================================================================
# Kernel initialization initializes Composition.
# ==============================================================================

stoleus_kernel_initialize


assert_equals \
    "true" \
    "${STOLEUS_COMPOSITION_INITIALIZED:-false}" \
    "Composition should be initialized by the kernel."


if ! stoleus_composition_is_initialized; then
    fail "Composition initialization status is incorrect."
fi


assert_equals \
    "0" \
    "$(stoleus_composition_get_count)" \
    "Composition should initially contain no records."


# ==============================================================================
# Initialization is idempotent.
# ==============================================================================

stoleus_composition_initialize
stoleus_composition_initialize


assert_equals \
    "true" \
    "${STOLEUS_COMPOSITION_INITIALIZED:-false}" \
    "Repeated Composition initialization should remain successful."


# ==============================================================================
# Reset clears all Composition state and preserves initialization.
# ==============================================================================

STOLEUS_COMPOSITION_SUBJECT_TYPES+=("service")
STOLEUS_COMPOSITION_SUBJECT_IDS+=("example-service")
STOLEUS_COMPOSITION_PROVIDER_IDS+=("example-provider")
STOLEUS_COMPOSITION_CONTEXT_GENERATIONS+=("1")

STOLEUS_COMPOSITION_INDEX_BY_SUBJECT["service:example-service"]="0"


assert_equals \
    "1" \
    "$(stoleus_composition_get_count)" \
    "Composition fixture was not populated."


stoleus_composition_reset


assert_equals \
    "0" \
    "$(stoleus_composition_get_count)" \
    "Composition reset did not clear records."


if ! stoleus_composition_is_initialized; then
    fail "Composition reset should not deinitialize the subsystem."
fi


if (( ${#STOLEUS_COMPOSITION_INDEX_BY_SUBJECT[@]} != 0 )); then
    fail "Composition reset did not clear its lookup index."
fi



# ==============================================================================
# Composition records and provider cache.
# ==============================================================================

stoleus_composition_reset


stoleus_context_set \
    "composition-test-context" \
    "value"


composition_generation="$(
    stoleus_context_get_generation
)"


stoleus_composition_cache \
    "service" \
    "package-management" \
    "apt-provider"


assert_equals \
    "1" \
    "$(stoleus_composition_get_count)" \
    "Composition record was not cached."


assert_equals \
    "apt-provider" \
    "$(
        stoleus_composition_get_provider \
            "service" \
            "package-management"
    )" \
    "Composition provider lookup is incorrect."


assert_equals \
    "service"$'\t'"package-management"$'\t'"apt-provider"$'\t'"${composition_generation}"$'\t'"resolved" \
    "$(
        stoleus_composition_get \
            "service" \
            "package-management"
    )" \
    "Composition record is incorrect."


# Duplicate cache operation is idempotent.
stoleus_composition_cache \
    "service" \
    "package-management" \
    "apt-provider"


assert_equals \
    "1" \
    "$(stoleus_composition_get_count)" \
    "Duplicate Composition cache operation should be idempotent."


# Capability records use a separate subject namespace.
stoleus_composition_cache \
    "capability" \
    "package-management" \
    "apt-provider"


assert_equals \
    "2" \
    "$(stoleus_composition_get_count)" \
    "Service and Capability Composition subjects should remain distinct."


# Invalid subject types fail.
set +e

stoleus_composition_cache \
    "invalid" \
    "package-management" \
    "apt-provider" \
    >/dev/null 2>&1

invalid_subject_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_subject_exit_code" \
    "Invalid Composition subject type should return code 6."


# Unknown records fail deterministically.
set +e

stoleus_composition_get_provider \
    "service" \
    "unknown-service" \
    >/dev/null 2>&1

missing_record_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_record_exit_code" \
    "Unknown Composition record should return code 6."



# ==============================================================================
# Composition cache invalidates when Context generation changes.
# ==============================================================================

stoleus_composition_reset


stoleus_composition_cache \
    "service" \
    "context-sensitive-service" \
    "provider-a"


assert_equals \
    "1" \
    "$(stoleus_composition_get_count)" \
    "Context-sensitive Composition fixture was not cached."


composition_generation_before="$STOLEUS_COMPOSITION_CONTEXT_GENERATION"


stoleus_context_set \
    "composition-context-change" \
    "changed"


context_generation_after="$(
    stoleus_context_get_generation
)"


if [[ "$composition_generation_before" == "$context_generation_after" ]]; then
    fail "Context generation should change after Context mutation."
fi


# Read-only getters must not mutate Composition synchronization state.
stale_composition_generation="$STOLEUS_COMPOSITION_CONTEXT_GENERATION"

stoleus_composition_get_count \
    >/dev/null


assert_equals \
    "$stale_composition_generation" \
    "$STOLEUS_COMPOSITION_CONTEXT_GENERATION" \
    "Composition getter must not synchronize Context implicitly."


# Context synchronization is stateful and therefore executes directly in the
# current shell.
stoleus_composition_sync_context


assert_equals \
    "0" \
    "$(stoleus_composition_get_count)" \
    "Composition cache should be invalidated after Context synchronization."


assert_equals \
    "$context_generation_after" \
    "$STOLEUS_COMPOSITION_CONTEXT_GENERATION" \
    "Composition Context generation did not synchronize."


# Cache remains immediately usable after invalidation.
stoleus_composition_cache \
    "service" \
    "context-sensitive-service" \
    "provider-b"


assert_equals \
    "provider-b" \
    "$(
        stoleus_composition_get_provider \
            "service" \
            "context-sensitive-service"
    )" \
    "Composition cache was not reusable after Context invalidation."



# ==============================================================================
# Plugin Composition subjects are supported.
# ==============================================================================

assert_equals \
    "plugin:base-plugin" \
    "$(
        stoleus_composition_get_key \
            "plugin" \
            "base-plugin"
    )" \
    "Plugin Composition subject key is incorrect."


printf '%s\n' \
    "PASS: Service Composition tests completed successfully."
