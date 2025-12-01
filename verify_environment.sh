#!/usr/bin/env bash
# Preflight checker to verify the host can build and run the Mosaic VM environment.
# Exits non-zero if blocking issues are found so users know what to fix first.

set -euo pipefail                        # "-e" aborts on errors, "-u" aborts on unset variables, and "pipefail" propagates pipeline failures, so the script halts on any unexpected condition.

MISSING=()                               # Declare an empty bash array (using parentheses) to collect missing commands.
ERRORS=()                                # Declare another array to collect resource/KVM problems encountered during checks.

section() {                              # Define a function (name followed by parentheses) that prints section headers.
  echo "\n=== $1 ==="                     # "\n" prints a blank line; "$1" expands the function's first argument inside the echoed header.
}

check_cmd() {                            # Define a function that validates a command's presence in PATH.
  local cmd="$1"                        # "local" limits the variable scope to the function; "$1" captures the command name argument.
  if command -v "$cmd" >/dev/null 2>&1; then   # "command -v" resolves the executable path; redirection hides output while the "if" tests success.
    echo "[OK] $cmd found at $(command -v "$cmd")"   # Command substitution "$(...)" embeds the resolved path within the message.
  else
    echo "[MISSING] $cmd"               # Mark the command as absent so the user knows what to install.
    MISSING+=("$cmd")                   # The "+=" operator appends the missing command to the MISSING array.
  fi
}

check_disk_space() {                     # Function to ensure sufficient free disk space.
  section "Disk space"                  # Invoke section() with a quoted string to avoid word-splitting.
  local available_gb                     # Declare a local variable to store free space as an integer.
  available_gb=$(df -PB1G . | awk 'NR==2 {print $4}')   # Command substitution runs "df" with block size in GiB, pipes to awk to pick the free-space column.
  echo "Available space: ${available_gb}G"             # "${var}" expands the variable within the string; braces clarify the boundary before the trailing "G".
  if [[ ${available_gb} -lt 15 ]]; then  # "[[ ... ]]" performs a bash test; "-lt" compares integers for less-than.
    ERRORS+=("At least 15G free disk space recommended; only ${available_gb}G available.")  # Append a descriptive error if below threshold.
  fi
}

check_memory() {                         # Function to confirm enough RAM exists.
  section "Memory"                      # Print a labeled section header.
  local available_kb available_gb        # Declare two locals on one line for raw and converted memory values.
  available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')   # Use grep to select MemAvailable and awk to print the numeric kilobyte value.
  available_gb=$(awk -v kb="$available_kb" 'BEGIN {printf "%.1f", kb/1024/1024}')  # Pass the kB via "-v" into awk and format to one decimal gigabytes.
  echo "Available memory: ${available_gb}G"           # Echo the computed gigabyte figure for transparency.
  local threshold_kb=$((12*1024*1024))   # Arithmetic expansion "$((...))" calculates the 12 GiB threshold in kilobytes.
  if [[ $available_kb -lt $threshold_kb ]]; then  # Compare the available kB against the threshold using bash's numeric test.
    ERRORS+=("At least 12G available memory recommended; only ${available_gb}G detected.")  # Record a blocking issue when memory is short.
  fi
}

check_virtualization() {                 # Function to verify KVM hardware acceleration is usable.
  section "Virtualization"              # Print the section header.
  if [[ -c /dev/kvm ]]; then             # The "-c" file test checks whether the KVM character device exists.
    echo "[OK] /dev/kvm present"        # Success message when the device node is available.
  else
    echo "[WARN] /dev/kvm not present"  # Warn that KVM may be unusable.
    if grep -Eiq 'vmx|svm' /proc/cpuinfo; then   # "grep -E" uses extended regex to find Intel/AMD virtualization flags; "-i" ignores case, "-q" suppresses output for boolean use.
      echo "CPU virtualization flags detected, but KVM device missing (is kvm module loaded?)."   # Hardware appears capable but kernel/module configuration may be missing.
      ERRORS+=("/dev/kvm missing; ensure KVM modules are loaded and user has permissions.")        # Add actionable guidance to the ERRORS array.
    else
      ERRORS+=("No hardware virtualization flags detected; KVM acceleration may be unavailable.")  # Add a different error when CPU flags are absent.
    fi
  fi
}

check_required_commands() {              # Function to check the presence of all external tools used by the build/run scripts.
  section "Required commands"           # Emit a section header for clarity.
  check_cmd qemu-img                     # Test for "qemu-img" (disk image manipulation tool).
  check_cmd qemu-system-x86_64           # Test for the QEMU binary used to boot the VM with KVM.
  check_cmd debootstrap                  # Test for debootstrap, which builds the Ubuntu VM image.
  check_cmd sudo                         # Test for sudo, required by create_kvm_disk.sh during privileged steps.
}

summarize() {                            # Function to print a closing summary and set the exit code.
  section "Summary"                     # Separate summary output from preceding checks.
  if (( ${#MISSING[@]} > 0 )); then      # Arithmetic context "(( ))" retrieves the array length via "${#array[@]}" to see if anything is missing.
    echo "Missing commands: ${MISSING[*]}"   # "${array[*]}" expands all elements space-separated for user readability.
  else
    echo "All required commands found."      # Positive confirmation when nothing is missing.
  fi

  if (( ${#ERRORS[@]} > 0 )); then       # Reuse arithmetic test to see if any blocking issues were recorded.
    printf "Issues detected:\n"             # printf with "\n" prints a newline and avoids adding an extra one automatically.
    for issue in "${ERRORS[@]}"; do    # A "for" loop iterates over each stored error string; quoting preserves spaces.
      echo " - $issue"                    # Prefix each issue for easy scanning.
    done
    exit 1                                # Exit non-zero so callers/CI can treat failures as blocking.
  else
    echo "No blocking issues detected."    # All checks passed; safe to proceed.
  fi
}

check_required_commands                  # Invoke the functions in order; bare names execute the defined bash functions.
check_disk_space                          # Ensure enough free space exists for images and build artifacts.
check_memory                              # Confirm adequate RAM is available for builds and VM execution.
check_virtualization                      # Verify hardware virtualization/KVM is ready.
summarize                                 # Present results and exit appropriately.
