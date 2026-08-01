#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# verify_chrony_synchronization
# ==============================================================================
#
# Purpose:
#     Verify that Chrony has a valid synchronization source and that the local
#     system clock is actually close to synchronized time.
#
# Why checking only "Leap status: Normal" is insufficient:
#
#     Chrony can report:
#
#         Leap status : Normal
#
#     while still gradually correcting a very large clock difference.
#
# We therefore verify both:
#
#     1. Leap status is Normal.
#     2. System time offset is no greater than one second.
#
# If the remaining offset is larger than one second, we run:
#
#     chronyc makestep
#
# This immediately applies the outstanding clock correction rather than waiting
# for Chrony to adjust it gradually.
# ==============================================================================
verify_chrony_synchronization() {

    local maximum_attempts=10
    local current_attempt=1
    local maximum_offset_seconds="1.0"

    local tracking_output
    local leap_status
    local system_time_offset
    local absolute_offset


    require_root || return 1
    require_command "chronyc" || return 1
    require_command "awk" || return 1


    log_info "Waiting for Chrony synchronization..."


    while (( current_attempt <= maximum_attempts )); do

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
            # Output:
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
            #         -> -5.200000000
            #
            #     System time : 0.300000000 seconds fast of NTP time
            #         -> 0.300000000
            #
            # The sign is not important for the threshold, but preserving it
            # makes diagnostic output accurate.
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
                # The server is healthy only when:
                #
                #     Leap status = Normal
                #     absolute offset <= 1 second
                # --------------------------------------------------------------
                if [[ "$leap_status" == "Normal" ]] &&
                   awk \
                       -v offset="$absolute_offset" \
                       -v maximum="$maximum_offset_seconds" \
                       'BEGIN { exit !(offset <= maximum) }'; then

                    log_success \
                        "Chrony is synchronized; system-time offset is ${absolute_offset} seconds."

                    return 0
                fi


                # --------------------------------------------------------------
                # Chrony has a valid source, but the local clock is still far
                # away from synchronized time.
                #
                # Apply the outstanding correction immediately.
                # --------------------------------------------------------------
                if [[ "$leap_status" == "Normal" ]] &&
                   awk \
                       -v offset="$absolute_offset" \
                       -v maximum="$maximum_offset_seconds" \
                       'BEGIN { exit !(offset > maximum) }'; then

                    log_warning \
                        "System-time offset is ${absolute_offset} seconds; applying an immediate Chrony step."


                    if ! chronyc makestep; then

                        log_error "Chrony failed to apply the clock correction."

                        return 1
                    fi
                fi
            else

                log_warning \
                    "Chrony did not return a readable system-time offset."
            fi
        fi


        if (( current_attempt < maximum_attempts )); then

            log_info \
                "Chrony verification attempt ${current_attempt}/${maximum_attempts} was not yet successful."

            sleep 3
        fi


        current_attempt=$((current_attempt + 1))
    done


    log_error \
        "Chrony synchronization was not confirmed within the allowed time."

    return 1
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
#         - synchronized
# ==============================================================================
setup_chrony() {

    require_root || return 1

    log_info "Starting Chrony setup."

    ensure_package_installed "chrony" || return 1

    ensure_service_enabled_and_running "chrony.service" || return 1

    verify_chrony_synchronization || return 1

    log_success "Chrony setup completed successfully."
}