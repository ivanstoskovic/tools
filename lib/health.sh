#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Health Check Library
# ==============================================================================
#
# This file contains reusable functions used by:
#
#     stoleus health
#
# The command itself will live in:
#
#     commands/health.sh
#
# while the actual checks will live here.
#
# Later this file will contain functions such as:
#
#     check_time_sync
#     check_ssh
#     check_firewall
#     check_docker
#     check_postgresql
#     check_disk_space
#     check_memory
#
# Keeping the checks in a library separates:
#
#     CLI behavior             -> commands/health.sh
#     Health-check logic       -> lib/health.sh
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash error handling.
#
# -E
#     Preserve ERR traps inside functions and subshells.
#
# -e
#     Stop when an unexpected command fails.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     A pipeline fails if any important command in it fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# Health Result Counters
# ==============================================================================
#
# We keep track of how many warnings and failures were detected.
#
# Example final report:
#
#     Failures: 0
#     Warnings: 1
#
# These are ordinary global variables because every health-check function
# needs to update the same counters.
#
# We do NOT use readonly here because their values must change.
# ==============================================================================

HEALTH_FAILURES=0
HEALTH_WARNINGS=0

# IMPORTANT DESIGN RULE:
# Individual health checks record FAIL/WARN results in these counters but return
# success to the dispatcher. This lets the report continue through every check.
# commands/health.sh returns the final non-zero process exit code only after the
# complete report has been printed.


# ==============================================================================
# health_pass
# ==============================================================================
#
# Purpose:
#     Print a successful health-check result.
#
# Usage:
#
#     health_pass "Docker" "Engine is running"
#
# Output:
#
#     PASS  Docker                   Engine is running
#
# `$1`
#     First argument passed to the function.
#
# `$2`
#     Second argument passed to the function.
#
# `printf`
#     Prints formatted output.
#
#     Print a string in a field 6 characters wide and left-align it.
#
# `%-24s`
#     Print a string in a field 24 characters wide and left-align it.
#
# `%s`
#     Print the final string normally.
#
# `\n`
#     Print a newline.
# ==============================================================================
health_pass() {
    local component="$1"
    local details="$2"

    printf '%-6s %-24s %s\n' \
        "PASS" \
        "$component" \
        "$details"
}


# ==============================================================================
# health_warn
# ==============================================================================
#
# Purpose:
#     Report a condition that is not currently fatal but deserves attention.
#
# Example:
#
#     health_warn "Disk Space" "87% used"
#
# The warning counter is incremented using:
#
#     HEALTH_WARNINGS=$((HEALTH_WARNINGS + 1))
#
# `$(( ... ))`
#     Bash arithmetic expansion.
#
# It allows Bash to perform integer calculations.
#
# Example:
#
#     count=$((count + 1))
#
# is conceptually similar to:
#
#     count++;
#
# in C#.
# ==============================================================================
health_warn() {
    local component="$1"
    local details="$2"

    HEALTH_WARNINGS=$((HEALTH_WARNINGS + 1))

    printf '%-6s %-24s %s\n' \
        "WARN" \
        "$component" \
        "$details"
}
# health_fail
# ==============================================================================
#
# Purpose:
#     Report an actual health-check failure.
#
# Example:
#
#     health_fail "Docker" "Engine is not running"
#
# Every failure increments HEALTH_FAILURES.
#
# Later the main health command will inspect this counter.
#
# If HEALTH_FAILURES is greater than zero, the command will return a non-zero
# exit code so CI/CD or monitoring systems can detect that the server is not
# healthy.
# ==============================================================================
health_fail() {
    local component="$1"
    local details="$2"

    HEALTH_FAILURES=$((HEALTH_FAILURES + 1))

    printf '%-6s %-24s %s\n' \
        "FAIL" \
        "$component" \
        "$details"
}


# ==============================================================================
# health_skip
# ==============================================================================
#
# Purpose:
#     Report that a particular check does not apply to this server.
#
# Example:
#
#     stoleusapp does not have PostgreSQL installed.
#
# Instead of reporting:
#
#     FAIL PostgreSQL
#
# we should report:
#
#     SKIP PostgreSQL               Not installed
#
# A skipped component is NOT a warning and NOT a failure.
#
# Therefore this function does not modify either counter.
# ==============================================================================
health_skip() {
    local component="$1"
    local details="$2"

    printf '%-6s %-24s %s\n' \
        "SKIP" \
        "$component" \
        "$details"
}


# ==============================================================================

