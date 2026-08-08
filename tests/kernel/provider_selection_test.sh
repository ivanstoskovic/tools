#!/usr/bin/env bash

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


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


stoleus_kernel_initialize


assert_equals \
    "true" \
    "${STOLEUS_PROVIDER_SELECTION_INITIALIZED:-false}" \
    "Provider Selection should be initialized."


# Default metadata: one provider is selected.
assert_equals \
    "apt-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "package-management" \
            "" \
            "apt-provider"
    )" \
    "Default provider policy selection failed."


# Highest priority wins.
stoleus_provider_policy_registry_register \
    "capability" \
    "package-management" \
    "apt-provider" \
    "100" \
    "true"

stoleus_provider_policy_registry_register \
    "capability" \
    "package-management" \
    "dnf-provider" \
    "50" \
    "true"


assert_equals \
    "apt-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "package-management" \
            "" \
            "apt-provider" \
            "dnf-provider"
    )" \
    "Highest-priority provider was not selected."


# Disabled high-priority provider is ignored.
stoleus_provider_policy_registry_register \
    "capability" \
    "service-management" \
    "systemd-provider" \
    "1000" \
    "false"

stoleus_provider_policy_registry_register \
    "capability" \
    "service-management" \
    "openrc-provider" \
    "10" \
    "true"


assert_equals \
    "openrc-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "service-management" \
            "" \
            "systemd-provider" \
            "openrc-provider"
    )" \
    "Disabled provider should not be selected."


# Explicit enabled override wins over priority.
assert_equals \
    "dnf-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "package-management" \
            "dnf-provider" \
            "apt-provider" \
            "dnf-provider"
    )" \
    "Explicit enabled provider override was not honored."


# Explicit disabled override fails.
set +e

stoleus_provider_selection_select \
    "capability" \
    "service-management" \
    "systemd-provider" \
    "systemd-provider" \
    "openrc-provider" \
    >/dev/null 2>&1

disabled_override_exit_code=$?

set -e


assert_equals \
    "6" \
    "$disabled_override_exit_code" \
    "Disabled provider override should return code 6."


# Equal highest priorities conflict.
stoleus_provider_policy_registry_register \
    "capability" \
    "firewall-management" \
    "ufw-provider" \
    "100" \
    "true"

stoleus_provider_policy_registry_register \
    "capability" \
    "firewall-management" \
    "firewalld-provider" \
    "100" \
    "true"


set +e

stoleus_provider_selection_select \
    "capability" \
    "firewall-management" \
    "" \
    "ufw-provider" \
    "firewalld-provider" \
    >/dev/null 2>&1

tie_exit_code=$?

set -e


assert_equals \
    "8" \
    "$tie_exit_code" \
    "Highest-priority provider tie should return code 8."


# No enabled provider.
stoleus_provider_policy_registry_register \
    "capability" \
    "disabled-test" \
    "provider-a" \
    "10" \
    "false"

stoleus_provider_policy_registry_register \
    "capability" \
    "disabled-test" \
    "provider-b" \
    "20" \
    "false"


set +e

stoleus_provider_selection_select \
    "capability" \
    "disabled-test" \
    "" \
    "provider-a" \
    "provider-b" \
    >/dev/null 2>&1

no_enabled_exit_code=$?

set -e


assert_equals \
    "6" \
    "$no_enabled_exit_code" \
    "No enabled providers should return code 6."



# ==============================================================================
# Context conditions filter providers before priority selection.
# ==============================================================================

stoleus_context_set \
    "os-family" \
    "debian"


stoleus_provider_policy_registry_register \
    "capability" \
    "conditional-package-management" \
    "apt-provider" \
    "50" \
    "true" \
    "os-family=debian"


stoleus_provider_policy_registry_register \
    "capability" \
    "conditional-package-management" \
    "dnf-provider" \
    "1000" \
    "true" \
    "os-family=redhat"


assert_equals \
    "apt-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "conditional-package-management" \
            "" \
            "apt-provider" \
            "dnf-provider"
    )" \
    "Context-compatible provider should win before priority comparison."


# ==============================================================================
# Multiple conditions use logical AND.
# ==============================================================================

stoleus_context_set \
    "distribution" \
    "ubuntu"


stoleus_context_set \
    "architecture" \
    "x86_64"


stoleus_provider_policy_registry_register \
    "capability" \
    "multi-condition-test" \
    "matching-provider" \
    "10" \
    "true" \
    "os-family=debian;distribution=ubuntu;architecture=x86_64"


stoleus_provider_policy_registry_register \
    "capability" \
    "multi-condition-test" \
    "wrong-architecture-provider" \
    "1000" \
    "true" \
    "os-family=debian;distribution=ubuntu;architecture=arm64"


assert_equals \
    "matching-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "multi-condition-test" \
            "" \
            "matching-provider" \
            "wrong-architecture-provider"
    )" \
    "Provider conditions should use logical AND semantics."


