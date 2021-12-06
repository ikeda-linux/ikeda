#!/bin/bash

set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

rootdir=$(pwd)

if [[ ! -d build ]]; then
    ./clean.sh
fi

pushd build
builddir=$(pwd)

cores=$(nproc)

kernel_version=$(cat linux-version)
busybox_version=$(cat busybox-version)
bash_version=$(cat bash-version)

ncurses_version=$(cat ncurses-version)

# check `musl.config.mak` for MUSL toolchain versions

printsection() {
    echo "----------"
    echo "$1"
    echo "----------"
}

getfirmware() {
    echo "Ensuring firmware archive"
    if [[ ! -f .firmwaredownloaded ]]; then
        wget $(cat ${builddir}/firmware-url) -O firmware.tgz
        tar -xvf firmware.tgz
        rm firmware.tgz
        touch .firmwaredownloaded
    fi
}

installfirmware() {
    getfirmware

    printsection "Installing firmware to fs root"

    pushd linux-firmware*/

    make DESTDIR=${builddir}/filesystem/ install

    popd

}

getlinux() {
	echo "Getting kernel source"
	if [ ! -f linux-${kernel_version}.tar.xz ]; then
		wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${kernel_version}.tar.xz
	fi

	if [ -d linux-${kernel_version} ]; then
		rm -rf linux-${kernel_version}
	fi

	tar -xvf linux-${kernel_version}.tar.xz

}

makekernel() {

    printsection "Making Kernel"

    if [ ! -d linux-${kernel_version} ]; then
        echo "Ensuring source"
        getlinux
    fi

    if [ ! -f linux-${kernel_version}/arch/x86_64/boot/bzImage ]; then
        echo "Doing build."
        cd linux-${kernel_version}

        echo "Building"
        if [[ -f ${builddir}/qemu-yes ]]; then
            echo "Applying default config (VM/QEMU)"
            make defconfig
            # this ensures anything that *would* be a module is built-in by def (vv)
            sed "s/=m/=y/g" -i .config
            echo "Building kernel."
            time make -j${cores}
        else
            echo "Using Archlinux config"
            # this ensures anything that *would* be a module is built-in by def (vv)
            sed "s/=m/=y/g" -i .config
            cp ../k-config .config
            echo "Building kernel."
            time make all -j${cores}
        fi

        if [[ ! -f ${builddir}/qemu-yes ]]; then
            sed "s/=m/=y/g" -i .config
            cp .config ../k-config
            cp .config ../../src/k-config #TODO: add a flag for this in future?
        fi

        cd ../
    else
        echo "Kernel exists. Not rebuilding."
        echo "Delete linux-${kernel_version}/arch/x86_64/boot/bzImage to force a rebuild."
    fi

}

getbusybox() {
	echo "Ensuring busybox"
	if [[ ! -f busybox-${busybox_version}.tar.bz2 ]]; then
		wget https://busybox.net/downloads/busybox-${busybox_version}.tar.bz2
	fi

	if [ -d busybox-${busybox_version} ]; then
		rm -rf busybox-${busybox_version}
	fi

	tar -xf busybox-${busybox_version}.tar.bz2

}

buildbusybox() {

    printsection "Making BusyBox"

    if [ ! -f busybox-${busybox_version}/busybox ]; then
        if [ ! -d busybox-${busybox_version} ]; then
            getbusybox
        fi

        if [ -d kernel-headers ]; then
            pushd kernel-headers && git pull && popd
        else
            git clone https://github.com/sabotage-linux/kernel-headers
        fi

        cp bb-config busybox-${busybox_version}/.config
        pushd busybox-${busybox_version} && make CC=musl-gcc && cp .config ../bb-config && popd

    else
        echo "Not building BusyBox (program exists)"
        echo "Delete busybox-${busybox_version}/busybox to force a rebuild."
    fi

}

getbash() {
    printsection "Fetching bash"

    if [ ! -d bash-${bash_version} ]; then
        wget https://ftp.gnu.org/gnu/bash/bash-${bash_version}.tar.gz
    fi

    tar -xf bash-${bash_version}.tar.gz

}

buildbash() {
    printsection "Building bash"

    if [ ! -d bash-${bash_version} ]; then
        getbash
    fi
    if [ ! -f bash-${bash_version}/out/bin/bash ]; then
        pushd bash-${bash_version} && CC="musl-gcc -static" ./configure --without-bash-malloc --prefix="$(pwd)/out" && make && make install && popd
    fi

}

