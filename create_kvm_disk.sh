#!/bin/bash

###############################################################################
# This script builds a bootable Ubuntu disk image for the Mosaic KVM VM.
# The comments explain **every step and syntax choice** so you can replicate
# or adapt the process when writing your own image builder.
###############################################################################

# Name of the raw disk image that QEMU will boot. Using a variable makes it
# easy to change the output filename without touching the rest of the script.
DISK="disk.img"

# Requested disk size. qemu-img uses suffixes like G for gigabytes, so "10G"
# creates a 10‑gigabyte sparse file.
SIZE="10G"

# Temporary mount point for assembling the filesystem. `mktemp -d` creates a
# unique directory securely to avoid collisions with other runs.
MNTPNT=`mktemp -d`

# Base OS and architecture fed into debootstrap. "focal" is Ubuntu 20.04 and
# "amd64" targets x86_64 hosts.
OS="focal"
ARCH="amd64"

# Kernel release from the build host. Not directly used later, but recorded so
# you can reuse the host version if needed.
KERNEL=`uname -r`

# VM login credentials used by the provided workload scripts.
USER=oscar
PASS=oscar

# Serial console device configured for the VM. ttyS0 maps to QEMU's serial
# console to keep all I/O on the terminal when running with -nographic.
TTYS=ttyS0

# Directory containing prebuilt binaries, bootscripts, and workloads to copy
# into the guest image.
VMFILES="vmfiles"

# Build the BUSE example binary inside vmfiles/BUSE so it can be copied into
# the guest later. (The git clone is commented out because the repo already
# exists in-tree.)
# git clone https://github.com/acozzette/BUSE.git vmfiles/BUSE
make -C vmfiles/BUSE busexmp


# Helper that cleans up mounts/disk on failure. The M1/M0/D0 flags track which
# resources were created so we only tear down what exists.
function fail {
        [ "$M1" = "1" ] && sudo umount $MNTPNT/dev
        [ "$M0" = "1" ] && sudo umount $MNTPNT
        [ "$D0" = "1" ] && rm $DISK
        rmdir $MNTPNT
        exit $1
}

# Wrapper to echo the command, run it, and abort via fail() on nonzero exit.
# This keeps the script readable while still stopping early on errors.
function run {
        echo "$@"
        "$@"
        if [ $? != 0 ]; then
                echo "Failed [$*]"
                fail $?
        fi
}

# Create a sparse raw disk image. We set D0=1 after success so fail() knows to
# delete the file if a later step fails.
run qemu-img create -f raw $DISK $SIZE; D0=1

# Format the raw file with ext4 so the guest can mount it as /dev/sda.
run mkfs.ext4 -F $DISK

# Mount the image via loopback so we can populate it like a normal filesystem.
run sudo mkdir -p $MNTPNT
run sudo mount -o loop $DISK $MNTPNT; M0=1

# Bootstrap a minimal Ubuntu root filesystem into the mounted image.
run sudo debootstrap --arch $ARCH $OS $MNTPNT

# Copy helper: rsync preserves attributes and writes in-place to avoid extra
# copies. The ${f%/*} expansion strips the filename to reuse the source
# directory structure inside the target mount.
function copy_files {
        for f in $*
        do
                run sudo rsync -a --inplace $f $MNTPNT/${f%/*}
                # Alternative: plain cp -r (kept for reference)
                # run sudo cp -r $f $MNTPNT/${f%/*}
        done
}


# Prepare /dev inside the chroot so debootstrap-created system services see
# device nodes. The bind mount mirrors the host /dev into the image.
run sudo mkdir -p $MNTPNT/dev
run sudo mount --bind /dev/ $MNTPNT/dev; M1=1

# Convenience wrapper to run commands inside the new root. Quotes ensure the
# full command string is passed as-is to chroot.
function chroot_run {
        run sudo chroot $MNTPNT "$@"
}

# Disable unused TTYs to keep console noise down when running headless.
chroot_run rm -f /etc/init/tty[2345678].conf
chroot_run sed -i "s:/dev/tty\\[1-[2-8]\\]:/dev/tty1:g" /etc/default/console-setup

# Create the default user with no initial password, then set a known password
# so scripts can log in automatically.
chroot_run adduser $USER --disabled-password --gecos ""
chroot_run bash -c "echo "$USER:$PASS" | chpasswd"

# Force getty on the serial console to auto-login the user for non-interactive
# runs. The sed replacement rewrites ExecStart in the template unit.
chroot_run sed -i "s/^ExecStart.*$/ExecStart=-\/sbin\/agetty --noissue --autologin oscar %I $TERM/g" /lib/systemd/system/getty@.service

# Allow passwordless sudo so automation can escalate without prompts.
chroot_run sed -i "/User privilege specification/a oscar\tALL=(ALL) NOPASSWD:ALL" /etc/sudoers


# Copy workload binaries, boot-time scripts, and experiment assets into the
# guest home directory. These mirror the repo layout so they can be found by
# the provided run scripts.
run sudo cp $VMFILES/BUSE/busexmp $MNTPNT/usr/local/bin/
run sudo cp $VMFILES/bootscripts/*.sh $MNTPNT/etc/profile.d/
run sudo cp $VMFILES/scripts/*.sh $MNTPNT/home/$USER/
run sudo cp $VMFILES/scripts/*.py $MNTPNT/home/$USER/
run sudo cp -r $VMFILES/apps $MNTPNT/home/$USER/
chroot_run chown -R oscar:oscar /home/$USER/

# Install runtime dependencies used by the workloads (sysstat for iostat,
# psmisc for killall, libgomp1 for OpenMP apps, screen for session management).
chroot_run apt-get update
chroot_run apt-get install --yes sysstat psmisc
chroot_run apt-get install --yes libgomp1
chroot_run apt-get install --yes screen
# Additional build/tool packages kept here as comments for optional installs.
# chroot_run apt-get install --yes build-essential autoconf
# chroot_run apt-get install --yes initramfs-tools
# chroot_run apt-get install --yes time
# chroot_run apt-get install --yes vim


# Provision swap inside the guest to ensure memory-heavy benchmarks have room
# to run even on hosts with constrained RAM. The fstab entry re-enables it on
# every boot.
chroot_run fallocate -l 2G /swapfile
chroot_run chmod 600 /swapfile
chroot_run mkswap /swapfile
chroot_run swapon /swapfile
# The echo command appends a persistent fstab entry for the swapfile.
chroot_run bash -c "echo '/swapfile none swap sw 0 0' >> /etc/fstab"


# Clean shutdown path: unmount bind mounts and the root filesystem even if
# processes are still running inside the chroot, then delete the temp directory.
function cleanup_mount {
  echo "Cleaning up mount: $MNTPNT"

  # Kill any chroot-related process that might still be alive to prevent busy
  # mount errors. fuser returns nonzero if nothing is running, so we ignore
  # failures with `|| true`.
  sudo fuser -k $MNTPNT || true

  # Unmount /dev first, then the root, using lazy unmount (-l) as a fallback
  # to detach even if something still holds a reference.
  if mountpoint -q "$MNTPNT/dev"; then
    sudo umount "$MNTPNT/dev" || sudo umount -l "$MNTPNT/dev"
  fi

  if mountpoint -q "$MNTPNT"; then
    sudo umount "$MNTPNT" || sudo umount -l "$MNTPNT"
  fi

  # Finally remove the temporary directory to leave no trace on the host.
  sudo rm -rf "$MNTPNT"
}

# Always attempt cleanup at the end of the run.
cleanup_mount
