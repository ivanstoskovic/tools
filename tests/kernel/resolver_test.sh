#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Resolver Subsystem Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"
source "${PROJECT_ROOT}/tests/kernel/helpers/registry_storage.sh"


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
    "${TEST_TEMP_ROOT}/modules/chrony" \
    "${TEST_TEMP_ROOT}/modules/docker" \
    "${TEST_TEMP_ROOT}/modules/server"


cat > "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "chrony"

stoleus_plugin_description \
    "Install and verify Chrony."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_capabilities \
    "package-manager" \
    "service-manager"

stoleus_plugin_lifecycle \
    "install" \
    "chrony_install"

stoleus_plugin_lifecycle \
    "verify" \
    "chrony_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/docker/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "docker"

stoleus_plugin_description \
    "Install and verify Docker."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony"

stoleus_plugin_capabilities \
    "package-manager" \
    "service-manager"

stoleus_plugin_lifecycle \
    "install" \
    "docker_install"

stoleus_plugin_lifecycle \
    "verify" \
    "docker_verify"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/server/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "server"

stoleus_plugin_description \
    "Configure a server baseline."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_dependencies \
    "chrony" \
    "docker"

stoleus_plugin_lifecycle \
    "configure" \
    "server_configure"

stoleus_plugin_end
MANIFEST


for plugin_id in chrony docker server; do

    cat > "${TEST_TEMP_ROOT}/modules/${plugin_id}/implementation.sh" <<IMPLEMENTATION
#!/usr/bin/env bash

${plugin_id}_install() {
    return 0
}

${plugin_id}_verify() {
    return 0
}

${plugin_id}_configure() {
    return 0
}
IMPLEMENTATION

done


# ==============================================================================
# Configure isolated discovery and build the Registry.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"

stoleus_discovery_scan
stoleus_definition_build_all
stoleus_registry_import_definitions


# ==============================================================================
# Resolve one plugin.
# ==============================================================================

assert_equals \
    $'chrony\t0\tmodules' \
    "$(stoleus_resolver_resolve "chrony")" \
    "Chrony resolution is incorrect."


assert_equals \
    "1" \
    "$(stoleus_resolver_resolve_index "docker")" \
    "Docker Registry index is incorrect."


# ==============================================================================
# Resolve direct dependencies.
# ==============================================================================

server_dependencies="$(
    stoleus_resolver_resolve_dependencies "server"
)"


expected_server_dependencies="$(
    printf '%s\n' \
        $'chrony\t0\tmodules' \
        $'docker\t1\tmodules'
)"


assert_equals \
    "$expected_server_dependencies" \
    "$server_dependencies" \
    "Server direct dependency resolution is incorrect."


# ==============================================================================
# Validate complete Registry references.
# ==============================================================================

stoleus_resolver_validate_registry


assert_equals \
    "true" \
    "${STOLEUS_RESOLVER_VALIDATED:-false}" \
    "Resolver should mark the Registry as validated."


# ==============================================================================
# Verify resolved-reference cache.
# ==============================================================================

assert_equals \
    "3" \
    "${#STOLEUS_RESOLVER_RESOLVED_IDS[@]}" \
    "Resolver should cache exactly three resolved plugins."


resolved_records="$(
    stoleus_resolver_get_resolved
)"


expected_resolved_records="$(
    printf '%s\n' \
        $'chrony\t0\tmodules' \
        $'docker\t1\tmodules' \
        $'server\t2\tmodules'
)"


assert_equals \
    "$expected_resolved_records" \
    "$resolved_records" \
    "Resolved-reference records are incorrect."


# ==============================================================================
# Verify idempotent resolution.
# ==============================================================================

stoleus_resolver_resolve "chrony" >/dev/null
stoleus_resolver_resolve "chrony" >/dev/null


assert_equals \
    "3" \
    "${#STOLEUS_RESOLVER_RESOLVED_IDS[@]}" \
    "Repeated resolution must not duplicate cached references."


# ==============================================================================
# Verify unknown plugin handling.
# ==============================================================================

set +e

stoleus_resolver_resolve \
    "unknown" \
    >/dev/null 2>&1

unknown_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_exit_code" \
    "Unknown plugin resolution should return code 6."


# ==============================================================================
# Verify direct self-dependency validation.
# ==============================================================================

original_server_dependencies="$(
    stoleus_registry_get_field         "server"         "dependencies"
)"

stoleus_test_registry_replace_field     "server"     "dependencies"     "server"


set +e

stoleus_resolver_validate_plugin \
    "server" \
    >/dev/null 2>&1

self_dependency_exit_code=$?

set -e


assert_equals \
    "8" \
    "$self_dependency_exit_code" \
    "Direct self-dependency should return conflict code 8."


stoleus_test_registry_replace_field     "server"     "dependencies"     "$original_server_dependencies"


# ==============================================================================
# Verify duplicate direct dependencies.
# ==============================================================================

stoleus_test_registry_replace_field     "server"     "dependencies"     "chrony,chrony"


set +e

stoleus_resolver_validate_plugin \
    "server" \
    >/dev/null 2>&1

duplicate_dependency_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_dependency_exit_code" \
    "Duplicate direct dependencies should return conflict code 8."


stoleus_test_registry_replace_field     "server"     "dependencies"     "$original_server_dependencies"


# ==============================================================================
# Verify Registry must be frozen.
# ==============================================================================

STOLEUS_METADATA_COLLECTION_FROZEN["$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"]="false"


set +e

stoleus_resolver_resolve \
    "chrony" \
    >/dev/null 2>&1

unfrozen_registry_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unfrozen_registry_exit_code" \
    "Resolution against an unfrozen Registry should return code 6."


STOLEUS_METADATA_COLLECTION_FROZEN["$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"]="true"


printf '%s\n' \
    "PASS: Resolver subsystem tests completed successfully."
