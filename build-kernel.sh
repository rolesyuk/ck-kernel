#!/bin/bash

#DEPENDENCIES="kernel-package libncurses5 libncurses5-dev build-essential patch fakeroot bc"

KERNEL_MAJOR="4.1"
KERNEL_MINOR="11"
BFS="ck2"
BFQ="v7r8"
PREEMPT_RT=

#CROSS_COMPILER_PREFIX=$(readlink -f $(dirname $0)/gcc-linaro-4.9-2014.11-x86_64_arm-linux-gnueabihf/bin)/arm-linux-gnueabihf-

CONFIG="config-3.19.0-31-generic"

big_echo() {
	echo
	echo -e '\033[01;32m'"${1}"'\033[00m'
	echo
}

big_echo "Downloading vanilla kernel ${KERNEL_MAJOR}.${KERNEL_MINOR} ..."
wget -nc "https://www.kernel.org/pub/linux/kernel/v4.x/linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar.xz" || exit 1
wget -nc "https://www.kernel.org/pub/linux/kernel/v4.x/linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar.sign" || exit 1

if [ -n "${BFS}" ]; then
	big_echo "Downloading BFS patches ..."
	wget -nc "http://ck.kolivas.org/patches/4.0/${KERNEL_MAJOR}/${KERNEL_MAJOR}-${BFS}/patch-${KERNEL_MAJOR}-${BFS}.bz2" || exit 1
fi

big_echo "Downloading BFQ patches ..."
wget -nc -nd --no-parent --level 1 -r -R "*.html*" -R "${KERNEL_MAJOR}.0-${BFQ}" -R "*.BFQ" \
	"http://algo.ing.unimo.it/people/paolo/disk_sched/patches/${KERNEL_MAJOR}.0-${BFQ}" || exit 1
rm robots.txt

if [ -n "${PREEMPT_RT}" ]; then
	big_echo "Downloading PREEMPT_RT patches ..."
	wget -nc "https://www.kernel.org/pub/linux/kernel/projects/rt/${KERNEL_MAJOR}/patch-${KERNEL_MAJOR}.${KERNEL_MINOR}-${PREEMPT_RT}.patch.xz" || exit 1
fi

big_echo "Uncompresing kernel ..."
xz -dk "linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar.xz"
gpg --verify "linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar.sign" "linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar" || exit 1
tar xf "linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar"
rm "linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.tar"

big_echo "Uncompresing patches ..."
if [ -n "${BFS}" ]; then
#	xz -d patch-${KERNEL_MAJOR}-${BFS}.xz
	bzip2 -d patch-${KERNEL_MAJOR}-${BFS}.bz2
	mv patch-${KERNEL_MAJOR}-${BFS} patch-${KERNEL_MAJOR}-${BFS}.patch
fi
if [ -n "${PREEMPT_RT}" ]; then
	xz -d patch-${KERNEL_MAJOR}.${KERNEL_MINOR}-${PREEMPT_RT}.patch.xz
fi

PATCHES="../000*.patch"
if [ -n "${BFS}" ]; then
	PATCHES="../patch-${KERNEL_MAJOR}-${BFS}.patch ${PATCHES}"
fi
if [ -n "${PREEMPT_RT}" ]; then
	PATCHES="../patch-${KERNEL_MAJOR}.${KERNEL_MINOR}-${PREEMPT_RT}.patch ${PATCHES}"
fi
if [ -n "${PREEMPT_RT}" -a -n "${BFS}" ]; then
	big_echo "Applying patch for BFS patch ..."
	patch -p0 < patch-${KERNEL_MAJOR}-${BFS}.patch.rt
fi

(cd linux-${KERNEL_MAJOR}.${KERNEL_MINOR}
for PATCH in ${PATCHES}; do
	big_echo "Patching with ${PATCH} ..."
	patch -p1 < ${PATCH}
done
)

big_echo "Starting kernel configuration ..."

cp ${CONFIG} linux-${KERNEL_MAJOR}.${KERNEL_MINOR}/.config || exit 1
cd linux-${KERNEL_MAJOR}.${KERNEL_MINOR}

# ARM cross-compilation stuff
#export $(dpkg-architecture -aarmhf); export CROSS_COMPILE=${CROSS_COMPILER_PREFIX=} export ARCH=arm
#make tegra_defconfig

yes "" | make oldconfig > /dev/null

echo "Setting up BFQ in config ..."
sed -i -e 's/^# CONFIG_IOSCHED_BFQ is not set/CONFIG_IOSCHED_BFQ=y/'           \
    -i -e 's/^CONFIG_IOSCHED_NOOP=y/# CONFIG_IOSCHED_NOOP is not set/'           \
    -i -e 's/^CONFIG_IOSCHED_DEADLINE=y/# CONFIG_IOSCHED_DEADLINE is not set/'           \
    -i -e 's/^CONFIG_IOSCHED_CFQ=y/# CONFIG_IOSCHED_CFQ is not set/'           \
    -i -e 's/^CONFIG_DEFAULT_IOSCHED="cfq"/CONFIG_DEFAULT_IOSCHED="bfq"/'      \
    -i -e 's/^CONFIG_DEFAULT_IOSCHED="deadline"/CONFIG_DEFAULT_IOSCHED="bfq"/' \
    -i -e 's/^CONFIG_DEFAULT_IOSCHED="noop"/CONFIG_DEFAULT_IOSCHED="bfq"/' .config

echo "Setting up CONFIG_HZ=1000 in config ..."
sed -i -e 's/^CONFIG_HZ_300=y/# CONFIG_HZ_300 is not set/'   \
    -i -e 's/^CONFIG_HZ_250=y/# CONFIG_HZ_250 is not set/'   \
    -i -e 's/^# CONFIG_HZ_1000 is not set/CONFIG_HZ_1000=y/' \
    -i -e 's/^CONFIG_HZ=250/CONFIG_HZ=1000/'                 \
    -i -e 's/^CONFIG_HZ=300/CONFIG_HZ=1000/' .config

echo "Setting up PREEMPT in config ..."
sed -i -e 's/^CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/'           \
    -i -e 's/^CONFIG_PREEMPT_VOLUNTARY=y/# CONFIG_PREEMPT_VOLUNTARY is not set/' .config
if [ -n "${PREEMPT_RT}" ]; then
	sed -i -e 's/^CONFIG_PREEMPT=y/# CONFIG_PREEMPT is not set/'                     \
	    -i -e 's/^# CONFIG_PREEMPT_RT_FULL is not set/CONFIG_PREEMPT_RT_FULL=y/' .config
else
	sed -i -e 's/^# CONFIG_PREEMPT is not set/CONFIG_PREEMPT=y/' .config
fi

yes "" | make oldconfig > /dev/null

make menuconfig

rm .config.old

big_echo "Compiling kernel ..."
sudo sh -c "CONCURRENCY_LEVEL=$((`grep -c '^processor' /proc/cpuinfo`+1)) \
	fakeroot make-kpkg --initrd kernel_image kernel_headers modules_image; \
	cd ..; \
	rm -r linux-${KERNEL_MAJOR}.${KERNEL_MINOR}"

# ARM cross-compilation stuff
#	fakeroot make-kpkg --arch arm --cross-compile ${CROSS_COMPILER_PREFIX} --initrd \
#		kernel_image kernel_headers; \
#	make ARCH=arm CROSS_COMPILE=${CROSS_COMPILER_PREFIX} uImage; \
#	cp arch/arm/boot/uImage ../uImage; \
