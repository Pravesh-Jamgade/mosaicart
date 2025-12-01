# Linux prototype of Mosaic Pages

This directory contains the Linux prototype implementation of Mosaic Pages for ASPLOS'23.
The scripts provided here are used to reproduce Tables 3 and 4 from the paper.
The instruction presents how to run the experiments in KVM.


## System Requirements

* A Linux system
  * More than 2 cores
  * At least 12GB of free RAM

## Our System Configuration in Paper

* Intel Xeon E3-1220 processor with 4 cores
* 32GB RAM
* Ubuntu 20.04

## Build Instruction

We provide a script to download and build Linux kernel version 5.11.6 with and without the Mosaic patch.
The script will apply the Mosaic patch and build two kernels, Mosaic and vanilla.
We also provide kernel config for KVM. For custom configuration, Mosaic requires `CONFIG_MEMORY_FAILURE` and `CONFIG_MEMCG` enabled.
```
$ ./get_kernel.sh
```

## Create a VM Image

This script will create a 10GB VM image and copy workload binaries and scripts in the home directory.
```
$ ./create_kvm_disk.sh
```

If the command fails, verify that `qemu-img`, `debootstrap`, and `sudo` are installed and that you have at least 15GB of free disk space plus 12GB of available RAM for the build. The preflight script below will report any missing prerequisites before you start a long download/build step.

## Run KVM

```
$ ./run-qemu.sh [option]
```
OPTIONS
* -w Run KVM with disk read/write mode
* -v Run KVM vanilla kernel.

## Run Experiments

First, launch KVM with vanilla kernel and perform experiments.
Then, shut down the VM.
```
$ ./run-qemu.sh -wv
KVM $ ./run-cgroup.sh
KVM $ sudo shutdown -h now
```
Second, launch KVM with Mosaic kernel and perform experiments, and shut down the VM.
```
$ ./run-qemu.sh -w
KVM $ ./run-mosaic.sh
KVM $ sudo shutdown -h now
```

## Generate Tables from the Results

We will copy the home directory of the VM and generate tables in CSV format.
The final tables are available as `homedir/table3.csv` and `homedir/table4.csv`
```
$ ./copy_kvm_homedir.sh
$ cd homedir
$ ./process.sh
$ cat table3.csv
$ cat table4.csv
```

## Troubleshooting when the VM fails to start

Run a quick environment preflight from the repo root:
```
$ ./verify_environment.sh
```

The script checks that `qemu-img`, `qemu-system-x86_64`, and `debootstrap` are installed, confirms `/dev/kvm` is available, and ensures you have enough free disk and memory to create the VM image. Resolve any reported issues (e.g., install the missing package or enable KVM) and re-run the check before retrying `create_kvm_disk.sh` or `run-qemu.sh`.
