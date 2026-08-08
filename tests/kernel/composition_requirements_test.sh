#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Composition Direct Requirement Tests
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
    "${TEST_TEMP_ROOT}/modules/plugin-base" \
    "${TEST_TEMP_ROOT}/modules/provider-a" \
    "${TEST_TEMP_ROOT}/modules/empty-provider"


# ==============================================================================
# plugin-base
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/plugin-base/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "plugin-base"

stoleus_plugin_description \
    "Base dependency used by Composition tests."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "verify" \
    "plugin_base_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/plugin-base/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

plugin_base_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# provider-a
#
# Deliberately declares both required and provided service/capability metadata.
# Composition must return only dependencies/requirements.
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/provider-a/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "provider-a"

stoleus_plugin_description \
    "Provider containing Composition requirement fixtures."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "plugin-base"

stoleus_plugin_requires_services \
    "logging"

stoleus_plugin_requires_capabilities \
    "package-management"

stoleus_plugin_provides_capabilities \
    "provided-capability"

stoleus_plugin_provides_service \
    "provided-service" \
    "1.0.0" \
    "10"

stoleus_plugin_service_operation \
    "provided-service" \
    "status" \
    "provided_service_status"

stoleus_plugin_lifecycle \
    "verify" \
    "provider_a_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/provider-a/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

provider_a_verify() {
    return 0
}

provided_service_status() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# empty-provider
# ==============================================================================

cat > "${TEST_TEMP_ROOT}/modules/empty-provider/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "empty-provider"

stoleus_plugin_description \
    "Provider with no direct Composition requirements."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "verify" \
    "empty_provider_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/empty-provider/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

empty_provider_verify() {
    return 0
}
IMPLEMENTATION


# ==============================================================================
# Build the real Registry through the normal kernel pipeline.
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
# Direct typed requirements.
# ==============================================================================

requirements="$(
    stoleus_composition_list_provider_requirements \
        "provider-a"
)"


expected_requirements="$(
    printf '%s\n' \
        $'plugin\tplugin-base' \
        $'service\tlogging' \
        $'capability\tpackage-management'
)"


assert_equals \
    "$expected_requirements" \
    "$requirements" \
    "Composition direct provider requirements are incorrect."


# ==============================================================================
# Provided metadata must not become dependency edges.
# ==============================================================================

if [[ "$requirements" == *"provided-capability"* ]]; then
    fail "Provided capability must not appear as a Composition requirement."
fi


if [[ "$requirements" == *"provided-service"* ]]; then
    fail "Provided service must not appear as a Composition requirement."
fi


# ==============================================================================
# Provider with no requirements succeeds with no output.
# ==============================================================================

assert_equals \
    "" \
    "$(
        stoleus_composition_list_provider_requirements \
            "empty-provider"
    )" \
    "Provider without requirements should produce no Composition edges."


# ==============================================================================
# Unknown provider.
# ==============================================================================

if stoleus_composition_list_provider_requirements \
    "unknown-provider" \
    >/dev/null 2>&1; then

    unknown_provider_exit_code=0
else
    unknown_provider_exit_code=$?
fi


assert_equals \
    "6" \
    "$unknown_provider_exit_code" \
    "Unknown Composition provider should return code 6."


# ==============================================================================
# Invalid provider ID.
# ==============================================================================

if stoleus_composition_list_provider_requirements \
    "INVALID_PROVIDER" \
    >/dev/null 2>&1; then

    invalid_provider_exit_code=0
else
    invalid_provider_exit_code=$?
fi


assert_equals \
    "2" \
    "$invalid_provider_exit_code" \
    "Invalid Composition provider ID should return code 2."


printf '%s\n' \
    "PASS: Composition direct requirement tests completed successfully."