# ==============================================================================
# check_time_sync
# ==============================================================================
#
# Purpose:
#     Verify whether the server clock is synchronized.
#
# On our Ubuntu servers, Chrony is the preferred time synchronization service.
#
# Why time synchronization matters:
#
#     - TLS certificates depend on correct time.
#     - GitHub Actions and authentication tokens depend on correct time.
#     - Logs from multiple servers need comparable timestamps.
#     - PostgreSQL and distributed systems rely on sane clocks.
#
# We first check whether the `chronyc` command exists.
#
# `command -v chronyc`
#     Looks for the command in the current PATH.
#
# `>/dev/null 2>&1`
#     Hides both normal output and error output because we only care about
#     whether the command exists.
#
# If Chrony does not exist, we report SKIP rather than FAIL, because some
# servers may use a different time synchronization implementation.
#
# If Chrony exists, we inspect:
#
#     chronyc tracking
#
# We specifically look for:
#
#     Leap status : Normal
#
# In Chrony, "Normal" indicates that the clock is synchronized and operating
# normally.
# ==============================================================================
check_time_sync() {

    # --------------------------------------------------------------------------
    # Check whether the Chrony client command exists.
    #
    # `command -v`
    #     Returns success if Bash can find the command.
    #
    # `!`
    #     Negates the result.
    #
    # Therefore:
    #
    #     if ! command -v chronyc ...
    #
    # means:
    #
    #     If chronyc does NOT exist...
    # --------------------------------------------------------------------------
    if ! command -v chronyc >/dev/null 2>&1; then

        health_skip \
            "Time Sync" \
            "Chrony is not installed"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Ask Chrony for its current synchronization state.
    #
    # `chronyc tracking`
    #
    # produces information such as:
    #
    #     Reference ID    : ...
    #     Stratum         : 3
    #     System time     : ...
    #     Leap status     : Normal
    #
    # We pipe the result into grep.
    #
    # `grep -q`
    #     Quiet mode.
    #
    # grep does not print the matching line; it only returns an exit status.
    #
    # Exit code:
    #
    #     0 = match found
    #     1 = match not found
    #
    # `-E`
    #     Enables extended regular expressions.
    #
    # `[[:space:]]*`
    #     Matches zero or more whitespace characters.
    #
    # This makes the check tolerant of different spacing around the colon.
    # --------------------------------------------------------------------------
    if chronyc tracking 2>/dev/null |
        grep -qE 'Leap status[[:space:]]*:[[:space:]]*Normal'; then

        health_pass \
            "Time Sync" \
            "Chrony synchronized"

        return 0
    fi


    # --------------------------------------------------------------------------
    # If Chrony exists but does not report "Leap status: Normal", something is
    # wrong with synchronization.
    #
    # This is a real health failure rather than a skipped check.
    # --------------------------------------------------------------------------
    health_fail \
        "Time Sync" \
        "Chrony is not synchronized"

    return 0
}

# ==============================================================================
# check_ssh
# ==============================================================================
#
# Purpose:
#     Verify that SSH is available and currently working.
#
# Why SSH matters:
#
#     - We use SSH to administer the Linux servers remotely.
#     - GitHub deployment workflows may rely on SSH.
#     - Losing SSH access can lock us out of the server.
#
# Important detail:
#
# On modern Ubuntu systems, SSH may use socket activation.
#
# That means:
#
#     ssh.socket
#
# can be enabled and listening on port 22, while:
#
#     ssh.service
#
# itself may show as disabled.
#
# We already saw this on our Stoleus servers.
#
# Therefore this health check must support BOTH:
#
#     ssh.socket
#
# and:
#
#     ssh.service
#
# ==============================================================================
check_ssh() {

    # --------------------------------------------------------------------------
    # First check whether systemd itself is available.
    #
    # `systemctl`
    #     Is the command used to communicate with systemd.
    #
    # Our Linux production/staging servers use systemd.
    #
    # On Windows Git Bash, however, systemctl normally does not exist.
    #
    # In that case we SKIP the check rather than reporting a failure.
    # --------------------------------------------------------------------------
    if ! command -v systemctl >/dev/null 2>&1; then

        health_skip \
            "SSH" \
            "systemd is not available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Prefer ssh.socket when it exists.
    #
    # `systemctl cat ssh.socket`
    #
    # asks systemd to display the unit definition.
    #
    # We do not actually care about the contents here.
    #
    # We only care whether the unit exists.
    #
    # Therefore:
    #
    #     >/dev/null 2>&1
    #
    # hides the output.
    # --------------------------------------------------------------------------
    if systemctl cat ssh.socket >/dev/null 2>&1; then

        # ----------------------------------------------------------------------
        # Check whether the socket is currently active.
        #
        # `systemctl is-active --quiet ssh.socket`
        #
        # returns:
        #
        #     0 -> active
        #     non-zero -> inactive
        #
        # `--quiet`
        #     suppresses normal output because we only need the exit code.
        # ----------------------------------------------------------------------
        if systemctl is-active --quiet ssh.socket; then

            health_pass \
                "SSH" \
                "ssh.socket is active"

            return 0
        fi


        # ----------------------------------------------------------------------
        # The socket exists but is not active.
        #
        # That means SSH is not currently accepting connections through the
        # expected socket-activation mechanism.
        # ----------------------------------------------------------------------
        health_fail \
            "SSH" \
            "ssh.socket exists but is not active"

        return 0
    fi


    # --------------------------------------------------------------------------
    # If ssh.socket does not exist, fall back to the traditional ssh.service.
    #
    # Older systems or differently configured systems may run sshd directly
    # as a continuously running service.
    # --------------------------------------------------------------------------
    if systemctl cat ssh.service >/dev/null 2>&1; then

        if systemctl is-active --quiet ssh.service; then

            health_pass \
                "SSH" \
                "ssh.service is active"

            return 0
        fi


        health_fail \
            "SSH" \
            "ssh.service exists but is not active"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Neither ssh.socket nor ssh.service exists.
    #
    # This usually means the OpenSSH server is not installed.
    #
    # Because some machines may intentionally not run SSH, we report SKIP
    # rather than FAIL.
    #
    # Later, a repair/provisioning command can decide whether SSH should be
    # installed automatically.
    # --------------------------------------------------------------------------
    health_skip \
        "SSH" \
        "OpenSSH server is not installed"

    return 0
}

