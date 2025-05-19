#!/bin/sh

#echo $0 $1 $2 $3 $4 $5 $6 $7

PROG_NAME=$0
DEBUG=$1
KERNEL_VERSION=$2
PLATFORM_TYPE=$3
MONOLITH_TYPE=$4
CPU=$5
ROOTFS=$6
DISK_DEV=$7 
ROOT_DEV=$8
SINGLE_PARTITION=$9

# DISK_DEV represents the new disk device (e.g., sda)
# ROOT_DEV represents the new root partition device (e.g., sda2)

if [ $DEBUG = yes ]; then DEBUG_ARG=debug; else DEBUG_ARG=release; fi

# vverifier: special handling of platform type
if [ $PLATFORM_TYPE = bvverifier ]; then PLATFORM_TYPE=vverifier; fi
if [ $MONOLITH_TYPE = bvverifier ]; then MONOLITH_TYPE=vverifier; fi
if [ $PLATFORM_TYPE = bnv40b ]; then PLATFORM_TYPE=nv40b; fi
if [ $MONOLITH_TYPE = bnv40b ]; then MONOLITH_TYPE=nv40b; fi

SINGLE_USER_MODE=no

case $PLATFORM_TYPE in
    b1) 
        # The BV1 flash device is an eMMC, and its device name ends in 'pX', 
        # where X is a number, whereas all other eUSB device names end in 'X'
        # without any prepended 'p' character
        DISK_DEV_BOOT=${DISK_DEV}p3
        DISK_DEV_BOOT_MOUNTPOINT=${DISK_DEV_BOOT}
        DEV_FSTAB_INDENT=" "
        if [  ${SINGLE_PARTITION} = yes ]; then SINGLE_USER_MODE=yes; fi
        ;;
    b110rev2) 
        # The 110rev2 flash device is an eMMC, and its device name ends in 'pX', 
        # where X is a number, whereas all other eUSB device names end in 'X'
        # without any prepended 'p' character
        DISK_DEV_BOOT=${DISK_DEV}p1
        DISK_DEV_BOOT_MOUNTPOINT=${DISK_DEV_BOOT}
        DEV_FSTAB_INDENT=" "
        ;;
    vverifier)
        DISK_DEV_BOOT=${DISK_DEV}1
        DISK_DEV_BOOT_MOUNTPOINT=boot
        DEV_FSTAB_INDENT="      "
    echo vverifier
        ;;
    nv40b)
        DISK_DEV_BOOT=${DISK_DEV}1
        DISK_DEV_BOOT_MOUNTPOINT=boot
        DEV_FSTAB_INDENT="      "
        echo nv40b
        ;;

    *)
        DISK_DEV_BOOT=${DISK_DEV}1
        DISK_DEV_BOOT_MOUNTPOINT=${DISK_DEV_BOOT}
        DEV_FSTAB_INDENT="      "
        ;;
esac
    echo $DISK_DEV_BOOT_MOUNTPOINT
    echo $DISK_DEV_BOOT
# Other settings
GRUB_BOOT_LOADER=yes
GRUB2_BOOT_LOADER=no
USE_TMPFS=yes
CREATE_SYS_LOG_LINK=yes
USE_HOTPLUG=yes

USE_LABELS=no # Disabled by default
if [ ${SINGLE_PARTITION} = no ]; then
 if [ ${ROOT_DEV} = hda2 ] || [ ${ROOT_DEV} = sda2 ] || [ ${ROOT_DEV} = vda2 ]  || [ ${ROOT_DEV} = xvda2 ] ; then 
  DEV_LABEL_ROOT=rootfs1
 else
  DEV_LABEL_ROOT=rootfs2
 fi
else
 DEV_LABEL_ROOT=rootfs
fi

