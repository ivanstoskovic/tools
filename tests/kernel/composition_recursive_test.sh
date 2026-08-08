#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Recursive Service Composition Tests
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
    "${TEST_TEMP_ROOT}/modules/base-plugin" \
    "${TEST_TEMP_ROOT}/modules/feature-provider" \
    "${TEST_TEMP_ROOT}/modules/child-provider" \
    "${TEST_TEMP_ROOT}/modules/root-provider" \
    "${TEST_TEMP_ROOT}/contracts/child-service" \
    "${TEST_TEMP_ROOT}/contracts/root-service"


# ==============================================================================
# base-plugin
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/base-plugin/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "base-plugin"

stoleus_plugin_description \
    "Base plugin for recursive Composition testing."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "verify" \
    "base_plugin_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/base-plugin/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

base_plugin_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# feature-provider
#
# Provides a capability and depends directly on base-plugin.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/feature-provider/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "feature-provider"

stoleus_plugin_description \
    "Capability provider used by recursive Composition."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "base-plugin"

stoleus_plugin_provides_capabilities \
    "feature-capability"

stoleus_plugin_lifecycle \
    "verify" \
    "feature_provider_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/feature-provider/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

feature_provider_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# child-provider
#
# Provides child-service.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/child-provider/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "child-provider"

stoleus_plugin_description \
    "Child service provider used by recursive Composition."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_provides_service \
    "child-service" \
    "1.0.0" \
    "100"

stoleus_plugin_service_operation \
    "child-service" \
    "status" \
    "child_service_status"

stoleus_plugin_lifecycle \
    "verify" \
    "child_provider_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/child-provider/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

child_service_status() {
    return 0
}

child_provider_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# root-provider
#
# Provides root-service and requires both:
#
#     child-service
#     feature-capability
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/root-provider/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "root-provider"

stoleus_plugin_description \
    "Root service provider used by recursive Composition."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_requires_services \
    "child-service"

stoleus_plugin_requires_capabilities \
    "feature-capability"

stoleus_plugin_provides_service \
    "root-service" \
    "1.0.0" \
    "100"

stoleus_plugin_service_operation \
    "root-service" \
    "status" \
    "root_service_status"

stoleus_plugin_lifecycle \
    "verify" \
    "root_provider_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/root-provider/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

root_service_status() {
    return 0
}

root_provider_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# Bootstrap isolated Registry state.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_contract_definition_reset
stoleus_contract_registry_reset
stoleus_contract_registry_create_collection
stoleus_service_registry_reset
stoleus_service_resolver_reset
stoleus_capability_registry_reset
stoleus_capability_resolver_reset
stoleus_composition_reset


stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


stoleus_discovery_scan
stoleus_definition_build_all
stoleus_registry_import_definitions


# ==============================================================================
# Define the two service contracts through the normal ContractDefinition
# discovery/build pipeline.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/contracts/child-service/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin \
    "child-service"

stoleus_contract_description \
    "Child service contract used by recursive Composition."

stoleus_contract_version \
    "1.0.0"

stoleus_contract_operation \
    "status" \
    "Return child service status."

stoleus_contract_end
CONTRACT


cat > "${TEST_TEMP_ROOT}/contracts/root-service/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin \
    "root-service"

stoleus_contract_description \
    "Root service contract used by recursive Composition."

stoleus_contract_version \
    "1.0.0"

stoleus_contract_operation \
    "status" \
    "Return root service status."

stoleus_contract_end
CONTRACT


stoleus_contract_definition_add_root \
    "${TEST_TEMP_ROOT}/contracts"

stoleus_contract_definition_build_all

stoleus_contract_registry_import_definitions

stoleus_service_registry_import_plugins
stoleus_capability_registry_import_plugins

# ==============================================================================
# Recursive Composition.
# ==============================================================================

stoleus_composition_resolve_subject \
    "service" \
    "root-service"


# ==============================================================================
# All typed subjects should have been composed exactly once.
# ==============================================================================

assert_equals \
    "4" \
    "$(stoleus_composition_get_count)" \
    "Recursive Composition should contain four typed subjects."


assert_equals \
    "root-provider" \
    "$(
        stoleus_composition_get_provider \
            "service" \
            "root-service"
    )" \
    "Root service provider is incorrect."


assert_equals \
    "child-provider" \
    "$(
        stoleus_composition_get_provider \
            "service" \
            "child-service"
    )" \
    "Child service provider is incorrect."


assert_equals \
    "feature-provider" \
    "$(
        stoleus_composition_get_provider \
            "capability" \
            "feature-capability"
    )" \
    "Capability provider is incorrect."


assert_equals \
    "base-plugin" \
    "$(
        stoleus_composition_get_provider \
            "plugin" \
            "base-plugin"
    )" \
    "Direct plugin dependency provider is incorrect."