ensure_musl() {
    printsection "Checking MUSL source"

    if [ ! -d musl-cross-make ]; then
        git clone https://github.com/richfelker/musl-cross-make
    else
        pushd musl-cross-make && git pull && popd
    fi
}

musl() {
    printsection "Making MUSL"
    ensure_musl

    FP="$PWD/musl-out"
    cp musl.config.mak musl-cross-make/config.mak
    sed -i "s|SOMEPATHHERE|$FP|g" musl-cross-make/config.mak

    if [ ! -d musl-out ]; then
        mkdir musl-out
        pushd musl-cross-make
        make -j${cores}
        make install
        popd
    else
        echo "Not rebuilding MUSL stuff"
    fi

}

sg() {
    echo "We're in $PWD"
    if [[ -f static-get ]]; then
        rm static-get
    fi
    curl -LO https://raw.githubusercontent.com/minos-org/minos-static/master/static-get
    chmod +x static-get

    if [[ ! -f ../sg-targets ]]; then
        echo "Not using static-get for anything"
    else
        pushd filesystem/usr
        for tgt in $(cat ${rootdir}/sg-targets); do
            echo "Getting $tgt"
            ../../static-get $tgt
            tar -xvf *tar*
            rm *tar*
        done
        popd
    fi

    cp static-get filesystem/usr/bin/.

}

rustysd() {

    # I would love to not clone out of tree, but for some reason that's the only way it works
    
    if [[ ! -d ~/rustysd ]]; then
        git clone git@git.tar.black:ikeda/rustysd.git ~/rustysd
    else
        pushd ~/rustysd && git pull && popd
    fi

    pushd ~/rustysd

    cargo build --target=x86_64-unknown-linux-musl --release
    
    popd

    cp ~/rustysd/target/x86_64-unknown-linux-musl/release/rustysd filesystem/bin/.
    cp ~/rustysd/target/x86_64-unknown-linux-musl/release/rsdctl filesystem/bin/.

}

66() {
    if [[ ! -d 66 ]]; then
        git clone https://framagit.org/Obarun/66/
    fi

    pushd 66
    ./build_toolchain.sh
    ./configure --enable-static-libc --prefix=${thisdir}/filesystem
    make
    make install
    popd 
}

ncurses() {

    thisdir=$(pwd)

    if [[ ! -d ncurses-${ncurses_version} ]]; then
        wget https://invisible-mirror.net/archives/ncurses/ncurses-${ncurses_version}.tar.gz
        tar -xvf ncurses-${ncurses_version}.tar.gz
        rm ncurses-${ncurses_version}.tar.gz
    fi
    
    pushd ncurses-${ncurses_version}
    ./configure --prefix=${thisdir}/filesystem/usr --with-shared --without-debug
    make
    make install
    popd



    mkdir -p filesystem/usr/{lib,share}
    cp -rv /usr/lib/terminfo filesystem/usr/lib/.
    cp -rv /usr/share/terminfo filesystem/usr/share/.

}

notools() {
    mkdir -p filesystem/usr/bin

    # nofetch
    wget https://git.tar.black/notools/nofetch/-/raw/master/nofetch
    chmod +x nofetch
    mv nofetch filesystem/usr/bin

    #notop
    wget https://git.tar.black/notools/notop/-/raw/master/notop
    chmod +x notop
    mv notop filesystem/usr/bin
}

image() {
    makekernel
    buildbusybox
    buildbash
    musl
    sg
    # rustysd
    66
    ncurses
    notools

    if [[ ! -f firmware-no ]]; then
        installfirmware
    fi

    printsection "Making final image"

    if [ -d ikeda_mount ]; then
        sudo rm ikeda_mount -rf
    fi

    if [ -f ikeda ]; then
        rm ikeda
    fi

    echo "Making Ikeda Linux image"

    if [[ ! -f firmware-no ]]; then
        # linux firmware is *chunky* also so is the kernel
        fallocate -l3000M ikeda
    else
        # should fit w/o firmware and w/o arch kernel
        fallocate -l1500M ikeda 
    fi
	
    parted ikeda mklabel msdos --script
    parted --script ikeda 'mkpart primary ext4 1 -1' 

	sudo ./as_root.sh

}

test() {

    if [[ "$1" == "qemu" ]]; then
        touch qemu-yes
    fi

    if [[ ! -f ikeda ]]; then
        image
    fi

    if [[ "$2" == "-ng" ]]; then
        qemu-system-x86_64 -enable-kvm -nographic ikeda
    else
        qemu-system-x86_64 -enable-kvm ikeda
    fi
}

test "$@"

popd