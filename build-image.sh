#!/bin/bash

# git clone https://github.com/offensive-security/kali-arm-build-scripts.git
# cd kali-arm-build-scripts
# ./build_deps.sh

basedir=`pwd`/kali-lcd
wireless=wlan0
wired=eth0
wan=eth0

# Size of image in megabytes
size=3000

arm="abootimg cgpt fake-hwclock ntpdate vboot-utils vboot-kernel-utils uboot-mkimage"
base="initramfs-tools sudo parted e2fsprogs usbutils"
tools="libnfc-bin mfoc nmap ethtool usbutils"
services="openssh-server apache2 openvpn hostapd dnsmasq"
extras="aircrack-ng wpasupplicant python-smbus i2c-tools"

export packages="${arm} ${base} ${tools} ${services} ${extras}"
export architecture="armel"

mkdir -p ${basedir}
cd ${basedir}

debootstrap --foreign --arch $architecture kali kali-$architecture http://http.kali.org/kali

cp /usr/bin/qemu-arm-static kali-$architecture/usr/bin/

LANG=C chroot kali-$architecture /debootstrap/debootstrap --second-stage

cat << EOF > kali-$architecture/etc/apt/sources.list
deb http://http.kali.org/kali kali main contrib non-free
deb http://security.kali.org/kali-security kali/updates main contrib non-free
EOF

echo "kali" > kali-$architecture/etc/hostname

cat << EOF > kali-$architecture/etc/hosts
127.0.0.1       kali    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

cat << EOF > kali-$architecture/etc/network/interfaces
auto lo
iface lo inet loopback

auto $wired
iface $wired inet static
  address 192.168.1.100
  netmask 255.255.255.0

auto $wireless
iface $wireless inet static
  address 10.0.0.1
  netmask 255.255.255.0
EOF

cat << EOF > kali-$architecture/etc/resolv.conf
nameserver 8.8.8.8
EOF

export MALLOC_CHECK_=0 # workaround for LP: #520465
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

mount -t proc proc kali-$architecture/proc
mount -o bind /dev/ kali-$architecture/dev/
mount -o bind /dev/pts kali-$architecture/dev/pts

cat << EOF > kali-$architecture/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

cp /etc/hosts kali-$architecture/etc/

cat << EOF > kali-$architecture/third-stage
#!/bin/bash
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get update
apt-get install locales-all
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates initramfs-tools uboot-mkimage
apt-get -y install locales console-common less nano git
echo "root:toor" | chpasswd

echo \# > /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
apt-get --yes --force-yes install $packages
update-rc.d ssh enable
rm -f /usr/sbin/policy-rc.d
rm -f /usr/sbin/invoke-rc.d
dpkg-divert --remove --rename /usr/sbin/invoke-rc.d
rm -f /third-stage
EOF

chmod +x kali-$architecture/third-stage
LANG=C chroot kali-$architecture /third-stage

echo i2c-bcm2708 >> kali-$architecture/etc/modules
echo i2c-dev >> kali-$architecture/etc/modules

cat <<EOF > kali-$architecture/etc/hostapd/hostapd.conf
interface=$wireless
driver=nl80211
ssid=KaliFreeWifi
channel=1
EOF

cat <<EOF > kali-$architecture/etc/dnsmasq.conf
log-facility=/var/log/dnsmasq.log
#address=/#/10.0.0.1
#address=/google.com/10.0.0.1
interface=$wireless
dhcp-range=10.0.0.10,10.0.0.250,12h
dhcp-option=3,10.0.0.1
dhcp-option=6,10.0.0.1
#no-resolv
log-queries
EOF

cat <<EOF > kali-$architecture/etc/rc.local
#!/bin/sh
cd /root/Adafruit-Raspberry-Pi-Python-Code/Adafruit_CharLCDPlate
/usr/bin/python kali-sly-pi.py &
exit 0
EOF

chmod +x kali-$architecture/etc/rc.local

cat <<EOF >> kali-$architecture/usr/bin/nat-start
#!/bin/bash
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o $wan -j MASQUERADE
iptables -A FORWARD -i $wan -o $wireless -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $wireless -o $wan -j ACCEPT
EOF

