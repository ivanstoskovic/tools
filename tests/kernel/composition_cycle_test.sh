#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Composition Cycle Tests
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

    if [[ -n "$TEST_TEMP_ROOT" &&
          -d "$TEST_TEMP_ROOT" ]]; then

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


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/provider-a" \
    "${TEST_TEMP_ROOT}/modules/provider-b" \
    "${TEST_TEMP_ROOT}/modules/plugin-c" \
    "${TEST_TEMP_ROOT}/modules/safe-provider" \
    "${TEST_TEMP_ROOT}/contracts/a" \
    "${TEST_TEMP_ROOT}/contracts/safe-service"


# ==============================================================================
# Contract: service a
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/contracts/a/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin \
    "a"

stoleus_contract_description \
    "Service A used for Composition cycle testing."

stoleus_contract_version \
    "1.0.0"

stoleus_contract_operation \
    "status" \
    "Return service A status."

stoleus_contract_end
CONTRACT


# ==============================================================================
# Contract: safe-service
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/contracts/safe-service/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin \
    "safe-service"

stoleus_contract_description \
    "Independent service used after cycle failure."

stoleus_contract_version \
    "1.0.0"

stoleus_contract_operation \
    "status" \
    "Return safe service status."

stoleus_contract_end
CONTRACT


# ==============================================================================
# provider-a
#
# service:a -> capability:b
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/provider-a/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "provider-a"

stoleus_plugin_description \
    "Service A provider."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_requires_capabilities \
    "b"

stoleus_plugin_provides_service \
    "a" \
    "1.0.0" \
    "100"

stoleus_plugin_service_operation \
    "a" \
    "status" \
    "provider_a_status"

stoleus_plugin_lifecycle \
    "verify" \
    "provider_a_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/provider-a/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

provider_a_status() {
    return 0
}

provider_a_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# provider-b
#
# capability:b -> plugin:c
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/provider-b/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "provider-b"

stoleus_plugin_description \
    "Capability B provider."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "plugin-c"

stoleus_plugin_provides_capabilities \
    "b"

stoleus_plugin_lifecycle \
    "verify" \
    "provider_b_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/provider-b/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

provider_b_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# plugin-c
#
# plugin:c -> service:a
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/plugin-c/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "plugin-c"

stoleus_plugin_description \
    "Plugin C closes the mixed-type Composition cycle."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_requires_services \
    "a"

stoleus_plugin_lifecycle \
    "verify" \
    "plugin_c_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/plugin-c/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

plugin_c_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# safe-provider
#
# Independent graph used after cycle failure.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/safe-provider/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "safe-provider"

stoleus_plugin_description \
    "Independent service provider."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_provides_service \
    "safe-service" \
    "1.0.0" \
    "100"

stoleus_plugin_service_operation \
    "safe-service" \
    "status" \
    "safe_service_status"

stoleus_plugin_lifecycle \
    "verify" \
    "safe_provider_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/safe-provider/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

safe_service_status() {
    return 0
}

safe_provider_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# Build Plugin Registry.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"

stoleus_discovery_scan
stoleus_definition_build_all
stoleus_registry_import_definitions


# ==============================================================================
# Build Contract Registry.
# ==============================================================================

STOLEUS_CONTRACT_DEFINITION_ROOTS=()

stoleus_contract_definition_reset
stoleus_contract_registry_reset
stoleus_contract_registry_create_collection

stoleus_contract_definition_add_root \
    "${TEST_TEMP_ROOT}/contracts"

stoleus_contract_definition_build_all
stoleus_contract_registry_import_definitions


# ==============================================================================
# Build Service / Capability state.
# ==============================================================================

stoleus_service_registry_reset
stoleus_service_resolver_reset
stoleus_capability_registry_reset
stoleus_capability_resolver_reset
stoleus_composition_reset


stoleus_service_registry_import_plugins
stoleus_capability_registry_import_plugins


# ==============================================================================
# Mixed-type cycle detection.
# ==============================================================================

if cycle_output="$(
    stoleus_composition_resolve_subject \
        "service" \
        "a" \
        2>&1
)"; then

    cycle_exit_code=0
else
    cycle_exit_code=$?
fi


assert_equals \
    "8" \
    "$cycle_exit_code" \
    "Composition cycle should return conflict code 8."


expected_cycle="service:a -> capability:b -> plugin:plugin-c -> service:a"


if [[ "$cycle_output" != *"$expected_cycle"* ]]; then

    printf 'FAIL: Composition cycle path is incorrect.\n' >&2
    printf 'Expected path: %s\n' "$expected_cycle" >&2
    printf 'Actual output: %s\n' "$cycle_output" >&2

    exit 1
fi


# ==============================================================================
# Failed traversal must leave active traversal state clean.
# ==============================================================================

assert_equals \
    "0" \
    "${#STOLEUS_COMPOSITION_VISITING[@]}" \
    "Cycle failure left Composition visiting state dirty."


assert_equals \
    "0" \
    "${#STOLEUS_COMPOSITION_TRAVERSAL_STACK[@]}" \
    "Cycle failure left Composition traversal stack dirty."


# ==============================================================================
# Failed cycle must not poison a later independent Composition.
# ==============================================================================

stoleus_composition_resolve_subject \
    "service" \
    "safe-service"


assert_equals \
    "safe-provider" \
    "$(
        stoleus_composition_get_provider \
            "service" \
            "safe-service"
    )" \
    "Composition could not recover after cycle failure."


assert_equals \
    "1" \
    "$(stoleus_composition_get_count)" \
    "Failed cycle should not leave partially resolved Composition records."


printf '%s\n' \
    "PASS: Composition cycle tests completed successfully."