case $PLATFORM_TYPE in
    b1) 
        GRUB_BOOT_LOADER=no
        USE_HOTPLUG=no
        ;;
    b110rev2) 
        GRUB_BOOT_LOADER=no
        GRUB2_BOOT_LOADER=yes
        ;;
    b1100) 
        GRUB_BOOT_LOADER=no
        GRUB2_BOOT_LOADER=yes
        ;;
    nv40b) 
        GRUB_BOOT_LOADER=no
        GRUB2_BOOT_LOADER=yes
        ;;
    b3500t)
        USE_HOTPLUG=no
        ;;
    b4000)
        USE_HOTPLUG=no
        ;;
    b4100)
        USE_HOTPLUG=no
        ;;
    b4104)
        USE_HOTPLUG=no
        ;;
    b4200)
        USE_HOTPLUG=no
        ;;
    b4210)
        USE_HOTPLUG=no
        ;;
    b6030) 
        GRUB_BOOT_LOADER=no
        GRUB2_BOOT_LOADER=yes
        ;;
    vverifier)
        GRUB_BOOT_LOADER=no
        GRUB2_BOOT_LOADER=yes
        USE_TMPFS=no
        CREATE_SYS_LOG_LINK=no
        USE_LABELS=yes
        ;;
    *)
        ;;
esac

# Go to the top of the new rootfs
cd ${ROOTFS}
# echo Changed directory to `pwd`

# Clear the umask, so we can set permissions correctly
umask 0

#
# Setuid bits
#
for i in bin/busybox \
  usr/bin/exfo-pci-control \
  usr/bin/celtic-eeprom \
  usr/bin/celtic-serial \
  usr/bin/celtic-timesvc \
  usr/bin/lastmile-rawcardtool \
  usr/bin/qemu-img \
  usr/sbin/tcpdump \
  usr/sbin/showsel \
  usr/sbin/fw_printenv \
  sbin/dmidecode \
  etc/init.d/netronome-nfe3240/tcpdump; do
  if [ -f $i ]; then chmod +s $i; fi
done
echo $ROOTFS
#
# File ownership. 501:3 is postgres:postgres, 500:1 is admin:admin.
#
chown 501:3 ${ROOTFS}/var/pgsql
chown 501:3 ${ROOTFS}/home/postgres
chown 500:1 ${ROOTFS}/home/admin
chmod 755 ${ROOTFS}/home/admin

# Setup links to the boot partition
if [ ${SINGLE_PARTITION} = no ]; then
 ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf ${ROOTFS}/var/brix/conf
 ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix ${ROOTFS}/etc/License
 
 # Setup symlinks for projects files
 if [ $PLATFORM_TYPE = b6030 ]; then 
   if [ ! -d /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf/raid-config ]; then 
       mkdir /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf/raid-config/ 
   fi
   if [ ! -f /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf/raid-config/projects ]; then
       touch /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf/raid-config/projects 
       chmod 0755 /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf/raid-config/projects 
   fi
   if [ ! -L ${ROOTFS}/etc/projects ]; then
       ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/brix/conf/raid-config/projects ${ROOTFS}/etc/projects
   fi
 fi

 # The grub link
 if [ $GRUB_BOOT_LOADER = yes ]; then
  ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/grub ${ROOTFS}/boot/grub
 fi
 if [ $GRUB2_BOOT_LOADER = yes ]; then
  ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/boot/grub ${ROOTFS}/boot/grub
  ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/boot/grub2 ${ROOTFS}/boot/grub2
 fi

 # The metadata link
 if [ $PLATFORM_TYPE = vverifier ]; then 
  ln -s /mnt/${DISK_DEV_BOOT_MOUNTPOINT}/metadata ${ROOTFS}/var/metadata
 fi
fi

# The sys.log link
if [ $CREATE_SYS_LOG_LINK = yes ]; then
  ln -s /mnt/tmpfs/var/log/sys.log ${ROOTFS}/var/log/sys.log
fi

if [ $USE_HOTPLUG = no ]; then
  rm -f ${ROOTFS}/sbin/hotplug
fi


# Remove these files, they end up being left over for one reason or another
rm -f ${ROOTFS}/var/brix/conf/conf
rm -rf ${ROOTFS}/etc/init.d/netronome/.ssh
rm -rf ${ROOTFS}/etc/init.d/netronome-nfe3240/.ssh

# Workaround for netronome-nfe ssh access: for some reason, it only works
# if the file ownership is as below.
if [ -f ${ROOTFS}/etc/init.d/netronome-nfe3240/nfp-bsp-release/keyring/cayenne-ssh ]; then
  chown 1076:105 ${ROOTFS}/etc/init.d/netronome-nfe3240/nfp-bsp-release/keyring/cayenne-ssh
