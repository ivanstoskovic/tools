#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Contract Registry Tests
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
    "${TEST_TEMP_ROOT}/contracts/service-manager"


cat > "${TEST_TEMP_ROOT}/contracts/package-manager/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin "package-manager"

stoleus_contract_description \
    "Installs, removes, and inspects operating-system packages."

stoleus_contract_version \
    "1.0.0"

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


cat > "${TEST_TEMP_ROOT}/contracts/service-manager/contract.sh" <<'CONTRACT'
#!/usr/bin/env bash

stoleus_contract_begin "service-manager"

stoleus_contract_description \
    "Controls operating-system services."

stoleus_contract_version \
    "1.1.0"

stoleus_contract_operation \
    "enable" \
    "Enable one service."

stoleus_contract_operation \
    "start" \
    "Start one service."

stoleus_contract_operation \
    "is-active" \
    "Determine whether one service is active."

stoleus_contract_end
CONTRACT


# ==============================================================================
# Configure an isolated ContractDefinition root.
# ==============================================================================

STOLEUS_CONTRACT_DEFINITION_ROOTS=()

stoleus_contract_definition_reset
stoleus_contract_registry_reset
stoleus_contract_registry_create_collection

stoleus_contract_definition_add_root \
    "${TEST_TEMP_ROOT}/contracts"


# ==============================================================================
# Definition -> Contract Registry.
# ==============================================================================

stoleus_contract_definition_build_all
stoleus_contract_registry_import_definitions


assert_equals \
    "true" \
    "${STOLEUS_CONTRACT_REGISTRY_READY:-false}" \
    "Contract Registry should be ready after import."


if ! stoleus_contract_registry_is_frozen; then
    fail "Contract Registry should be frozen after import."
fi


assert_equals \
    "2" \
    "$(stoleus_contract_registry_get_count)" \
    "Contract Registry should contain two contracts."


if ! stoleus_contract_registry_contains "package-manager"; then
    fail "Contract Registry should contain package-manager."
fi


if ! stoleus_contract_registry_contains "service-manager"; then
    fail "Contract Registry should contain service-manager."
fi


assert_equals \
    "0" \
    "$(stoleus_contract_registry_get_index "package-manager")" \
    "Package-manager Contract Registry index is incorrect."


assert_equals \
    "1" \
    "$(stoleus_contract_registry_get_index "service-manager")" \
    "Service-manager Contract Registry index is incorrect."


assert_equals \
    "1.0.0" \
    "$(stoleus_contract_registry_get_field \
        "package-manager" \
        "version")" \
    "Package-manager version lookup failed."


assert_equals \
    "Installs, removes, and inspects operating-system packages." \
    "$(stoleus_contract_registry_get_field \
        "package-manager" \
        "description")" \
    "Package-manager description lookup failed."


assert_equals \
    "install,remove,exists" \
    "$(stoleus_contract_registry_get_field \
        "package-manager" \
        "operations")" \
    "Package-manager operations lookup failed."


# ==============================================================================
# Contract-specific operation projection.
# ==============================================================================

expected_package_operations="$(
    printf '%s\n' \
        $'install\tInstall one package.' \
        $'remove\tRemove one package.' \
        $'exists\tDetermine whether one package is installed.'
)"


assert_equals \
    "$expected_package_operations" \
    "$(stoleus_contract_registry_list_operations "package-manager")" \
    "Package-manager operation listing is incorrect."


# ==============================================================================
# Contract Registry listing.
# ==============================================================================

expected_contract_list="$(
    printf '%s\n' \
        $'package-manager\t1.0.0\tInstalls, removes, and inspects operating-system packages.' \
        $'service-manager\t1.1.0\tControls operating-system services.'
)"


assert_equals \
    "$expected_contract_list" \
    "$(stoleus_contract_registry_list)" \
    "Contract Registry listing is incorrect."


# ==============================================================================
# Generic collection state must match the adapter.
# ==============================================================================

assert_equals \
    "2" \
    "$(stoleus_metadata_collection_get_count "contracts")" \
    "Generic contracts collection count is incorrect."


assert_equals \
    "1.1.0" \
    "$(stoleus_metadata_collection_get_field \
        "contracts" \
        "service-manager" \
        "version")" \
    "Contract Registry should use generic metadata storage."


# ==============================================================================
# Successful import is idempotent.
# ==============================================================================

stoleus_contract_registry_import_definitions


assert_equals \
    "2" \
    "$(stoleus_contract_registry_get_count)" \
    "Repeated Contract Registry import must not duplicate rows."


# ==============================================================================
# Frozen Registry rejects mutation.
# ==============================================================================

set +e

stoleus_contract_registry_append_definition \
    "0" \
    >/dev/null 2>&1

frozen_append_exit_code=$?

set -e


assert_equals \
    "8" \
    "$frozen_append_exit_code" \
    "Appending after Contract Registry freeze should return code 8."


# ==============================================================================
# Unknown contract and field handling.
# ==============================================================================

set +e

stoleus_contract_registry_get_field \
    "unknown" \
    "description" \
    >/dev/null 2>&1

unknown_contract_exit_code=$?


stoleus_contract_registry_get_field \
    "package-manager" \
    "unknown-field" \
    >/dev/null 2>&1

unknown_field_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_contract_exit_code" \
    "Unknown Contract Registry ID should return code 6."


assert_equals \
    "2" \
    "$unknown_field_exit_code" \
    "Unknown Contract Registry field should return code 2."


printf '%s\n' \
    "PASS: Contract Registry tests completed successfully."
