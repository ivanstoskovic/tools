#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Definition DSL Tests
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
stoleus_definition_reset
stoleus_manifest_bash_reset


# ==============================================================================
# Build Service DSL metadata.
# ==============================================================================

stoleus_plugin_begin \
    "apt-provider"

stoleus_plugin_description \
    "APT package-manager service provider."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_requires_services \
    "filesystem" \
    "remote-executor"

stoleus_plugin_provides_service \
    "package-manager" \
    "1.0.0" \
    "100"

stoleus_plugin_service_operation \
    "package-manager" \
    "install" \
    "apt_package_install"

stoleus_plugin_service_operation \
    "package-manager" \
    "remove" \
    "apt_package_remove"

stoleus_plugin_service_operation \
    "package-manager" \
    "exists" \
    "apt_package_exists"

stoleus_plugin_lifecycle \
    "verify" \
    "apt_provider_verify"

stoleus_plugin_end


assert_equals \
    "filesystem,remote-executor" \
    "$STOLEUS_MANIFEST_REQUIRED_SERVICES" \
    "Required service normalization is incorrect."


assert_equals \
    "package-manager|1.0.0|100" \
    "$STOLEUS_MANIFEST_PROVIDED_SERVICES" \
    "Provided service normalization is incorrect."


assert_equals \
    "package-manager|install|apt_package_install;package-manager|remove|apt_package_remove;package-manager|exists|apt_package_exists" \
    "$STOLEUS_MANIFEST_SERVICE_OPERATION_BINDINGS" \
    "Service operation normalization is incorrect."


# ==============================================================================
# Persist the metadata into a PluginDefinition.
# ==============================================================================

TEST_TEMP_ROOT="$(
    mktemp -d
)"

plugin_root="${TEST_TEMP_ROOT}/apt-provider"
implementation_path="${plugin_root}/implementation.sh"
manifest_path="${plugin_root}/manifest.sh"

mkdir -p "$plugin_root"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    > "$implementation_path"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    > "$manifest_path"


stoleus_definition_register \
    "apt-provider" \
    "providers" \
    "APT package-manager service provider." \
    "$plugin_root" \
    "$implementation_path" \
    "" \
    "" \
    "$manifest_path" \
    "bash" \
    "" \
    "" \
    "apt_provider_verify" \
    "" \
    "" \
    "$STOLEUS_MANIFEST_REQUIRED_SERVICES" \
    "$STOLEUS_MANIFEST_PROVIDED_SERVICES" \
    "$STOLEUS_MANIFEST_SERVICE_OPERATION_BINDINGS"


assert_equals \
    "filesystem,remote-executor" \
    "${STOLEUS_DEFINITION_REQUIRED_SERVICES[0]}" \
    "PluginDefinition required services are incorrect."


assert_equals \
    "package-manager|1.0.0|100" \
    "${STOLEUS_DEFINITION_PROVIDED_SERVICES[0]}" \
    "PluginDefinition provided services are incorrect."


assert_equals \
    "package-manager|install|apt_package_install;package-manager|remove|apt_package_remove;package-manager|exists|apt_package_exists" \
    "${STOLEUS_DEFINITION_SERVICE_OPERATION_BINDINGS[0]}" \
    "PluginDefinition service operation bindings are incorrect."


# ==============================================================================
# Duplicate required services are rejected.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "duplicate-required"


set +e

stoleus_plugin_requires_services \
    "filesystem" \
    "filesystem" \
    >/dev/null 2>&1

duplicate_required_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_required_exit_code" \
    "Duplicate required service should return conflict code 8."


# ==============================================================================
# Operations cannot bind to undeclared provided services.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "invalid-binding"


set +e

stoleus_plugin_service_operation \
    "package-manager" \
    "install" \
    "apt_install" \
    >/dev/null 2>&1

undeclared_service_exit_code=$?

set -e


assert_equals \
    "6" \
    "$undeclared_service_exit_code" \
    "Binding an undeclared provided service should return code 6."


# ==============================================================================
# Duplicate service-operation bindings are rejected.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "duplicate-binding"

stoleus_plugin_provides_service \
    "package-manager" \
    "1.0.0" \
    "10"

stoleus_plugin_service_operation \
    "package-manager" \
    "install" \
    "apt_install"


set +e

stoleus_plugin_service_operation \
    "package-manager" \
    "install" \
    "apt_install_again" \
    >/dev/null 2>&1

duplicate_binding_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_binding_exit_code" \
    "Duplicate service operation binding should return code 8."


# ==============================================================================
# Service priority and version validation.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "invalid-provider"


set +e

stoleus_plugin_provides_service \
    "package-manager" \
    "version-one" \
    "100" \
    >/dev/null 2>&1

invalid_version_exit_code=$?


stoleus_plugin_provides_service \
    "service-manager" \
    "1.0.0" \
    "high" \
    >/dev/null 2>&1

invalid_priority_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_version_exit_code" \
    "Invalid service version should return code 6."


assert_equals \
    "6" \
    "$invalid_priority_exit_code" \
    "Invalid service priority should return code 6."


printf '%s\n' \
    "PASS: Service Definition DSL tests completed successfully."