cat <<EOF >> kali-$architecture/usr/bin/nat-stop
#!/bin/bash
echo 0 > /proc/sys/net/ipv4/ip_forward
iptables -F
iptables -t nat -F
EOF

chmod +x  kali-$architecture/usr/bin/nat-start
chmod +x  kali-$architecture/usr/bin/nat-stop

echo \# > kali-$architecture/lib/udev/rules.d/75-persistent-net-generator.rules

sed -i 's#^DAEMON_CONF=.*#DAEMON_CONF=/etc/hostapd/hostapd.conf#' kali-$architecture/etc/init.d/hostapd

##### Get LCD related stuff ######
tar zxpf ../lcd.tar.gz -C kali-$architecture/root/
cp ../kali-sly-pi.py kali-$architecture/root/Adafruit-Raspberry-Pi-Python-Code/Adafruit_CharLCDPlate/

cat << EOF > kali-$architecture/cleanup
#!/bin/bash
rm -rf /root/.bash_history
apt-get clean
rm -f /0
rm -f /hs_err*
rm -f cleanup
rm -f /usr/bin/qemu*
EOF

chmod +x kali-$architecture/cleanup
LANG=C chroot kali-$architecture /cleanup

umount kali-$architecture/dev/pts
umount kali-$architecture/dev/
umount kali-$architecture/proc

# Create the disk and partition it
echo "Creating image file for Raspberry Pi"
dd if=/dev/zero of=${basedir}/kali-mod-rpi.img bs=1M count=$size
parted kali-mod-rpi.img --script -- mklabel msdos
parted kali-mod-rpi.img --script -- mkpart primary fat32 0 64
parted kali-mod-rpi.img --script -- mkpart primary ext4 64 -1

# Set the partition variables
loopdevice=`losetup -f --show ${basedir}/kali-mod-rpi.img`
device=`kpartx -va $loopdevice| sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
mkfs.vfat $bootp
mkfs.ext4 $rootp

# Create the dirs for the partitions and mount them
mkdir -p ${basedir}/bootp ${basedir}/root
mount $bootp ${basedir}/bootp
mount $rootp ${basedir}/root

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${basedir}/kali-$architecture/ ${basedir}/root/

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> ${basedir}/root/etc/inittab

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section. We've added a static binary kernel/modules to this build for brevity.

# git clone -b rpi-3.13.y --depth 1 https://github.com/raspberrypi/linux ${basedir}/kernel
# git clone --depth 1 https://github.com/raspberrypi/tools ${basedir}/tools
# cd ${basedir}/kernel
# mkdir -p ../patches
# wget https://raw.github.com/offensive-security/kali-arm-build-scripts/master/patches/kali-wifi-injection-3.12.patch -O ../patches/mac80211.patch
# patch -p1 --no-backup-if-mismatch < ../patches/mac80211.patch
# touch .scmversion
# export ARCH=arm
# export CROSS_COMPILE=${basedir}/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian/bin/arm-linux-gnueabihf-
# cp ${basedir}/../kernel-configs/rpi.config .config
# make -j $(grep -c processor /proc/cpuinfo)
# make modules_install INSTALL_MOD_PATH=${basedir}/root
# git clone --depth 1 https://github.com/raspberrypi/firmware.git rpi-firmware
# cp -rf rpi-firmware/boot/* ${basedir}/bootp/
# cp arch/arm/boot/zImage ${basedir}/bootp/kernel.img
# cd ${basedir}
## Create cmdline.txt file
# cat << EOF > ${basedir}/bootp/cmdline.txt
# dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 elevator=deadline root=/dev/mmcblk0p2 rootfstype=ext4 rootwait
# EOF
# rm -rf ${basedir}/root/lib/firmware
# cd ${basedir}/root/lib
# git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git firmware
# rm -rf ${basedir}/root/lib/firmware/.git

tar zxpf ../modules.tar.gz -C ${basedir}/root/
tar zxpf ../bootp.tar.gz -C ${basedir}/bootp/

# rpi-wiggle
mkdir -p ${basedir}/root/scripts
cp ../rpi-wiggle ${basedir}/root/scripts/rpi-wiggle.sh

# Unmount partitions
umount $bootp
umount $rootp
kpartx -dv $loopdevice
losetup -d $loopdevice

