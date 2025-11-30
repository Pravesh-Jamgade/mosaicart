#!/bin/bash

while getopts wv opt; do
    case $opt in
        w) opt_rw="SET"
        ;;
        v) opt_vanilla="SET"
        ;;
    esac
done

if [[ "$opt_rw" = "SET" ]]; then
    SNAPSHOT=""
else
    SNAPSHOT="-snapshot"
fi

CONSOLE="console=tty1 highres=off $SERIAL_APPEND"
ROOT="root=/dev/sda rw --no-log"
NCPUS=2

if [[ "$opt_vanilla" = "SET" ]]; then
    KERNEL=/media/pravesh/Storage/code/sims/kdev/linux-5.15.180/arch/x86_64/boot/bzImage
else
    KERNEL=/media/pravesh/Storage/code/sims/kdev/linux/arch/x86_64/boot/bzImage
fi

set -x

qemu-system-x86_64 -enable-kvm -cpu host -m 12G -smp $NCPUS -hda disk.img -kernel $KERNEL \
	-append "nokaslr $CONSOLE $ROOT" \
	-nographic $SNAPSHOT $SERIAL


# qemu-system-x86_64 \
#   -enable-kvm \
#   -cpu host \
#   -m 2048 \
#   -smp 2 \
#   -hda disk.img \
#   -kernel /media/pravesh/Storage/code/sims/kdev/linux/arch/x86_64/boot/bzImage
#   -append "root=/dev/sda console=ttyS0 nokaslr rw" \
#   -nographic