fi

#
# etc customization
#

# Local variables
TTY_DEV=ttyS0
SECONDARY_TTY_DEV=ttyS1
USE_SECONDARY_TTY_DEV=yes
USE_TTY_USB=no
USE_VIDEO_TTY_DEV=no
TMPFS_SIZE=50M

# Serial port speeds
SERIAL_SPEED=9600
TTY_USB_SERIAL_SPEED=9600

if [ $PLATFORM_TYPE = b1 ]; then 
  TTY_DEV=ttymxc0
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=115200
  USE_TTY_USB=yes
fi
if [ $PLATFORM_TYPE = b110 ]; then 
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=9600
fi
if [ $PLATFORM_TYPE = b110rev2 ]; then 
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=9600
fi
if [ $PLATFORM_TYPE = b1100 ]; then 
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=115200,9600
fi
if [ $PLATFORM_TYPE = b1500 ]; then 
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=115200,9600
fi
if [ $PLATFORM_TYPE = b3000 ]; then 
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=115200,9600
fi
if [ $PLATFORM_TYPE = b3100 ]; then 
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=115200,9600
fi
if [ $PLATFORM_TYPE = nv40b ]; then 
  TTY_DEV=ttyS0
  SECONDARY_TTY_DEV=ttyS1
  SERIAL_SPEED=115200,9600
  USE_VIDEO_TTY_DEV=yes
fi

if [ $PLATFORM_TYPE = b4100 ]; then 
  TTY_DEV=ttyS1
  SECONDARY_TTY_DEV=ttyS0
fi

if [ $PLATFORM_TYPE = b4104 ]; then 
  TTY_DEV=ttyS1
  SECONDARY_TTY_DEV=ttyS0
fi

if [ $PLATFORM_TYPE = b4200 ] || \
   [ $PLATFORM_TYPE = b4204 ] || \
   [ $PLATFORM_TYPE = b4210 ] || \
   [ $PLATFORM_TYPE = b4220 ] || \
   [ $PLATFORM_TYPE = b4230 ]; then 
  USE_VIDEO_TTY_DEV=yes
  SERIAL_SPEED=115200
fi


if [ $PLATFORM_TYPE = b6030 ]; then 
  USE_VIDEO_TTY_DEV=yes
  USE_SECONDARY_TTY_DEV=no
  SERIAL_SPEED=9600
fi

if [ $PLATFORM_TYPE = vverifier ]; then 
  USE_SECONDARY_TTY_DEV=no
  USE_VIDEO_TTY_DEV=yes
fi

(
echo "#"
echo "# device        directory       type    options"
echo "#"
if [ ${USE_LABELS} = yes ]; then
  echo "LABEL=${DEV_LABEL_ROOT}   /               ext3    data=journal,noatime"
else
  echo "/dev/${ROOT_DEV}${DEV_FSTAB_INDENT} /               ext3    data=journal,noatime"
fi
echo "none            /proc           proc    defaults"
if [ ${KERNEL_VERSION} = 3.18.12 ]; then
  echo "none            /dev            devtmpfs defaults       0 0"
fi
if [ $PLATFORM_TYPE = vverifier ]; then
echo "none            /mnt/huge       hugetlbfs defaults"
fi
echo "/dev/devpts     /dev/pts        devpts  gid=5,mode=620  0 0"
echo "/dev/shm        /dev/shm        tmpfs   defaults        0 0"
echo "sysfs           /sys            sysfs   defaults        0 0"
if [ ${KERNEL_VERSION} = 2.6.35.7 ] || [ ${KERNEL_VERSION} = 3.0.35 ]; then
  # The usbfs has been obsoleted in newer kernels
  echo "/proc/bus/usb   /proc/bus/usb   usbfs   defaults        0 0"
fi
echo "none_debugs     /sys/kernel/debug debugfs"
if [ ${USE_TMPFS} = yes ]; then
  echo "tmpfs           /mnt/tmpfs      tmpfs   size=${TMPFS_SIZE} 0 0" 
fi
if [ ${SINGLE_PARTITION} = no ]; then
  if [ ${USE_LABELS} = yes ]; then
    echo "LABEL=bootfs    /mnt/${DISK_DEV_BOOT_MOUNTPOINT}       ext3    data=journal,noatime"
  else
    echo "/dev/${DISK_DEV_BOOT}${DEV_FSTAB_INDENT} /mnt/${DISK_DEV_BOOT_MOUNTPOINT}       ext3    data=journal,noatime"
  fi
fi
) >${ROOTFS}/etc/fstab

