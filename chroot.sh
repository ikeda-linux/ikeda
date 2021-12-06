#!/bin/bash
set -e

tgt=$(losetup -P -f --show ikeda)
mkdir ikeda_mount
mount ${tgt}p1 ikeda_mount

chroot ikeda_mount /usr/bin/zsh

umount ikeda_mount
losetup -D