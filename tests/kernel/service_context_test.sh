#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Context-Aware Service Resolution Tests
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
    "${plugin_root}/dnf-provider" \
    "${plugin_root}/generic-provider" \
    "${plugin_root}/consumer"


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


for plugin_id in \
    apt-provider \
    dnf-provider \
    generic-provider \
    consumer; do

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${plugin_root}/${plugin_id}/implementation.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        > "${plugin_root}/${plugin_id}/manifest.sh"
done


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
# Build providers and consumer.
# ==============================================================================

stoleus_definition_reset
stoleus_registry_reset
stoleus_service_registry_reset
stoleus_service_resolver_reset
stoleus_context_reset


stoleus_definition_register \
    "apt-provider" \
    "providers" \
    "Debian APT provider." \
    "${plugin_root}/apt-provider" \
    "${plugin_root}/apt-provider/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/apt-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "apt_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|100" \
    "package-manager|install|apt_install;package-manager|exists|apt_exists" \
    "package-manager|os-family|debian"


stoleus_definition_register \
    "dnf-provider" \
    "providers" \
    "Red Hat DNF provider." \
    "${plugin_root}/dnf-provider" \
    "${plugin_root}/dnf-provider/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/dnf-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "dnf_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|500" \
    "package-manager|install|dnf_install;package-manager|exists|dnf_exists" \
    "package-manager|os-family|redhat"


stoleus_definition_register \
    "generic-provider" \
    "providers" \
    "Context-independent fallback provider." \
    "${plugin_root}/generic-provider" \
    "${plugin_root}/generic-provider/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/generic-provider/manifest.sh" \
    "bash" \
    "" \
    "" \
    "generic_verify" \
    "" \
    "" \
    "" \
    "package-manager|1.0.0|10" \
    "package-manager|install|generic_install;package-manager|exists|generic_exists" \
    ""


stoleus_definition_register \
    "consumer" \
    "modules" \
    "Package-manager consumer." \
    "${plugin_root}/consumer" \
    "${plugin_root}/consumer/implementation.sh" \
    "" \
    "" \
    "${plugin_root}/consumer/manifest.sh" \
    "bash" \
    "" \
    "" \
    "consumer_verify" \
    "" \
    "" \
    "package-manager" \
    "" \
    "" \
    ""


STOLEUS_DEFINITIONS_FROZEN="true"

stoleus_registry_import_definitions
stoleus_service_registry_import_plugins


# ==============================================================================
# Debian context selects APT despite DNF having a higher global priority.
# ==============================================================================

stoleus_context_set \
    "os-family" \
    "debian"


debian_output="${TEST_TEMP_ROOT}/debian-resolution.tsv"

stoleus_service_resolver_resolve \
    "package-manager" \
    > "$debian_output"


assert_equals \
    $'package-manager\tapt-provider\t1.0.0\t100' \
    "$(cat "$debian_output")" \
    "Debian context should select the APT provider."


assert_equals \
    "apt-provider" \
    "$(stoleus_service_resolver_get_provider_plugin "package-manager")" \
    "Cached Debian provider is incorrect."


# ==============================================================================
# Context mutation invalidates the existing resolver cache.
# ==============================================================================

stoleus_context_set \
    "os-family" \
    "redhat"


redhat_output="${TEST_TEMP_ROOT}/redhat-resolution.tsv"

stoleus_service_resolver_resolve \
    "package-manager" \
    > "$redhat_output"


assert_equals \
    $'package-manager\tdnf-provider\t1.0.0\t500' \
    "$(cat "$redhat_output")" \
    "Red Hat context should select the DNF provider."


assert_equals \
    "1" \
    "${#STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[@]}" \
    "Context invalidation should rebuild, not duplicate, resolver cache."


# ==============================================================================
# An incompatible override is rejected.
# ==============================================================================

stoleus_context_set_provider_override \
    "package-manager" \
    "apt-provider"


set +e

stoleus_service_resolver_resolve \
    "package-manager" \
    >/dev/null 2>&1

incompatible_override_exit_code=$?

set -e


assert_equals \
    "6" \
    "$incompatible_override_exit_code" \
    "Context-incompatible provider override should return code 6."


# ==============================================================================
# A compatible context-independent override wins over priority.
# ==============================================================================

stoleus_context_set_provider_override \
    "package-manager" \
    "generic-provider"


override_output="${TEST_TEMP_ROOT}/override-resolution.tsv"

stoleus_service_resolver_resolve \
    "package-manager" \
    > "$override_output"


assert_equals \
    $'package-manager\tgeneric-provider\t1.0.0\t10' \
    "$(cat "$override_output")" \
    "Explicit compatible provider override was not honored."


assert_equals \
    "generic-provider" \
    "$(stoleus_service_resolver_get_provider_plugin "package-manager")" \
    "Explicit provider override was not cached."


# ==============================================================================
# Clearing the override restores context-and-priority selection.
# ==============================================================================

stoleus_context_clear_provider_override \
    "package-manager"


restored_output="${TEST_TEMP_ROOT}/restored-resolution.tsv"

stoleus_service_resolver_resolve \
    "package-manager" \
    > "$restored_output"


assert_equals \
    $'package-manager\tdnf-provider\t1.0.0\t500' \
    "$(cat "$restored_output")" \
    "Clearing override should restore DNF selection for Red Hat context."


# ==============================================================================
# Context state is queryable.
# ==============================================================================

assert_equals \
    "redhat" \
    "$(stoleus_context_get "os-family")" \
    "Runtime context lookup is incorrect."


if (( $(stoleus_context_get_generation) <= 0 )); then
    fail "Context generation should increase after mutations."
fi


printf '%s\n' \
    "PASS: Context-aware Service Resolution tests completed successfully."