# ==============================================================================
# Resolution state contains each typed subject exactly once.
# ==============================================================================

assert_equals \
    "true" \
    "${STOLEUS_COMPOSITION_RESOLVED["service:root-service"]:-false}" \
    "Root service was not marked resolved."


assert_equals \
    "true" \
    "${STOLEUS_COMPOSITION_RESOLVED["service:child-service"]:-false}" \
    "Child service was not marked resolved."


assert_equals \
    "true" \
    "${STOLEUS_COMPOSITION_RESOLVED["capability:feature-capability"]:-false}" \
    "Capability was not marked resolved."


assert_equals \
    "true" \
    "${STOLEUS_COMPOSITION_RESOLVED["plugin:base-plugin"]:-false}" \
    "Base plugin was not marked resolved."


# ==============================================================================
# Re-resolving the root is idempotent.
# ==============================================================================

stoleus_composition_resolve_subject \
    "service" \
    "root-service"


assert_equals \
    "4" \
    "$(stoleus_composition_get_count)" \
    "Repeated recursive Composition should not duplicate records."


# ==============================================================================
# Traversal state must be clean after successful resolution.
# ==============================================================================

assert_equals \
    "0" \
    "${#STOLEUS_COMPOSITION_VISITING[@]}" \
    "Composition visiting state was not cleared."


assert_equals \
    "0" \
    "${#STOLEUS_COMPOSITION_TRAVERSAL_STACK[@]}" \
    "Composition traversal stack was not cleared."



# ==============================================================================
# Deterministic dependency-first Composition order.
# ==============================================================================

expected_order="$(
    printf '%s\n' \
        $'service\tchild-service\tchild-provider' \
        $'plugin\tbase-plugin\tbase-plugin' \
        $'capability\tfeature-capability\tfeature-provider' \
        $'service\troot-service\troot-provider'
)"


assert_equals \
    "$expected_order" \
    "$(stoleus_composition_list_order)" \
    "Recursive Composition order is not dependency-first."



# ==============================================================================
# Composition diagnostics expose resolved graph.
# ==============================================================================

composition_list="$(
    stoleus_composition_list
)"


if [[ "$composition_list" != *$'service\tchild-service\tchild-provider'* ]]; then
    fail "Composition list is missing child-service."
fi


if [[ "$composition_list" != *$'plugin\tbase-plugin\tbase-plugin'* ]]; then
    fail "Composition list is missing base-plugin."
fi


if [[ "$composition_list" != *$'capability\tfeature-capability\tfeature-provider'* ]]; then
    fail "Composition list is missing feature-capability."
fi


if [[ "$composition_list" != *$'service\troot-service\troot-provider'* ]]; then
    fail "Composition list is missing root-service."
fi


# ==============================================================================
# Explain renders the typed dependency hierarchy.
# ==============================================================================

composition_explain="$(
    stoleus_composition_explain \
        "service" \
        "root-service"
)"


expected_explain="$(
    printf '%s\n' \
        'service:root-service' \
        '  provider: root-provider' \
        '  dependencies:' \
        '    service:child-service' \
        '      provider: child-provider' \
        '    capability:feature-capability' \
        '      provider: feature-provider' \
        '      dependencies:' \
        '        plugin:base-plugin' \
        '          provider: base-plugin'
)"


assert_equals \
    "$expected_explain" \
    "$composition_explain" \
    "Composition Explain hierarchy is incorrect."


# ==============================================================================
# Explain is read-only.
# ==============================================================================

composition_count_before_explain="$(
    stoleus_composition_get_count
)"

composition_generation_before_explain="$STOLEUS_COMPOSITION_CONTEXT_GENERATION"


stoleus_composition_explain \
    "service" \
    "root-service" \
    >/dev/null


assert_equals \
    "$composition_count_before_explain" \
    "$(stoleus_composition_get_count)" \
    "Composition Explain must not mutate cached records."


assert_equals \
    "$composition_generation_before_explain" \
    "$STOLEUS_COMPOSITION_CONTEXT_GENERATION" \
    "Composition Explain must not synchronize or mutate Context generation."


# ==============================================================================
# Explain rejects unresolved subjects rather than resolving implicitly.
# ==============================================================================

if stoleus_composition_explain \
    "service" \
    "unresolved-service" \
    >/dev/null 2>&1
then
    unresolved_explain_exit_code=0
else
    unresolved_explain_exit_code=$?
fi


assert_equals \
    "6" \
    "$unresolved_explain_exit_code" \
    "Composition Explain should reject unresolved subjects."


printf '%s\n' \
    "PASS: Recursive Service Composition tests completed successfully."
