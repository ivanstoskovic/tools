#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Provider Resolver Tests
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
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/chrony"


cat > "${TEST_TEMP_ROOT}/contracts/package-manager/contract.sh" <<'CONTRACT'
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


for plugin_id in \
    apt-provider \
    custom-apt-provider \
    chrony; do

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${TEST_TEMP_ROOT}/plugins/${plugin_id}/implementation.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${TEST_TEMP_ROOT}/plugins/${plugin_id}/manifest.sh"
done


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
# Build two providers and one consumer.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset
stoleus_service_resolver_reset


stoleus_definition_register \
    "apt-provider" \
    "providers" \
    "Standard APT provider." \
    "${TEST_TEMP_ROOT}/plugins/apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "apt_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|100" \
    "package-manager|install|apt_install;package-manager|exists|apt_exists"


stoleus_definition_register \
    "custom-apt-provider" \
    "providers" \
    "Higher-priority custom APT provider." \
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "custom_apt_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|500" \
    "package-manager|install|custom_apt_install;package-manager|exists|custom_apt_exists"


stoleus_definition_register \
    "chrony" \
    "modules" \
    "Chrony consumer." \
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
# Highest priority wins.
# ==============================================================================

expected_resolution="$(
    printf '%s' \
        $'package-manager\tcustom-apt-provider\t1.0.0\t500'
)"


resolution_output_path="${TEST_TEMP_ROOT}/package-manager-resolution.tsv"


# Run the mutating resolver in the current shell.
#
# Do not invoke it inside $(...), because command substitution executes in a
# subshell and would discard the resolver cache when that subshell exits.
stoleus_service_resolver_resolve \
    "package-manager" \
    > "$resolution_output_path"


actual_resolution="$(
    cat "$resolution_output_path"
)"


assert_equals \
    "$expected_resolution" \
    "$actual_resolution" \
    "Highest-priority service provider was not selected."


assert_equals \
    "custom-apt-provider" \
    "$(stoleus_service_resolver_get_provider_plugin "package-manager")" \
    "Resolved provider plugin is incorrect."


assert_equals \
    "custom_apt_install" \
    "$(stoleus_service_resolver_get_operation_binding \
        "package-manager" \
        "install")" \
    "Resolved install operation binding is incorrect."


if ! stoleus_service_resolver_is_resolved "package-manager"; then
    fail "Package-manager service should be cached as resolved."
fi


assert_equals \
    "1" \
    "${#STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[@]}" \
    "Repeated provider lookup must not duplicate cache entries."


# ==============================================================================
# Complete Registry requirement validation.
# ==============================================================================

stoleus_service_resolver_validate_registry


assert_equals \
    "true" \
    "${STOLEUS_SERVICE_RESOLVER_VALIDATED:-false}" \
    "Service requirements should be marked validated."


assert_equals \
    "$expected_resolution" \
    "$(stoleus_service_resolver_get_resolved)" \
    "Resolved provider listing is incorrect."


# ==============================================================================
# Highest-priority tie must fail.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset
stoleus_service_resolver_reset


stoleus_definition_register \
    "apt-provider" \
    "providers" \
    "APT provider." \
    "${TEST_TEMP_ROOT}/plugins/apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "apt_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|100" \
    "package-manager|install|apt_install;package-manager|exists|apt_exists"


stoleus_definition_register \
    "custom-apt-provider" \
    "providers" \
    "Tied APT provider." \
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider" \
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider/implementation.sh" \
    "" \
    "" \
    "${TEST_TEMP_ROOT}/plugins/custom-apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "custom_apt_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|100" \
    "package-manager|install|custom_apt_install;package-manager|exists|custom_apt_exists"


STOLEUS_DEFINITIONS_FROZEN="true"

stoleus_registry_import_definitions
stoleus_service_registry_import_plugins


set +e

stoleus_service_resolver_resolve \
    "package-manager" \
    >/dev/null 2>&1

tie_exit_code=$?

set -e


assert_equals \
    "8" \
    "$tie_exit_code" \
    "Highest-priority provider tie should return conflict code 8."


# ==============================================================================
# Missing provider must fail.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset
stoleus_service_resolver_reset


stoleus_definition_register \
    "chrony" \
    "modules" \
    "Chrony consumer without a provider." \
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


set +e

stoleus_service_resolver_validate_registry \
    >/dev/null 2>&1

missing_provider_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_provider_exit_code" \
    "Required service without a provider should return code 6."


printf '%s\n' \
    "PASS: Service Provider Resolver tests completed successfully."