# Create the factory defaults password files
cp ${ROOTFS}/etc/passwd ${ROOTFS}/etc/.passwd.factory_default
cp ${ROOTFS}/etc/shadow ${ROOTFS}/etc/.shadow.factory_default

# Write the inittab
(
echo \# Runlevels:
echo \# 1 - single user mode, bypasses inittab completely
echo \# 2 - diagnostics mode
echo \# 3 - multi user mode
echo \# 4 - multi user mode, backup partition
echo \# 5 - multi user mode, restore factory defaults
echo \# 6 - multi user mode as kgdb target
echo
echo :2:sysinit:/etc/init.d/rc.diag.init 2 
echo :3:sysinit:/etc/init.d/rc.init 3 
echo :4:sysinit:/etc/init.d/rc.init 4 
echo :5:sysinit:/etc/init.d/rc.init 5 
echo :6:sysinit:/etc/init.d/rc.init 6 
echo :2:shutdown:/etc/init.d/rc.diag.shutdown 2 
echo :3:shutdown:/etc/init.d/rc.shutdown 3 
echo :4:shutdown:/etc/init.d/rc.shutdown 4 
echo :5:shutdown:/etc/init.d/rc.shutdown 5 
echo :6:shutdown:/etc/init.d/rc.shutdown 6 

if [ ${SINGLE_USER_MODE} = no ]; then
 echo :3456:respawn:/sbin/getty -c -L ${TTY_DEV} ${SERIAL_SPEED} vt100
 echo :2:respawn:/sbin/getty -n -l /bin/sh -c -L ${TTY_DEV} ${SERIAL_SPEED} vt100
 if [ ${USE_SECONDARY_TTY_DEV} = yes ]; then 
  echo :345:respawn:/sbin/getty -c -L ${SECONDARY_TTY_DEV} ${SERIAL_SPEED} vt100
  echo :2:respawn:/sbin/getty -n -l /bin/sh -c -L ${SECONDARY_TTY_DEV} ${SERIAL_SPEED} vt100
 fi
 if [ ${USE_TTY_USB} = yes ]; then 
   echo :3456:respawn:/usr/bin/start-ttyusb-getty.sh 3
   echo :2:respawn:/usr/bin/start-ttyusb-getty.sh 2
 fi
else # SINGLE_USER_MODE == yes
 echo :23456:respawn:/sbin/getty -n -l /bin/sh -c -L ${TTY_DEV} ${SERIAL_SPEED} vt100
 if [ ${USE_SECONDARY_TTY_DEV} = yes ]; then 
  echo :23456:respawn:/sbin/getty -n -l /bin/sh -c -L ${SECONDARY_TTY_DEV} ${SERIAL_SPEED} vt100
 fi
 if [ ${USE_TTY_USB} = yes ]; then 
   echo :23456:respawn:/sbin/getty -n -l /bin/sh -c -L ttyUSB0 ${TTY_USB_SERIAL_SPEED} vt100
 fi
fi

if [ ${USE_VIDEO_TTY_DEV} = yes ]; then 
  echo tty1:3456:respawn:/sbin/getty -c 38400 tty1
  echo tty2:3456:respawn:/sbin/getty -c 38400 tty2
  echo tty3:3456:respawn:/sbin/getty -c 38400 tty3
  echo tty4:3456:respawn:/sbin/getty -c 38400 tty4
  echo tty5:3456:respawn:/sbin/getty -c 38400 tty5
  echo tty6:3456:respawn:/sbin/getty -c 38400 tty6
  echo tty7:3456:respawn:/sbin/getty -c 38400 tty7
  echo tty1:2:respawn:/bin/sh
  echo tty2:2:respawn:/bin/sh
  echo tty3:2:respawn:/bin/sh
  echo tty4:2:respawn:/bin/sh
  echo tty5:2:respawn:/bin/sh
  echo tty6:2:respawn:/bin/sh
  echo tty7:2:respawn:/bin/sh
fi
echo ::restart:/sbin/init
echo ::ctrlaltdel:/sbin/reboot
) >${ROOTFS}/etc/inittab

