#!/usr/bin/env bash
set -euo pipefail

MISSING=()
ERRORS=()

section() {
  echo "\n=== $1 ==="
}

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[OK] $cmd found at $(command -v "$cmd")"
  else
    echo "[MISSING] $cmd"
    MISSING+=("$cmd")
  fi
}

check_disk_space() {
  section "Disk space"
  local available_gb
  available_gb=$(df -PB1G . | awk 'NR==2 {print $4}')
  echo "Available space: ${available_gb}G"
  if [[ ${available_gb} -lt 15 ]]; then
    ERRORS+=("At least 15G free disk space recommended; only ${available_gb}G available.")
  fi
}

check_memory() {
  section "Memory"
  local available_kb available_gb
  available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
  available_gb=$(awk -v kb="$available_kb" 'BEGIN {printf "%.1f", kb/1024/1024}')
  echo "Available memory: ${available_gb}G"
  local threshold_kb=$((12*1024*1024))
  if [[ $available_kb -lt $threshold_kb ]]; then
    ERRORS+=("At least 12G available memory recommended; only ${available_gb}G detected.")
  fi
}

check_virtualization() {
  section "Virtualization"
  if [[ -c /dev/kvm ]]; then
    echo "[OK] /dev/kvm present"
  else
    echo "[WARN] /dev/kvm not present"
    if grep -Eiq 'vmx|svm' /proc/cpuinfo; then
      echo "CPU virtualization flags detected, but KVM device missing (is kvm module loaded?)."
      ERRORS+=("/dev/kvm missing; ensure KVM modules are loaded and user has permissions.")
    else
      ERRORS+=("No hardware virtualization flags detected; KVM acceleration may be unavailable.")
    fi
  fi
}

check_required_commands() {
  section "Required commands"
  check_cmd qemu-img
  check_cmd qemu-system-x86_64
  check_cmd debootstrap
  check_cmd sudo
}

summarize() {
  section "Summary"
  if (( ${#MISSING[@]} > 0 )); then
    echo "Missing commands: ${MISSING[*]}"
  else
    echo "All required commands found."
  fi

  if (( ${#ERRORS[@]} > 0 )); then
    printf "Issues detected:\n"
    for issue in "${ERRORS[@]}"; do
      echo " - $issue"
    done
    exit 1
  else
    echo "No blocking issues detected."
  fi
}

check_required_commands
check_disk_space
check_memory
check_virtualization
summarize
