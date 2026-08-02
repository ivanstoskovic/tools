#!/usr/bin/env bash

set -Eeuo pipefail


# ==============================================================================
# Registered Secrets
# ==============================================================================
#
# Sensitive values registered here are automatically removed from messages
# passing through the logging system.
#
# Secrets exist only in memory for the lifetime of the current Stoleus process.
#
# This array is private to the framework and should be accessed only through:
#
#     register_secret()
#     unregister_secret()
#     clear_registered_secrets()
#     redact_text()
# ==============================================================================
declare -a STOLEUS_REGISTERED_SECRETS=()


# ==============================================================================
# redact_secret
# ==============================================================================
#
# Purpose:
#     Return a partially hidden representation of a sensitive value.
#
# Usage:
#
#     redact_secret "abcdefghijk"
#
# Output:
#
#     ab*******jk
#
# This helper is intended for explicitly displaying a safe representation.
# It does not register or store the supplied value.
# ==============================================================================
redact_secret() {

    local secret="${1-}"
    local secret_length
    local prefix
    local suffix


    secret_length="${#secret}"


    if (( secret_length == 0 )); then

        printf '<empty>\n'

        return 0
    fi


    if (( secret_length <= 4 )); then

        printf '****\n'

        return 0
    fi


    prefix="${secret:0:2}"
    suffix="${secret: -2}"


    printf '%s*******%s\n' \
        "$prefix" \
        "$suffix"

    return 0
}


# ==============================================================================
# escape_shell_pattern
# ==============================================================================
#
# Purpose:
#     Internal helper used by redact_text().
#
#     Escape Bash pattern characters so secrets are treated as literal text
#     during string replacement.
#
# This function is intended for internal use only.
# ==============================================================================
escape_shell_pattern() {

    local value="${1-}"


    value="${value//\\/\\\\}"
    value="${value//\*/\\*}"
    value="${value//\?/\\?}"
    value="${value//\[/\\[}"
    value="${value//\]/\\]}"


    printf '%s\n' "$value"

    return 0
}


# ==============================================================================
# register_secret
# ==============================================================================
#
# Purpose:
#     Register a sensitive value for automatic log redaction.
#
# Usage:
#
#     register_secret "$registration_token"
#
# Behavior:
#
#     - empty values are rejected;
#     - duplicate values are ignored;
#     - the value is stored only in process memory;
#     - the secret itself is never logged.
# ==============================================================================
register_secret() {

    local secret="${1-}"
    local registered_secret


    if [[ -z "$secret" ]]; then

        log_error "Cannot register an empty secret."

        return 2
    fi


    for registered_secret in "${STOLEUS_REGISTERED_SECRETS[@]}"; do

        if [[ "$registered_secret" == "$secret" ]]; then

            return 0
        fi
    done


    STOLEUS_REGISTERED_SECRETS+=("$secret")

    return 0
}


# ==============================================================================
# unregister_secret
# ==============================================================================
#
# Purpose:
#     Remove one sensitive value from automatic log redaction.
#
# The secret variable held by the caller should also be unset afterwards.
# ==============================================================================
unregister_secret() {

    local secret="${1-}"
    local registered_secret

    local -a remaining_secrets=()


    if [[ -z "$secret" ]]; then

        return 0
    fi


    for registered_secret in "${STOLEUS_REGISTERED_SECRETS[@]}"; do

        if [[ "$registered_secret" != "$secret" ]]; then

            remaining_secrets+=("$registered_secret")
        fi
    done


    STOLEUS_REGISTERED_SECRETS=(
        "${remaining_secrets[@]}"
    )

    return 0
}


# ==============================================================================
# clear_registered_secrets
# ==============================================================================
#
# Purpose:
#     Remove all registered secrets from process memory.
# ==============================================================================
clear_registered_secrets() {

    STOLEUS_REGISTERED_SECRETS=()

    return 0
}


# ==============================================================================
# redact_text
# ==============================================================================
#
# Purpose:
#     Replace every registered secret found inside text.
#
# Output:
#
#     Prints the redacted text to stdout.
#
# Important:
#
#     This function deliberately does not emit logs because it is itself used
#     by the logging system.
# ==============================================================================
redact_text() {

    local text="${1-}"
    local secret
    local escaped_secret


    for secret in "${STOLEUS_REGISTERED_SECRETS[@]}"; do

        if [[ -z "$secret" ]]; then

            continue
        fi


        escaped_secret="$(
            escape_shell_pattern "$secret"
        )"


        text="${text//$escaped_secret/***REDACTED***}"
    done


    printf '%s\n' "$text"

    return 0
}