#
# Device files setup
#

# Go to the dev folder
if [ ! -d ${ROOTFS}/dev ]; then mkdir -p ${ROOTFS}/dev; fi
cd ${ROOTFS}/dev
# echo Changed directory to `pwd`

# Devices are created through the /sys file system, 
# and additionally by the setup_devices() routine in /etc/init.d/rc.platform

# Required by switch_root and by fsck
mknod console c 5 1 
mknod null c 1 3
mknod zero c 1 5

# Required by /etc/fstab
mkdir pts shm

# Required by the fsck, which runs before setup_devices()
mknod sda b 8 0
for i in 1 2 3 4 5 6 7; do
  mknod sda$i b 8 $i
done
  
mknod sdb b 8 16
k=17
for i in 1 2 3 4 5 6 7; do
  mknod sdb$i b 8 $k
  let k=k+1
done
  
mknod sdc b 8 32
k=33
for i in 1 2 3 4 5 6 7; do
  mknod sdc$i b 8 $k
  let k=k+1
done
  
mknod sdd b 8 48
k=49
for i in 1 2 3 4 5 6 7; do
  mknod sdd$i b 8 $k
  let k=k+1
done
  
mknod sde b 8 64
k=65
for i in 1 2 3 4 5 6 7; do
  mknod sde$i b 8 $k
  let k=k+1
done

mknod mmcblk0 b 179 0
k=1
for i in 1 2 3 4 5 6 7; do
  mknod mmcblk0p$i b 179 $k
  let k=k+1
done

mknod mmcblk1 b 179 24
k=25
for i in 1 2 3 4 5 6 7; do
  mknod mmcblk1p$i b 179 $k
  let k=k+1
done

mknod mtd0 c 90 0

for i in 0 1 2 3 4 5 6 7 8 9; do
  mknod ttyUSB$i c 188 $i
done

for i in 0 1 2 3 4; do
  let j=i+16
  mknod ttymxc$i c 207 $j
done

ln -s ../proc/kcore core
ln -s ../proc/self/fd df

for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  mknod loop$i b 7 $i
done

mknod ppp c 108 0
mknod full c 1 7
mknod kmem c 1 2
mknod mem c 1 1
mknod ptmx c 5 2
mknod rtc c 10 135
mknod rtc0 c 254 0
mknod urandom c 1 9

k=0
for i in p q r s t u v w x y z a b c d e; do
  for j in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
    mknod pty$i$j c 2 $k
    mknod tty$i$j c 3 $k
    let k=k+1
  done
done

mknod random c 1 8
mknod initrd b 1 250
mknod ram1 b 1 1
ln -s ram1 ram

ln -s ../proc/self/fd/2 stderr
ln -s ../proc/self/fd/0 stdin
ln -s ../proc/self/fd/1 stdout

mknod tty c 5 0
for i in 0 1 2 3 4 5 6 7 8 9; do
  mknod tty$i c 4 $i
done

for i in 0 1 2 3 4 5 6 7 8 9; do
  let j=i+64
  mknod ttyS$i c 4 $j
done

for i in 0 1; do
  let j=i+170
  mknod ttyCS$i c 204 $j
done

for i in 0 1 2; do
  mknod i2c-$i c 89 $i
done

mknod watchdog c 10 130

chmod 666 full null ptmx pty* zero ppp
chmod 666 tty* ttys* ttyS* ttyUSB*
chmod 664 random console
chmod 660 loop* kmem mem sda*
chmod 644 rtc urandom
chmod 640 ram
chmod 400 initrd watchdog

# Pop back
cd - >/dev/null 2>&1
# echo Changed directory to `pwd`

#
# Crontab support
#

