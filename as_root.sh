#!/bin/bash

set -e

# are these borked?

# keep track of the last executed command
#trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
#trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT


cores=$(nproc)

kernel_version=$(cat linux-version)
busybox_version=$(cat busybox-version)
bash_version=$(cat bash-version)

base=$(pwd)

tgt=$(losetup -P -f --show ikeda)
mkdir ikeda_mount
mkfs.ext4 ${tgt}p1
mount ${tgt}p1 ikeda_mount

echo "Making raw filesystem"

pushd ikeda_mount

mkdir -p usr/{sbin,bin} bin sbin boot
mkdir -p {dev,etc,home,lib,mnt,opt,proc,srv,sys,run}
mkdir -p var/{lib,lock,log,run,spool,cache}
install -d -m 0750 root
install -d -m 1777 tmp
mkdir -p usr/{include,lib,share,src,local}

#ln -s bin/bash usr/bin/zsh

echo "Copying linux-${kernel_version} and busybox-${busybox_version}"
cp ../linux-${kernel_version}/arch/x86_64/boot/bzImage boot/bzImage

cp ../busybox-${busybox_version}/busybox usr/bin/busybox
for util in $(./usr/bin/busybox --list-full); do
    ln -s /usr/bin/busybox $util
    echo "linked busybox to $util"

    echo "$util" >> ${base}/things_linked.txt

done

#mkdir -p usr/share/udhcpc
#cp -rv ../busybox-${busybox_version}/examples/udhcp/* usr/share/udhcpc/.

echo "Installing musl-${musl_version} . . ."
cp -r ../musl-out/* usr/.

echo "Installing bash-${bash_version} . . ."
cp -rv ../bash-${bash_version}/out/* usr/.

echo "Unpacking statically prebuilt zsh . . ."
pushd usr
curl -LO https://github.com/romkatv/zsh-bin/releases/download/v6.0.0/zsh-5.8-linux-x86_64.tar.gz
tar -xf zsh-5.8-linux-x86_64.tar.gz
rm zsh-5.8-linux-x86_64.tar.gz
# pop out of usr
popd

# pop out of mountpoint
popd

echo "Final filesystem setup"
cp -r filesystem/* ikeda_mount/.
chmod -R -x ikeda_mount/etc/*
chmod +x ikeda_mount/etc/startup

# unknown if needed?
partuuid=$(fdisk -l ../ikeda | grep "Disk identifier" | awk '{split($0,a,": "); print a[2]}' | sed 's/0x//g')
cp limine/limine.sys ikeda_mount/boot/. -v
sed -i "s/something/${partuuid}/g" ikeda_mount/boot/limine.cfg

printf "Would you like a RootFS tarball? (y/N): "
read RFS

if [[ "$RFS" == "y" ]]; then
    if [[ -f ikeda.tar.gz ]]; then
        rm ikeda.tar.gz
    fi
    pushd ikeda_mount && tar -cvzf ../ikeda.tar.gz * && popd
fi


if [ -d ikeda_mount ]; then
    findmnt | grep ikeda
    if [[ "$?" == "0" ]]; then
        umount ikeda_mount
    fi
    rm ikeda_mount -rf
fi

cd ${base}
echo "we're in $(pwd)"