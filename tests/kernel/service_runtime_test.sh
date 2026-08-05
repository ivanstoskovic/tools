#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Invocation Runtime Tests
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


contract_root="${TEST_TEMP_ROOT}/contracts"
plugin_root="${TEST_TEMP_ROOT}/plugins"

mkdir -p \
    "${contract_root}/package-manager" \
    "${plugin_root}/apt-provider" \
    "${plugin_root}/chrony"


# ==============================================================================
# Contract manifest.
# ==============================================================================

cat > "${contract_root}/package-manager/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin "package-manager"

stoleus_contract_description \
    "Installs and inspects operating-system packages."

stoleus_contract_version "1.0.0"

stoleus_contract_operation \
    "install" \
    "Install one package."

stoleus_contract_operation \
    "exists" \
    "Determine whether one package is installed."

stoleus_contract_end
CONTRACT


# ==============================================================================
# Provider implementation.
# ==============================================================================

cat > "${plugin_root}/apt-provider/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

STOLEUS_TEST_APT_IMPLEMENTATION_LOADED="true"

apt_package_install() {

    local package_name="${1:-}"

    STOLEUS_TEST_LAST_INSTALLED_PACKAGE="$package_name"

    printf 'installed:%s\n' "$package_name"

    return 0
}


apt_package_exists() {

    local package_name="${1:-}"

    printf 'exists:%s\n' "$package_name"

    return 0
}


apt_provider_verify() {

    return 0
}
IMPLEMENTATION


printf '%s\n' \
    '#!/usr/bin/env bash' \
    > "${plugin_root}/apt-provider/manifest.sh"


printf '%s\n' \
    '#!/usr/bin/env bash' \
    > "${plugin_root}/chrony/implementation.sh"


printf '%s\n' \
    '#!/usr/bin/env bash' \
    > "${plugin_root}/chrony/manifest.sh"


# ==============================================================================
# Build Contract Registry.
# ==============================================================================

STOLEUS_CONTRACT_DEFINITION_ROOTS=()

stoleus_contract_definition_reset
stoleus_contract_registry_reset
stoleus_contract_registry_create_collection

stoleus_contract_definition_add_root \
    "$contract_root"

stoleus_contract_definition_build_all
stoleus_contract_registry_import_definitions


# ==============================================================================
# Build Plugin, Service, and Resolver state.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset
stoleus_service_resolver_reset
stoleus_service_runtime_reset
stoleus_lifecycle_reset


stoleus_definition_register \
    "apt-provider" \
    "providers" \
    "APT package-manager provider." \
    "${plugin_root}/apt-provider" \
    "${plugin_root}/apt-provider/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "apt_provider_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|100" \
    "package-manager|install|apt_package_install;package-manager|exists|apt_package_exists"


stoleus_definition_register \
    "chrony" \
    "modules" \
    "Chrony service consumer." \
    "${plugin_root}/chrony" \
    "${plugin_root}/chrony/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/chrony/manifest.sh" \
    "bash" \
    "" \
    "" \
    "chrony_verify" \
    "" \
    "" \
    "package-manager" \
    "" \
    ""


STOLEUS_DEFINITIONS_FROZEN="true"

stoleus_registry_import_definitions
stoleus_service_registry_import_plugins


# ==============================================================================
# Invoke a service operation.
# ==============================================================================

service_output_path="${TEST_TEMP_ROOT}/service-output.txt"


stoleus_service_call \
    "package-manager" \
    "install" \
    "chrony" \
    > "$service_output_path"


assert_equals \
    "installed:chrony" \
    "$(cat "$service_output_path")" \
    "Service operation output is incorrect."


if ! stoleus_service_resolver_is_resolved "package-manager"; then
    fail "Service call should cache the selected provider."
fi


if ! stoleus_lifecycle_is_plugin_loaded "apt-provider"; then
    fail "Service call should load the selected provider plugin."
fi


assert_equals \
    "true" \
    "${STOLEUS_TEST_APT_IMPLEMENTATION_LOADED:-false}" \
    "Provider implementation should be sourced in the current shell."


assert_equals \
    "chrony" \
    "${STOLEUS_TEST_LAST_INSTALLED_PACKAGE:-}" \
    "Service arguments were not forwarded to the provider function."


assert_equals \
    "apt-provider" \
    "$(stoleus_service_get_provider "package-manager")" \
    "Selected service provider is incorrect."


assert_equals \
    "apt_package_install" \
    "$(stoleus_service_get_operation \
        "package-manager" \
        "install")" \
    "Resolved service operation function is incorrect."


expected_last_call="$(
    printf '%s' \
        $'package-manager\tinstall\tapt-provider\tapt_package_install\t0'
)"


assert_equals \
    "$expected_last_call" \
    "$(stoleus_service_runtime_get_last_call)" \
    "Last service call metadata is incorrect."


# ==============================================================================
# Repeated calls reuse the same resolver and lifecycle state.
# ==============================================================================

initial_resolved_count="${#STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[@]}"
initial_loaded_count="${#STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS[@]}"


stoleus_service_call \
    "package-manager" \
    "exists" \
    "chrony" \
    > "${TEST_TEMP_ROOT}/exists-output.txt"


assert_equals \
    "exists:chrony" \
    "$(cat "${TEST_TEMP_ROOT}/exists-output.txt")" \
    "Second service operation output is incorrect."


assert_equals \
    "$initial_resolved_count" \
    "${#STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[@]}" \
    "Repeated service calls must not duplicate resolver cache entries."


assert_equals \
    "$initial_loaded_count" \
    "${#STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS[@]}" \
    "Repeated service calls must not load the provider more than once."


# ==============================================================================
# Unknown operations are rejected.
# ==============================================================================

set +e

stoleus_service_call \
    "package-manager" \
    "remove" \
    "chrony" \
    >/dev/null 2>&1

unknown_operation_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_operation_exit_code" \
    "Unknown service operation should return configuration code 6."


# ==============================================================================
# Missing bound function is detected after provider loading.
# ==============================================================================

provider_key="package-manager@apt-provider"
provider_index="$(
    stoleus_metadata_collection_get_index \
        "$STOLEUS_SERVICE_REGISTRY_COLLECTION_ID" \
        "$provider_key"
)"

binding_key="${STOLEUS_SERVICE_REGISTRY_COLLECTION_ID}|${provider_index}|operation-bindings"

original_bindings="${STOLEUS_METADATA_VALUES[$binding_key]}"

STOLEUS_METADATA_VALUES["$binding_key"]="install|missing_provider_function;exists|apt_package_exists"


set +e

stoleus_service_call \
    "package-manager" \
    "install" \
    "chrony" \
    >/dev/null 2>&1

missing_function_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_function_exit_code" \
    "Missing bound provider function should return code 6."


STOLEUS_METADATA_VALUES["$binding_key"]="$original_bindings"


printf '%s\n' \
    "PASS: Service Invocation Runtime tests completed successfully."