# ==============================================================================
# check_firewall
# ==============================================================================
#
# Purpose:
#     Verify that UFW is installed and that the firewall is active.
#
# Why this matters:
#
#     - UFW controls which inbound network connections are allowed.
#     - On our Stoleus servers, we intentionally use UFW to restrict access.
#     - An inactive firewall can expose services that should not be reachable.
#
# This health check is READ-ONLY.
#
# It does NOT:
#
#     - enable UFW
#     - add firewall rules
#     - remove firewall rules
#
# Later we can create a separate repair/configuration command for that.
# ==============================================================================
check_firewall() {

    # --------------------------------------------------------------------------
    # Check whether UFW is installed.
    # --------------------------------------------------------------------------
    if ! command -v ufw >/dev/null 2>&1; then

        health_skip \
            "Firewall" \
            "UFW is not installed"

        return 0
    fi


    # --------------------------------------------------------------------------
    # UFW's `status` command requires root privileges on Ubuntu.
    #
    # IMPORTANT:
    #     We do NOT call `sudo` from inside the health check.
    #
    # Why?
    #     - sudo may prompt for a password and hang an automated health check.
    #     - systemd jobs must be non-interactive.
    #     - privilege escalation should be explicit.
    #
    # When run manually as a normal user, report that an authoritative firewall
    # check requires root instead of incorrectly claiming that UFW is inactive.
    #
    # `$EUID`
    #     Effective user ID of the current Bash process.
    #
    # Root always has EUID 0.
    # --------------------------------------------------------------------------
    if (( EUID != 0 )); then

        health_warn \
            "Firewall" \
            "Status check requires root; run 'sudo stoleus health'"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Capture UFW output so we can distinguish:
    #
    #     active
    #     inactive
    #     command/error condition
    #
    # instead of treating every non-successful parse as "inactive".
    # --------------------------------------------------------------------------
    local ufw_output

    if ! ufw_output="$(ufw status 2>&1)"; then

        health_warn \
            "Firewall" \
            "Unable to read UFW status"

        return 0
    fi


    if grep -q '^Status: active' <<< "$ufw_output"; then

        health_pass \
            "Firewall" \
            "UFW is active"

        return 0
    fi


    if grep -q '^Status: inactive' <<< "$ufw_output"; then

        health_fail \
            "Firewall" \
            "UFW is installed but inactive"

        # Health checks record the failure but return 0 so the remaining checks
        # still run. commands/health.sh decides the final process exit code from
        # HEALTH_FAILURES after the complete report is produced.
        return 0
    fi


    health_warn \
        "Firewall" \
        "UFW returned an unexpected status"

    return 0
}

# ==============================================================================
# check_docker
# ==============================================================================
#
# Purpose:
#     Verify whether Docker is installed and whether the Docker Engine is
#     currently running.
#
# Why Docker matters:
#
#     - Our Stoleus application servers will run applications in containers.
#     - GitHub Actions deployments may need to build/start Docker containers.
#     - If Docker is installed but stopped, deployments will fail.
#
# This health check is READ-ONLY.
#
# It does NOT:
#
#     - install Docker
#     - start Docker
#     - enable Docker at boot
#     - restart containers
#
# Later, a repair/provisioning command can perform those actions explicitly.
# ==============================================================================
check_docker() {

    # --------------------------------------------------------------------------
    # Check whether the Docker CLI exists.
    # --------------------------------------------------------------------------
    if ! command -v docker >/dev/null 2>&1; then

        health_skip \
            "Docker" \
            "Docker is not installed"

        return 0
    fi


    # --------------------------------------------------------------------------
    # On systemd-based Linux servers, first inspect the Docker service itself.
    #
    # This lets us distinguish:
    #
    #     service stopped
    #
    # from:
    #
    #     service running but current user cannot access /var/run/docker.sock
    # --------------------------------------------------------------------------
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl cat docker.service >/dev/null 2>&1; then

        if ! systemctl is-active --quiet docker.service; then

            health_fail \
                "Docker" \
                "Docker service is installed but not running"

            return 0
        fi
    fi


    # --------------------------------------------------------------------------
    # `docker info` performs an actual client -> daemon communication test.
    # --------------------------------------------------------------------------
    if docker info >/dev/null 2>&1; then

        health_pass \
            "Docker" \
            "Docker Engine is running and accessible"

        return 0
    fi


    # --------------------------------------------------------------------------
    # If systemd says Docker is active but `docker info` fails for a non-root
    # user, permissions are a common cause. Check group membership so the report
    # gives a more useful diagnosis.
    # --------------------------------------------------------------------------
    if (( EUID != 0 )) && command -v id >/dev/null 2>&1; then

        if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx docker; then

            health_fail \
                "Docker Access" \
                "Current user is not a member of the docker group"

            return 0
        fi
    fi


    health_fail \
        "Docker" \
        "Docker daemon is running but cannot be reached by this user"

    return 0
}