# ==============================================================================
# Context-incompatible override is rejected.
# ==============================================================================

set +e

stoleus_provider_selection_select \
    "capability" \
    "conditional-package-management" \
    "dnf-provider" \
    "apt-provider" \
    "dnf-provider" \
    >/dev/null 2>&1

incompatible_override_exit_code=$?

set -e


assert_equals \
    "6" \
    "$incompatible_override_exit_code" \
    "Context-incompatible override should return code 6."


# ==============================================================================
# No context-compatible provider.
# ==============================================================================

stoleus_provider_policy_registry_register \
    "capability" \
    "no-context-match" \
    "provider-a" \
    "100" \
    "true" \
    "os-family=redhat"


stoleus_provider_policy_registry_register \
    "capability" \
    "no-context-match" \
    "provider-b" \
    "50" \
    "true" \
    "distribution=debian"


set +e

stoleus_provider_selection_select \
    "capability" \
    "no-context-match" \
    "" \
    "provider-a" \
    "provider-b" \
    >/dev/null 2>&1

no_context_match_exit_code=$?

set -e


assert_equals \
    "6" \
    "$no_context_match_exit_code" \
    "No context-compatible provider should return code 6."


# ==============================================================================
# Provider without policy metadata remains context-independent.
# ==============================================================================

assert_equals \
    "unconfigured-provider" \
    "$(
        stoleus_provider_selection_select \
            "capability" \
            "unconfigured-condition-test" \
            "" \
            "unconfigured-provider"
    )" \
    "Provider without policy metadata should remain context-independent."



# ==============================================================================
# Provider Selection records structured decision trace.
# ==============================================================================

stoleus_provider_policy_registry_reset


stoleus_context_set \
    "os-family" \
    "debian"


stoleus_provider_policy_registry_register \
    "capability" \
    "trace-test" \
    "apt-provider" \
    "100" \
    "true" \
    "os-family=debian"


stoleus_provider_policy_registry_register \
    "capability" \
    "trace-test" \
    "dnf-provider" \
    "1000" \
    "true" \
    "os-family=redhat"


stoleus_provider_policy_registry_register \
    "capability" \
    "trace-test" \
    "disabled-provider" \
    "2000" \
    "false"


stoleus_provider_selection_select \
    "capability" \
    "trace-test" \
    "" \
    "apt-provider" \
    "dnf-provider" \
    "disabled-provider" \
    >/dev/null


assert_equals \
    "apt-provider" \
    "$(stoleus_provider_selection_get_selected)" \
    "Trace scenario selected the wrong provider."


assert_equals \
    "3" \
    "$(stoleus_provider_trace_get_count)" \
    "Provider Selection should record one trace row per candidate."


assert_equals \
    "selected" \
    "$(stoleus_provider_trace_get_field \
        "capability:trace-test@apt-provider#0" \
        "decision")" \
    "Selected provider trace decision is incorrect."


assert_equals \
    "rejected-context" \
    "$(stoleus_provider_trace_get_field \
        "capability:trace-test@dnf-provider#1" \
        "decision")" \
    "Context-rejected provider trace decision is incorrect."


assert_equals \
    "rejected-disabled" \
    "$(stoleus_provider_trace_get_field \
        "capability:trace-test@disabled-provider#2" \
        "decision")" \
    "Disabled provider trace decision is incorrect."


assert_equals \
    "matched" \
    "$(stoleus_provider_trace_get_field \
        "capability:trace-test@apt-provider#0" \
        "condition-result")" \
    "Selected provider condition result is incorrect."


assert_equals \
    "rejected" \
    "$(stoleus_provider_trace_get_field \
        "capability:trace-test@dnf-provider#1" \
        "condition-result")" \
    "Rejected provider condition result is incorrect."


# ==============================================================================
# Explicit override is identifiable in the trace.
# ==============================================================================

stoleus_provider_policy_registry_reset


stoleus_provider_policy_registry_register \
    "capability" \
    "trace-override-test" \
    "provider-a" \
    "100" \
    "true"


stoleus_provider_policy_registry_register \
    "capability" \
    "trace-override-test" \
    "provider-b" \
    "10" \
    "true"


stoleus_provider_selection_select \
    "capability" \
    "trace-override-test" \
    "provider-b" \
    "provider-a" \
    "provider-b" \
    >/dev/null


assert_equals \
    "provider-b" \
    "$(stoleus_provider_selection_get_selected)" \
    "Trace override scenario selected the wrong provider."


assert_equals \
    "selected-override" \
    "$(stoleus_provider_trace_get_field \
        "capability:trace-override-test@provider-b#1" \
        "decision")" \
    "Explicit override trace decision is incorrect."


printf '%s\n' \
    "PASS: Generic Provider Selection tests completed successfully."
