#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Contract Definition Tests
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
    "1.0.0"

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
# Configure isolated contract roots.
# ==============================================================================

STOLEUS_CONTRACT_DEFINITION_ROOTS=()

stoleus_contract_definition_reset

stoleus_contract_definition_add_root \
    "${TEST_TEMP_ROOT}/contracts"


# ==============================================================================
# Build ContractDefinitions.
# ==============================================================================

stoleus_contract_definition_build_all


assert_equals \
    "true" \
    "${STOLEUS_CONTRACT_DEFINITIONS_FROZEN:-false}" \
    "ContractDefinitions should be frozen after build."


assert_equals \
    "2" \
    "${#STOLEUS_CONTRACT_DEFINITION_IDS[@]}" \
    "Exactly two ContractDefinitions should be built."


assert_equals \
    "package-manager" \
    "${STOLEUS_CONTRACT_DEFINITION_IDS[0]}" \
    "Contract definitions should use lexical order."


assert_equals \
    "service-manager" \
    "${STOLEUS_CONTRACT_DEFINITION_IDS[1]}" \
    "Second ContractDefinition should be service-manager."


if ! stoleus_contract_definition_exists "package-manager"; then
    fail "Package-manager contract should exist."
fi


assert_equals \
    "0" \
    "$(stoleus_contract_definition_get_index "package-manager")" \
    "Package-manager contract index is incorrect."


assert_equals \
    "1.0.0" \
    "$(stoleus_contract_definition_get_field "package-manager" "version")" \
    "Package-manager version is incorrect."


assert_equals \
    "install,remove,exists" \
    "$(stoleus_contract_definition_get_field "package-manager" "operations")" \
    "Package-manager operations are incorrect."


expected_operations="$(
    printf '%s\n' \
        $'install\tInstall one package.' \
        $'remove\tRemove one package.' \
        $'exists\tDetermine whether one package is installed.'
)"


assert_equals \
    "$expected_operations" \
    "$(stoleus_contract_definition_list_operations "package-manager")" \
    "Package-manager operation listing is incorrect."


expected_contract_list="$(
    printf '%s\n' \
        $'package-manager\t1.0.0\tInstalls, removes, and inspects operating-system packages.' \
        $'service-manager\t1.0.0\tControls operating-system services.'
)"


assert_equals \
    "$expected_contract_list" \
    "$(stoleus_contract_definition_list)" \
    "ContractDefinition listing is incorrect."


# ==============================================================================
# Verify successful build is idempotent.
# ==============================================================================

stoleus_contract_definition_build_all


assert_equals \
    "2" \
    "${#STOLEUS_CONTRACT_DEFINITION_IDS[@]}" \
    "Repeated builds must not duplicate ContractDefinitions."


# ==============================================================================
# Verify roots cannot change after freeze.
# ==============================================================================

set +e

stoleus_contract_definition_add_root \
    "${TEST_TEMP_ROOT}/other-contracts" \
    >/dev/null 2>&1

frozen_root_exit_code=$?

set -e


assert_equals \
    "8" \
    "$frozen_root_exit_code" \
    "Adding a root after ContractDefinition freeze should return code 8."


# ==============================================================================
# Verify unknown contract handling.
# ==============================================================================

set +e

stoleus_contract_definition_get_field \
    "unknown" \
    "description" \
    >/dev/null 2>&1

unknown_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_exit_code" \
    "Unknown contract lookup should return code 6."


printf '%s\n' \
    "PASS: Contract Definition subsystem tests completed successfully."