# ==============================================================================
# check_docker_compose
# ==============================================================================
#
# Purpose:
#     Verify that the modern Docker Compose plugin is available.
#
# Why this matters:
#
#     Docker Engine and Docker Compose are separate things.
#
#     Docker Engine lets us run containers:
#
#         docker run ...
#
#     Docker Compose lets us define and run multi-container applications:
#
#         docker compose up -d
#
# Our deployment model will rely heavily on:
#
#     docker compose
#
# rather than the old standalone command:
#
#     docker-compose
#
# This health check is READ-ONLY.
# It does not install or repair Docker Compose.
# ==============================================================================
check_docker_compose() {

    # --------------------------------------------------------------------------
    # First make sure Docker itself exists.
    #
    # `docker compose` is a Docker CLI plugin, so there is no point checking it
    # if the main `docker` command is missing.
    # --------------------------------------------------------------------------
    if ! command -v docker >/dev/null 2>&1; then

        health_skip \
            "Docker Compose" \
            "Docker is not installed"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Ask Docker for the Compose plugin version.
    #
    # Example:
    #
    #     docker compose version
    #
    # might return:
    #
    #     Docker Compose version v5.3.1
    #
    # We suppress the output because we only need the exit code.
    #
    # Exit code 0 means the Compose plugin is available.
    # --------------------------------------------------------------------------
    if docker compose version >/dev/null 2>&1; then

        health_pass \
            "Docker Compose" \
            "Compose plugin is available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Docker exists, but the modern Compose plugin does not.
    #
    # This is a real failure for our application servers because our deployment
    # tooling will expect commands such as:
    #
    #     docker compose up -d
    #
    # Later, our repair/install command can install the missing plugin.
    # --------------------------------------------------------------------------
    health_fail \
        "Docker Compose" \
        "Compose plugin is not available"

    return 0
}

# ==============================================================================
# check_postgresql
# ==============================================================================
#
# Purpose:
#     Verify whether PostgreSQL is installed, whether its service is running,
#     and whether PostgreSQL is actually accepting connections.
#
# Why this is better than checking only systemctl:
#
#     A Linux service can be "active" while the application itself is not ready.
#
# For PostgreSQL, `pg_isready` performs a lightweight readiness check.
#
# Result logic:
#
#     PostgreSQL not installed
#         -> SKIP
#
#     PostgreSQL installed but service stopped
#         -> FAIL
#
#     PostgreSQL service running but pg_isready fails
#         -> FAIL
#
#     PostgreSQL service running and accepting connections
#         -> PASS
#
# This function is READ-ONLY.
# ==============================================================================
check_postgresql() {

    # --------------------------------------------------------------------------
    # First check whether PostgreSQL's command-line client exists.
    #
    # `command -v psql`
    #     Searches PATH for the psql executable.
    #
    # If psql does not exist, PostgreSQL is considered not installed for this
    # health check.
    # --------------------------------------------------------------------------
    if ! command -v psql >/dev/null 2>&1; then

        health_skip \
            "PostgreSQL" \
            "PostgreSQL is not installed"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Our Ubuntu servers use systemd to manage PostgreSQL.
    #
    # If systemctl is unavailable, we cannot reliably verify the service state.
    # --------------------------------------------------------------------------
    if ! command -v systemctl >/dev/null 2>&1; then

        health_skip \
            "PostgreSQL" \
            "systemd is not available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Verify that the PostgreSQL systemd service is active.
    #
    # `systemctl is-active --quiet`
    #     Returns 0 if the service is active.
    #
    # If it is not active, the database cannot be considered healthy.
    # --------------------------------------------------------------------------
    if ! systemctl is-active --quiet postgresql.service; then

        health_fail \
            "PostgreSQL" \
            "Service is installed but not running"

        return 0
    fi


    # --------------------------------------------------------------------------
    # At this point the Linux service is running.
    #
    # Now check whether the PostgreSQL server is actually ready.
    #
    # `pg_isready`
    #     PostgreSQL utility that checks whether the server is accepting
    #     connections.
    #
    # Typical successful output:
    #
    #     /var/run/postgresql:5432 - accepting connections
    #
    # We suppress the output because our own report should remain consistent.
    # --------------------------------------------------------------------------
    if ! command -v pg_isready >/dev/null 2>&1; then

        # ----------------------------------------------------------------------
        # The service is running, but the readiness utility is unavailable.
        #
        # This is not necessarily a database failure, so WARN is more accurate
        # than FAIL.
        # ----------------------------------------------------------------------
        health_warn \
            "PostgreSQL" \
            "Service running; pg_isready is unavailable"

        return 0
    fi


    # --------------------------------------------------------------------------
    # `pg_isready` can often be executed directly.
    #
    # We intentionally do not provide a database username/password here.
    #
    # This is only a server-readiness probe, not an application login test.
    # --------------------------------------------------------------------------
    if pg_isready >/dev/null 2>&1; then

        health_pass \
            "PostgreSQL" \
            "Service running and accepting connections"

        return 0
    fi


    # --------------------------------------------------------------------------
    # systemd reports the service as active, but PostgreSQL is not accepting
    # connections.
    #
    # Possible causes:
    #
    #     - PostgreSQL is still starting
    #     - database startup failed partially
    #     - socket/port configuration problem
    #     - cluster/database instance problem
    #
    # Therefore this is a real health failure.
    # --------------------------------------------------------------------------
    health_fail \
        "PostgreSQL" \
        "Service running but not accepting connections"

    return 0
}

