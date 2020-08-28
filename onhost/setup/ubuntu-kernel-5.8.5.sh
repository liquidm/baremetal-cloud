#!/bin/bash

# install boot loaders
spawn_chroot "DEBIAN_FRONTEND=noninteractive apt-get -y install extlinux grub-efi-amd64"

# fetch and install kernel via ubuntu ppa
mkdir -p /mnt/baremetal/root/kernel-5.8.5
cd /mnt/baremetal/root/kernel-5.8.5

wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.8.5/amd64/linux-headers-5.8.5-050805-generic_5.8.5-050805.202008270831_amd64.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.8.5/amd64/linux-headers-5.8.5-050805_5.8.5-050805.202008270831_all.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.8.5/amd64/linux-image-unsigned-5.8.5-050805-generic_5.8.5-050805.202008270831_amd64.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.8.5/amd64/linux-modules-5.8.5-050805-generic_5.8.5-050805.202008270831_amd64.deb
spawn_chroot "dpkg -i /root/kernel-5.8.5/*.deb"
