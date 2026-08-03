#!/usr/bin/env bash

set -Eeuo pipefail


# ==============================================================================
# verify_chrony_synchronization
# ==============================================================================
#
# Purpose:
#     Verify that Chrony has a valid synchronization source and that the local
#     system clock is close to synchronized time.
#
# Verification occurs at two levels:
#
#     1. Internal Chrony verification
#
#        - `Leap status` must be `Normal`.
#        - Chrony's reported system-time offset must be no greater than one
#          second.
#
#     2. Independent external verification
#
#        - The local UTC clock is compared with the HTTP Date header returned by
#          GitHub.
#        - The difference must be no greater than five seconds.
#
# Why both checks are required:
#
#     Chrony can report a very small offset relative to its selected NTP source,
#     but that does not independently prove that the resulting system time is
#     correct relative to external services.
#
#     GitHub Actions registration and OAuth authentication are time-sensitive,
#     so an independent external verification protects against false-positive
#     synchronization reports.
#
# Recovery:
#
#     If Chrony has a valid source but reports an offset greater than one second,
#     this function runs:
#
#         chronyc makestep
#
#     This applies the remaining clock correction immediately instead of waiting
#     for Chrony to adjust the clock gradually.
#
# Return codes:
#
#     0 = Chrony and external clock verification succeeded
#     1 = general synchronization failure
#     other standardized Stoleus exit codes may be returned by shared helpers
# ==============================================================================
verify_chrony_synchronization() {

    local maximum_attempts=10
    local current_attempt=1

    local maximum_chrony_offset_seconds="1.0"
    local maximum_external_skew_seconds="5"

    local tracking_output=""
    local leap_status=""
    local system_time_offset=""
    local absolute_offset=""


    require_root || return "${STOLEUS_EXIT_PERMISSION:-5}"

    require_command "chronyc" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"

    require_command "awk" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"

    require_command "sleep" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"


    log_info "Waiting for Chrony synchronization..."


    while (( current_attempt <= maximum_attempts )); do

        # ----------------------------------------------------------------------
        # Reset values so data from a previous attempt cannot be reused.
        # ----------------------------------------------------------------------
        tracking_output=""
        leap_status=""
        system_time_offset=""
        absolute_offset=""


        # ----------------------------------------------------------------------
        # Read the complete Chrony tracking report once per attempt.
        # ----------------------------------------------------------------------
        if ! tracking_output="$(chronyc tracking 2>&1)"; then

            log_warning \
                "Unable to read Chrony tracking information on attempt ${current_attempt}/${maximum_attempts}."

        else

            # ------------------------------------------------------------------
            # Extract the Leap status.
            #
            # Example:
            #
            #     Leap status     : Normal
            #
            # Result:
            #
            #     Normal
            # ------------------------------------------------------------------
            leap_status="$(
				awk -F ':' '
					/^Leap status/ {
						value = $2
						gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
						print value
						exit
					}
				' <<< "$tracking_output"
			)"


            # ------------------------------------------------------------------
            # Extract the signed System time offset.
            #
            # Examples:
            #
            #     System time : 5.200000000 seconds slow of NTP time
            #
            # becomes:
            #
            #     -5.200000000
            #
            # And:
            #
            #     System time : 0.300000000 seconds fast of NTP time
            #
            # becomes:
            #
            #     0.300000000
            # ------------------------------------------------------------------
            system_time_offset="$(
                awk '
                    /^System time/ {
                        offset = $4

                        if ($6 == "slow") {
                            offset = -offset
                        }

                        print offset
                        exit
                    }
                ' <<< "$tracking_output"
            )"


            log_debug \
                "Chrony leap status on attempt ${current_attempt}: ${leap_status:-unavailable}"

            log_debug \
                "Chrony system-time offset on attempt ${current_attempt}: ${system_time_offset:-unavailable}"


            # ------------------------------------------------------------------
            # Validate that the extracted offset is numeric.
            # ------------------------------------------------------------------
            if [[ "$system_time_offset" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then

                # --------------------------------------------------------------
                # Convert the signed offset to an absolute value.
                # --------------------------------------------------------------
                absolute_offset="$(
                    awk -v value="$system_time_offset" '
                        BEGIN {
                            if (value < 0) {
                                value = -value
                            }

                            printf "%.9f", value
                        }
                    '
                )"


                # --------------------------------------------------------------
                # Chrony's internal state is acceptable only when:
                #
                #     Leap status = Normal
                #     absolute offset <= 1 second
                # --------------------------------------------------------------
                if [[ "$leap_status" == "Normal" ]] &&
                   awk \
                       -v offset="$absolute_offset" \
                       -v maximum="$maximum_chrony_offset_seconds" \
                       'BEGIN { exit !(offset <= maximum) }'; then

                    log_info \
                        "Chrony internal synchronization is valid; system-time offset is ${absolute_offset} seconds."


                    # ----------------------------------------------------------
                    # Independently compare local UTC time with GitHub.
                    #
                    # Chrony's internal status alone is not accepted as final
                    # proof that the system clock is correct.
                    # ----------------------------------------------------------
                    if verify_remote_clock_skew \
                        "https://github.com" \
                        "$maximum_external_skew_seconds"; then

                        log_success \
                            "Chrony synchronization verified internally and against external time."

                        return "${STOLEUS_EXIT_SUCCESS:-0}"
                    fi


                    local external_verification_exit_code=$?


                    log_error \
                        "Chrony reported synchronization, but external clock verification failed."

                    return "$external_verification_exit_code"
                fi


                # --------------------------------------------------------------
                # Chrony has a valid synchronization source, but the system clock
                # still differs too much from Chrony's selected time source.
                #
                # Apply the correction immediately.
                # --------------------------------------------------------------
                if [[ "$leap_status" == "Normal" ]] &&
                   awk \
                       -v offset="$absolute_offset" \
                       -v maximum="$maximum_chrony_offset_seconds" \
                       'BEGIN { exit !(offset > maximum) }'; then

                    log_warning \
                        "System-time offset is ${absolute_offset} seconds; applying an immediate Chrony step."


                    if ! chronyc makestep >/dev/null 2>&1; then

                        log_error \
                            "Chrony failed to apply the immediate clock correction."

                        return "${STOLEUS_EXIT_FAILURE:-1}"
                    fi


                    log_info \
                        "Chrony accepted the immediate clock-correction request."
                fi

            else

                log_warning \
                    "Chrony did not return a readable system-time offset."
            fi
        fi


        # ----------------------------------------------------------------------
        # Wait before the next attempt unless this was the final attempt.
        # ----------------------------------------------------------------------
        if (( current_attempt < maximum_attempts )); then

            log_info \
                "Chrony verification attempt ${current_attempt}/${maximum_attempts} was not yet successful."

            sleep 3
        fi


        current_attempt=$((current_attempt + 1))
    done


    log_error \
        "Chrony synchronization was not confirmed within the allowed time."

    return "${STOLEUS_EXIT_VERIFICATION:-7}"
}


# ==============================================================================
# setup_chrony
# ==============================================================================
#
# Purpose:
#     Ensure that Chrony is:
#
#         - installed
#         - enabled at boot
#         - currently running
#         - synchronized with a valid NTP source
#         - independently verified against external UTC time
#
# The operation is successful only when both Chrony's internal state and the
# external clock-skew check pass.
# ==============================================================================
setup_chrony() {

    require_root ||
        return "${STOLEUS_EXIT_PERMISSION:-5}"


    log_info "Starting Chrony setup."


    ensure_package_installed "chrony" ||
        return "${STOLEUS_EXIT_FAILURE:-1}"


    ensure_service_enabled_and_running "chrony.service" ||
        return "${STOLEUS_EXIT_FAILURE:-1}"


    verify_chrony_synchronization || return $?


    log_success "Chrony setup completed successfully."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}