# ==============================================================================
# check_disk_usage
# ==============================================================================
#
# Purpose:
#     Check mounted filesystems and detect dangerously high disk usage.
#
# Why disk usage matters:
#
#     A full filesystem can cause:
#
#     - Docker failures
#     - PostgreSQL failures
#     - log-writing failures
#     - package update failures
#     - application crashes
#
# Thresholds:
#
#     below 85%  -> PASS
#     85-94%     -> WARN
#     95%+       -> FAIL
#
# We ignore pseudo-filesystems such as tmpfs and devtmpfs because they are
# memory-backed system filesystems rather than normal persistent disk storage.
#
# This function is READ-ONLY.
# ==============================================================================

check_disk_usage() {

    # --------------------------------------------------------------------------
    # Local variables used to track the filesystem with the highest usage.
    #
    # worst_usage
    #     Highest percentage seen so far.
    #
    # worst_mount
    #     Mount point corresponding to that percentage.
    # --------------------------------------------------------------------------
    local worst_usage=0
    local worst_mount="/"

    # --------------------------------------------------------------------------
    # `df`
    #     Displays filesystem disk usage.
    #
    # -P
    #     Uses POSIX output format, which is easier and safer to parse.
    #
    # -x tmpfs
    #     Excludes tmpfs.
    #
    # -x devtmpfs
    #     Excludes devtmpfs.
    #
    # Example output:
    #
    # Filesystem     1024-blocks    Used Available Capacity Mounted on
    # /dev/sda3        24100000   7000000  16000000      31% /
    #
    # `awk`
    #     Extracts:
    #
    #         mount point
    #         usage percentage
    #
    # NR > 1
    #     Skips the header line.
    #
    # $6
    #     Mount point.
    #
    # $5
    #     Usage percentage.
    #
    # The output becomes something like:
    #
    #     / 31%
    #     /var/lib/docker 4%
    # --------------------------------------------------------------------------
    while read -r mountpoint usage; do

        # ----------------------------------------------------------------------
        # Remove the `%` character.
        #
        # Example:
        #
        #     31%
        #
        # becomes:
        #
        #     31
        #
        # `${usage%\%}`
        #     Bash parameter expansion that removes a trailing `%`.
        # ----------------------------------------------------------------------
        usage="${usage%\%}"


        # ----------------------------------------------------------------------
        # Some special filesystems can return values that are not numeric.
        #
        # We only continue if usage contains digits.
        #
        # `=~`
        #     Bash regular-expression operator.
        #
        # ^[0-9]+$
        #     Means:
        #
        #     start of string
        #     one or more digits
        #     end of string
        # ----------------------------------------------------------------------
        [[ "$usage" =~ ^[0-9]+$ ]] || continue


        # ----------------------------------------------------------------------
        # Remember the filesystem with the highest utilization.
        # ----------------------------------------------------------------------
        if (( usage > worst_usage )); then
            worst_usage="$usage"
            worst_mount="$mountpoint"
        fi


        # ----------------------------------------------------------------------
        # Critical threshold:
        #
        # 95% or more is considered a failure.
        # ----------------------------------------------------------------------
        if (( usage >= 95 )); then

            health_fail \
                "Disk $mountpoint" \
                "${usage}% used"

        # ----------------------------------------------------------------------
        # Warning threshold:
        #
        # 85-94% requires attention but is not yet critical.
        # ----------------------------------------------------------------------
        elif (( usage >= 85 )); then

            health_warn \
                "Disk $mountpoint" \
                "${usage}% used"
        fi

    done < <(
        df -P -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null |
            awk 'NR > 1 {print $NF, $(NF-1)}'
    )


    # --------------------------------------------------------------------------
    # If the worst filesystem is still below the warning threshold, report one
    # concise PASS line instead of printing PASS for every mounted filesystem.
    #
    # Example:
    #
    #     PASS   Disk Usage    Highest: 31% on /
    # --------------------------------------------------------------------------
    if (( worst_usage < 85 )); then

        health_pass \
            "Disk Usage" \
            "Highest: ${worst_usage}% on ${worst_mount}"
    fi
}

# ==============================================================================
# check_memory
# ==============================================================================
#
# Purpose:
#     Check how much RAM is currently available to the operating system.
#
# Why memory matters:
#
#     Very low available memory can cause:
#
#     - application slowdowns
#     - Docker container failures
#     - PostgreSQL performance problems
#     - Linux OOM (Out Of Memory) killer activity
#
# We use Linux:
#
#     /proc/meminfo
#
# which contains live memory information provided by the Linux kernel.
#
# Example:
#
#     MemTotal:       32768000 kB
#     MemAvailable:   27000000 kB
#
# `MemAvailable` is more useful than simply looking at "free" RAM because Linux
# intentionally uses unused memory for filesystem cache and can reclaim much
# of that memory when applications need it.
#
# Thresholds for now:
#
#     >= 512 MB available   -> PASS
#     256-511 MB available  -> WARN
#     < 256 MB available    -> FAIL
#
# We can later move these thresholds into configuration.
#
# This function is READ-ONLY.
# ==============================================================================

