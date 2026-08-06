#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Registry Tests
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


mkdir -p \
    "${TEST_TEMP_ROOT}/contracts/package-manager" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/chrony"


cat > "${TEST_TEMP_ROOT}/contracts/package-manager/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin "package-manager"

stoleus_contract_description \
    "Installs, removes, and inspects operating-system packages."

stoleus_contract_version "1.0.0"

stoleus_contract_operation \
    "install" \
    "Install one package."

stoleus_contract_operation \
    "remove" \
    "Remove one package."

stoleus_contract_operation \
    "exists" \
    "Determine whether one package is installed."

stoleus_contract_end
CONTRACT


for plugin_id in apt-provider chrony; do

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${TEST_TEMP_ROOT}/plugins/${plugin_id}/implementation.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${TEST_TEMP_ROOT}/plugins/${plugin_id}/manifest.sh"
done


# ==============================================================================
# Build the Contract Registry.
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
# Build PluginDefinitions.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset


stoleus_definition_register \
    "apt-provider" \
    "providers" \
    "APT package-manager provider." \
    "${TEST_TEMP_ROOT}/plugins/apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "apt_provider_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|100" \
    "package-manager|install|apt_package_install;package-manager|remove|apt_package_remove;package-manager|exists|apt_package_exists"


stoleus_definition_register \
    "chrony" \
    "modules" \
    "Chrony time synchronization module." \
    "${TEST_TEMP_ROOT}/plugins/chrony" \
    "${TEST_TEMP_ROOT}/plugins/chrony/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/chrony/manifest.sh" \
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
# Validate imported provider metadata.
# ==============================================================================

if ! stoleus_service_registry_is_frozen; then
    fail "Service Registry should be frozen after import."
fi


assert_equals \
    "1" \
    "$(stoleus_service_registry_get_count)" \
    "Service Registry should contain exactly one provider."


if ! stoleus_service_registry_contains \
    "package-manager@apt-provider"; then

    fail "APT package-manager provider should exist."
fi


assert_equals \
    "apt-provider" \
    "$(stoleus_service_registry_get_provider \
        "package-manager" \
        "apt-provider")" \
    "Provider lookup is incorrect."


assert_equals \
    "100" \
    "$(stoleus_service_registry_get_field \
        "package-manager@apt-provider" \
        "priority")" \
    "Provider priority is incorrect."


assert_equals \
    "apt_package_install" \
    "$(stoleus_service_registry_get_operation_binding \
        "package-manager" \
        "apt-provider" \
        "install")" \
    "Install operation binding is incorrect."


expected_providers="$(
    printf '%s' \
        $'apt-provider\t1.0.0\t100'
)"


assert_equals \
    "$expected_providers" \
    "$(stoleus_service_registry_list_providers "package-manager")" \
    "Package-manager provider listing is incorrect."


expected_registry="$(
    printf '%s' \
        $'package-manager\tapt-provider\t1.0.0\t100'
)"


assert_equals \
    "$expected_registry" \
    "$(stoleus_service_registry_list)" \
    "Complete Service Registry listing is incorrect."


# ==============================================================================
# Verify missing contract operation bindings are rejected.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset


stoleus_definition_register \
    "incomplete-provider" \
    "providers" \
    "Incomplete provider." \
    "${TEST_TEMP_ROOT}/plugins/apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "incomplete_provider_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|10" \
    "package-manager|install|provider_install;package-manager|remove|provider_remove"


STOLEUS_DEFINITIONS_FROZEN="true"

stoleus_registry_import_definitions


set +e

stoleus_service_registry_import_plugins \
    >/dev/null 2>&1

missing_binding_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_binding_exit_code" \
    "Missing contract operation binding should return code 6."


printf '%s\n' \
    "PASS: Service Registry tests completed successfully."