# Is Intel Raid control enabled?
if [ $PLATFORM_TYPE = b4204 ] || \
   [ $PLATFORM_TYPE = b4210 ] || \
   [ $PLATFORM_TYPE = b4220 ] || \
   [ $PLATFORM_TYPE = b4230 ]; then 
  USE_INTEL_RAID_CONTROL=yes
else
  USE_INTEL_RAID_CONTROL=no
fi

# Is IPMI enabled?
if [ $PLATFORM_TYPE = b110 ] || \
   [ $PLATFORM_TYPE = b110rev2 ] || \
   [ $PLATFORM_TYPE = b1500 ] || \
   [ $PLATFORM_TYPE = b3100 ] || \
   [ $PLATFORM_TYPE = nv40b ] || \
   [ $PLATFORM_TYPE = vverifier ]; then
  USE_IPMI_WDT=no
else
  USE_IPMI_WDT=yes
fi

# Is /dev/watchdog used?
if [ $PLATFORM_TYPE = b1 ] || \
   [ $PLATFORM_TYPE = b1100 ] || \
   [ $PLATFORM_TYPE = b1500 ] || \
   [ $PLATFORM_TYPE = b3100 ] || \
   [ $PLATFORM_TYPE = nv40b ]; then
  USE_DEV_WATCHDOG=yes
else
  USE_DEV_WATCHDOG=no
fi

if [ $USE_INTEL_RAID_CONTROL = yes ]; then
  echo "* * * * * /usr/bin/raid-control" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

if [ $USE_IPMI_WDT = yes ]; then
  echo "* * * * * /usr/sbin/wdt -r" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

if [ $USE_DEV_WATCHDOG = yes ]; then
  echo "* * * * * ls /tmp >/dev/null 2>&1; if [ \$? = 0 ]; then if [ -c /dev/watchdog ]; then echo 0 > /dev/watchdog; fi; fi" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

if [ $PLATFORM_TYPE = b110 ]; then
    echo "* * * * * /usr/sbin/wdt_sp -r" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

if [ $PLATFORM_TYPE = b110rev2 ]; then
    echo "* * * * * /usr/sbin/wdt -r" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

# add raid-alert script into crontab
if [ $PLATFORM_TYPE = b6030 ]; then
    echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /usr/sbin/raid_alert_monitor.sh" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

# All platforms use logrotate - but the script may be a no-op for some platforms
echo "0 0 * * * /usr/sbin/logrotate.sh" >>${ROOTFS}/var/spool/cron/crontabs/root

# Only vverifier platforms use logrotate for GTP
if [ $PLATFORM_TYPE = vverifier ]; then
echo "* * * * * /usr/sbin/logrotate  /etc/logrotateGTP.conf" >>${ROOTFS}/var/spool/cron/crontabs/root
fi

#
# home/admin customization
#

CAPTURE_IS_LINKED=no
if [ $PLATFORM_TYPE = b4200 ] || \
   [ $PLATFORM_TYPE = b4204 ] || \
   [ $PLATFORM_TYPE = b4210 ] || \
   [ $PLATFORM_TYPE = b4220 ] || \
   [ $PLATFORM_TYPE = b4230 ] || \
   [ $PLATFORM_TYPE = b6030 ]; then 
    CAPTURE_IS_LINKED=yes
fi

if [ $CAPTURE_IS_LINKED = no ]; then
  mkdir ${ROOTFS}/home/admin/capture
  for i in ${ROOTFS}/home/admin/capture; do
    # Set to user admin, group admin
    chown 500:1 $i
    chmod 775 $i
  done
else
  mkdir ${ROOTFS}/home/admin/capture
  # Set to user admin, group admin
  chown 500:1 ${ROOTFS}/home/admin/capture
  ln -s ${ROOTFS}/home/admin/capture ${ROOTFS}/home/admin/capture
fi

for i in ${ROOTFS}/home/admin/.profile; do
  chmod 664 $i
done

for i in ${ROOTFS}/home/admin/.ssh; do
  # Set to user admin, group admin
  chown 500:1 $i
  chmod 700 $i
done

for i in ${ROOTFS}/home/admin/ramdisk.priv.key; do
  # Set to user admin, group admin
  chown 500:1 $i
  chmod 600 $i
done