check_memory() {

    # --------------------------------------------------------------------------
    # `/proc/meminfo` is provided by the Linux kernel.
    #
    # On a non-Linux development environment such as Windows Git Bash, this
    # file may not exist or may not provide Linux server memory information.
    #
    # In that case we SKIP rather than incorrectly report a failure.
    #
    # `-r`
    #     Means: does this file exist and can the current user read it?
    # --------------------------------------------------------------------------
    if [[ ! -r /proc/meminfo ]]; then

        health_skip \
            "Memory" \
            "/proc/meminfo is not available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Declare a local variable that will store available memory in megabytes.
    # --------------------------------------------------------------------------
    local available_mb


    # --------------------------------------------------------------------------
    # Read MemAvailable from /proc/meminfo.
    #
    # `awk`
    #     Processes text line by line.
    #
    # `/^MemAvailable:/`
    #     Selects the line beginning with:
    #
    #         MemAvailable:
    #
    # `$2`
    #     Represents the second whitespace-separated field.
    #
    # Example:
    #
    #     MemAvailable:   27987968 kB
    #
    # `$2` is:
    #
    #     27987968
    #
    # The kernel reports this value in KB.
    #
    # We divide by 1024 to convert:
    #
    #     KB -> MB
    #
    # `int(...)`
    #     Removes the decimal part because we only need whole megabytes.
    #
    # `$(...)`
    #     Command substitution: Bash executes awk and stores its output in
    #     available_mb.
    # --------------------------------------------------------------------------
    available_mb="$(
        awk '/^MemAvailable:/ {
            print int($2 / 1024)
            exit
        }' /proc/meminfo
    )"


    # --------------------------------------------------------------------------
    # Validate the value before using it in arithmetic.
    #
    # `=~`
    #     Bash regular-expression comparison.
    #
    # `^[0-9]+$`
    #     Means the entire value must contain one or more numeric digits.
    #
    # If something unexpected happened while reading /proc/meminfo, we report
    # a warning instead of attempting invalid arithmetic.
    # --------------------------------------------------------------------------
    if [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then

		health_skip \
			"Memory" \
			"MemAvailable is not exposed by this environment"

		return 0
	fi


    # --------------------------------------------------------------------------
    # Critical condition:
    #
    # Less than 256 MB available.
    #
    # `(( ... ))`
    #     Bash arithmetic expression.
    # --------------------------------------------------------------------------
    if (( available_mb < 256 )); then

        health_fail \
            "Memory" \
            "Critical: ${available_mb} MB available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Warning condition:
    #
    # 256 MB through 511 MB available.
    # --------------------------------------------------------------------------
    if (( available_mb < 512 )); then

        health_warn \
            "Memory" \
            "Low: ${available_mb} MB available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Anything >= 512 MB is currently considered healthy.
    # --------------------------------------------------------------------------
    health_pass \
        "Memory" \
        "${available_mb} MB available"

    return 0
}

