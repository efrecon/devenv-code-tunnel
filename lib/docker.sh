#!/bin/sh

# Note: This is a library, not a standalone script. It is meant to be sourced
# from other scripts.

is_privileged() {
  # Get the capability bounding set
  cap_bnd=$(grep '^CapBnd:' /proc/$$/status | awk '{print $2}')
  # Convert to decimal
  cap_bnd=$(printf "%d" "0x${cap_bnd}")

  # Get the last capability number
  last_cap=$(cat /proc/sys/kernel/cap_last_cap)

  # Calculate the maximum capability value
  max_cap=$(((1 << (last_cap + 1)) - 1))

  if [ "${cap_bnd}" -eq "${max_cap}" ]; then
    verbose "Container is running in privileged mode."
    return 0
  else
    verbose "Container is not running in privileged mode."
    return 1
  fi
}