# ==============================================================================
# check_github_runners
# ==============================================================================
#
# Purpose:
#     Verify whether GitHub Actions self-hosted runner services are installed
#     and, if installed, whether they are currently running.
#
# Why this matters:
#
#     Our CI/CD pipelines depend on self-hosted GitHub Actions runners.
#
# If a runner service is stopped:
#
#     - GitHub jobs may remain queued
#     - deployments may not start
#     - maintenance workflows may fail
#
# Result logic:
#
#     No runner services found
#         -> SKIP
#
#     Runner service active
#         -> PASS
#
#     Runner service stopped
#         -> FAIL
#
# Multiple runners are supported.
#
# GitHub runner services usually have names similar to:
#
#     actions.runner.<owner>-<repo>.<runner-name>.service
#
# Example:
#
#     actions.runner.ivanstoskovic-tools.stoleusapp.service
#
# This function is READ-ONLY.
# It does not start or enable runner services.
# ==============================================================================
check_github_runners() {

    # --------------------------------------------------------------------------
    # GitHub runners on our Linux servers are managed by systemd.
    #
    # If systemctl is not available, we cannot perform this check.
    #
    # This will happen on Windows Git Bash, for example.
    # --------------------------------------------------------------------------
    if ! command -v systemctl >/dev/null 2>&1; then

        health_skip \
            "GitHub Runner" \
            "systemd is not available"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Create an empty Bash array.
    #
    # Arrays allow us to store multiple runner service names.
    #
    # Example:
    #
    #     runner_units[0]="actions.runner.repo1.runner1.service"
    #     runner_units[1]="actions.runner.repo2.runner2.service"
    #
    # `local`
    #     Keeps the array scoped to this function.
    #
    # `-a`
    #     Explicitly declares an indexed array.
    # --------------------------------------------------------------------------
    local -a runner_units=()


    # --------------------------------------------------------------------------
    # `mapfile`
    #     Reads lines from standard input into a Bash array.
    #
    # `-t`
    #     Removes the trailing newline from each line.
    #
    # So:
    #
    #     mapfile -t runner_units
    #
    # means:
    #
    #     Read each output line and store it as one element in runner_units.
    #
    # `< <(...)`
    #     This is called process substitution.
    #
    # Bash runs the command inside `< <(...)` and feeds its output into mapfile.
    # --------------------------------------------------------------------------
    mapfile -t runner_units < <(

        # ----------------------------------------------------------------------
        # Ask systemd for all installed service unit files.
        #
        # `list-unit-files`
        #     Shows service definitions whether they are currently running or not.
        #
        # `--type=service`
        #     Only return service units.
        #
        # `--no-legend`
        #     Removes the header/footer text so the output is easier to parse.
        # ----------------------------------------------------------------------
        systemctl list-unit-files \
            --type=service \
            --no-legend \
            2>/dev/null |

            # ------------------------------------------------------------------
            # Use awk to select only GitHub runner service names.
            #
            # `$1`
            #     First field of each line, which is the service name.
            #
            # `~`
            #     Means "matches regular expression".
            #
            # /^actions\.runner\..*\.service$/
            #
            # means:
            #
            #     starts with: actions.runner.
            #     followed by anything
            #     ends with: .service
            #
            # The backslashes escape dots so they mean literal "." characters.
            # ------------------------------------------------------------------
            awk '$1 ~ /^actions\.runner\..*\.service$/ {print $1}'
    )


    # --------------------------------------------------------------------------
    # `${#runner_units[@]}`
    #     Returns the number of elements in the array.
    #
    # If the result is zero, no GitHub runner service was found.
    # --------------------------------------------------------------------------
    if (( ${#runner_units[@]} == 0 )); then

        health_skip \
            "GitHub Runner" \
            "No runner services installed"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Track whether any runner failed.
    #
    # We use:
    #
    #     0 = no failure
    #     1 = at least one runner failed
    #
    # This allows us to inspect every runner instead of stopping after the first
    # failed one.
    # --------------------------------------------------------------------------
    local runner_failed=0


    # --------------------------------------------------------------------------
    # Loop through every service stored in the array.
    #
    # `"${runner_units[@]}"`
    #     Expands every array element as a separate safely quoted value.
    # --------------------------------------------------------------------------
    local unit

    for unit in "${runner_units[@]}"; do

        # ----------------------------------------------------------------------
        # Check whether this particular runner service is active.
        # ----------------------------------------------------------------------
        if systemctl is-active --quiet "$unit"; then

            health_pass \
                "GitHub Runner" \
                "$unit is active"

        else

            health_fail \
                "GitHub Runner" \
                "$unit is not active"

            runner_failed=1
        fi
    done


    # --------------------------------------------------------------------------
    # Return a meaningful exit status.
    #
    # If any runner failed:
    #
    #     return 0
    #
    # Otherwise:
    #
    #     return 0
    #
    # Note:
    # health_fail() already increments HEALTH_FAILURES.
    # This return code only communicates the result of this function.
    # --------------------------------------------------------------------------
    if (( runner_failed > 0 )); then
        return 0
    fi

    return 0
}

# ==============================================================================
# check_network
# ==============================================================================
#
# Purpose:
#     Verify basic network connectivity required by our servers.
#
# We check three separate things:
#
#     1. Default route
#     2. DNS resolution
#     3. Outbound HTTPS connectivity
#
# Why separate them?
#
# Because "network is broken" can mean different things:
#
#     - no route to leave the local network
#     - DNS cannot translate names into IP addresses
#     - internet/HTTPS access is blocked
#
# By checking them separately, troubleshooting becomes much easier.
#
# This function is READ-ONLY.
# It does not modify Netplan, DNS, routes, firewall rules, or interfaces.
# ==============================================================================

check_network() {

    # ==========================================================================
    # 1. DEFAULT ROUTE
    # ==========================================================================
    #
    # A default route tells the operating system where to send traffic when
    # there is no more specific route.
    #
    # On Linux, it commonly looks like:
    #
    #     default via 192.168.1.1 dev enp0s3
    #
    # Without a default route, the server may still communicate with machines
    # on its local subnet but usually cannot reach external networks.
    # ==========================================================================

    # --------------------------------------------------------------------------
    # `ip route`
    #     Displays the kernel routing table.
    #
    # `ip route show default`
    #     Shows only the default route.
    #
    # `grep -q '^default '`
    #     Quietly checks whether a line beginning with "default " exists.
    #
    # We first verify that the `ip` command exists because Windows Git Bash may
    # not provide the Linux iproute2 command.
    # --------------------------------------------------------------------------
    if command -v ip >/dev/null 2>&1; then

        if ip route show default 2>/dev/null |
            grep -q '^default '; then

            health_pass \
                "Default Route" \
                "Default route is configured"

        else

            health_fail \
                "Default Route" \
                "No default route configured"
        fi

    else

        health_skip \
            "Default Route" \
            "Linux ip command is not available"
    fi


    # ==========================================================================
    # 2. DNS RESOLUTION
    # ==========================================================================
    #
    # DNS translates names such as:
    #
    #     github.com
    #
    # into IP addresses.
    #
    # A server may have working network connectivity but still fail to access
    # services by hostname if DNS is broken.
    # ==========================================================================

    # --------------------------------------------------------------------------
    # `getent hosts github.com`
    #
    # `getent`
    #     Queries system databases using the operating system's configured
    #     resolver.
    #
    # This is preferable to hardcoding tools such as nslookup because it tests
    # the same name-resolution mechanism applications normally use.
    #
    # Exit code 0 means the hostname was successfully resolved.
    # --------------------------------------------------------------------------
    if command -v getent >/dev/null 2>&1; then

        if getent hosts github.com >/dev/null 2>&1; then

            health_pass \
                "DNS" \
                "github.com resolves successfully"

        else

            health_fail \
                "DNS" \
                "Unable to resolve github.com"
        fi

    else

        health_skip \
            "DNS" \
            "getent is not available"
    fi


    # ==========================================================================
    # 3. OUTBOUND HTTPS
    # ==========================================================================
    #
    # DNS resolution alone does not prove that HTTPS traffic can leave the
    # server.
    #
    # Our infrastructure depends on outbound HTTPS for things such as:
    #
    #     - GitHub
    #     - package repositories
    #     - Docker registries
    #     - external APIs
    #
    # We use GitHub as a simple connectivity target because the infrastructure
    # already depends on it.
    # ==========================================================================

    # --------------------------------------------------------------------------
    # `curl`
    #     HTTP command-line client.
    #
    # Options:
    #
    # --silent
    #     Suppress progress output.
    #
    # --show-error
    #     Still show an error if the request fails.
    #
    # --fail
    #     Return a non-zero exit code for HTTP error responses.
    #
    # --max-time 10
    #     Do not wait longer than 10 seconds.
    #
    # --output /dev/null
    #     Discard the response body because we only care whether the request
    #     succeeds.
    # --------------------------------------------------------------------------
    if ! command -v curl >/dev/null 2>&1; then

        health_skip \
            "Outbound HTTPS" \
            "curl is not installed"

        return 0
    fi


    if curl \
        --silent \
        --show-error \
        --fail \
        --max-time 10 \
        --output /dev/null \
        https://github.com; then

        health_pass \
            "Outbound HTTPS" \
            "github.com is reachable"

        return 0
    fi


    # --------------------------------------------------------------------------
    # We use WARN instead of FAIL here.
    #
    # Why?
    #
    # A server may intentionally have restricted outbound internet access while
    # still being otherwise operational.
    #
    # Once we define stricter server roles/configuration, we can decide whether
    # particular machines require outbound HTTPS and promote this to FAIL there.
    # --------------------------------------------------------------------------
    health_warn \
        "Outbound HTTPS" \
        "Unable to reach github.com"

    return 0
}

# ==============================================================================
# check_lvm
# ==============================================================================
#
# Purpose:
#     Detect whether the server uses Linux LVM and verify that LVM metadata
#     can be read successfully.
#
# Why LVM matters in our environment:
#
#     stoleusstorage uses LVM for volumes such as:
#
#         /
#         /var/lib/docker
#         /var/lib/postgresql
#
#     stoleusstage also uses LVM.
#
#     stoleusapp currently uses normal disk partitions instead of LVM.
#
# Therefore:
#
#     LVM tools missing       -> SKIP
#     LVM tools installed,
#     but no physical volume  -> SKIP
#     LVM detected/readable   -> PASS
#
# This is intentionally a basic health check for now.
#
# Later we can extend it to inspect:
#
#     - free space in volume groups
#     - logical volume state
#     - thin pools
#     - snapshots
#     - missing physical volumes
#
# This function is READ-ONLY.
# ==============================================================================

check_logical_volume_manager() {

    # --------------------------------------------------------------------------
    # `lsblk` can identify LVM logical volumes without requiring root.
    #
    # Example TYPE values:
    #
    #     disk
    #     part
    #     lvm
    #
    # This gives us a safe first-level check even during a manual health run as
    # the deployer user.
    # --------------------------------------------------------------------------
    if command -v lsblk >/dev/null 2>&1; then

        if ! lsblk -rno TYPE 2>/dev/null | grep -qx 'lvm'; then

            health_skip \
                "LVM" \
                "Server does not use LVM"

            return 0
        fi
    else

        # Without lsblk we can only continue if the normal LVM tools exist.
        if ! command -v pvs >/dev/null 2>&1 ||
           ! command -v vgs >/dev/null 2>&1 ||
           ! command -v lvs >/dev/null 2>&1; then

            health_skip \
                "LVM" \
                "LVM inspection tools are not available"

            return 0
        fi
    fi


    # --------------------------------------------------------------------------
    # At this point LVM is present.
    #
    # The detailed pvs/vgs/lvs metadata scan can require elevated privileges on
    # some Linux configurations. A normal-user health run should not falsely
    # report storage corruption merely because the user cannot open block
    # devices or LVM lock files.
    # --------------------------------------------------------------------------
    if (( EUID != 0 )); then

        health_pass \
            "LVM" \
            "LVM volumes detected; deep metadata check requires root"

        return 0
    fi


    # --------------------------------------------------------------------------
    # A root health run should have the standard LVM administration tools.
    # --------------------------------------------------------------------------
    if ! command -v pvs >/dev/null 2>&1 ||
       ! command -v vgs >/dev/null 2>&1 ||
       ! command -v lvs >/dev/null 2>&1; then

        health_warn \
            "LVM" \
            "LVM detected but pvs/vgs/lvs tools are missing"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Perform the deeper metadata validation only when running as root.
    # --------------------------------------------------------------------------
    if ! pvs >/dev/null 2>&1 ||
       ! vgs >/dev/null 2>&1 ||
       ! lvs >/dev/null 2>&1; then

        health_fail \
            "LVM" \
            "LVM metadata could not be read"

        return 0
    fi


    health_pass \
        "LVM" \
        "LVM volumes detected and metadata is readable"

    return 0
}

# Backward-compatible shorter alias. Either function name can be used by
# commands/health.sh while we gradually standardize naming.
check_lvm() {
    check_logical_volume_manager
}
