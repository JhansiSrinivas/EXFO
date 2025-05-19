#!/bin/bash

# Parse the program name, but strip leading characters in the path
PROGNAME=${0##*/}
HOSTNAME=`hostname`

# The grub-install executable resides in a special location on Antigone
GRUB_INSTALL=grub2-install
if [ x$HOSTNAME = xantigone ]; then 
  GRUB_INSTALL=/usr/local/sbin/grub-install
fi

bvm_mkimg_usage ()
{
  echo
  echo Usage: ${PROGNAME} ARGUMENTS
  echo
  echo "Arguments:"
  echo "   -m|--monolith monolith-name.jar"
  echo "        Pass in a bvm monolith jar file. Required parameter."
  echo "   -p b1100"
  echo "        Specify the platform. Required parameter." 
  echo "        Only B1100 supported at this time."
  echo "   -o|--output bvm.vmdk"
  echo "        Specify the output vmdk file. This argument is optional."
  echo "        If not specified, it will be set to the leaf name of"
  echo "        monolith-name.jar, with the suffix changed to '.vmdk'."
  echo "   -dcf filename.xml"
  echo "        Pass in a default config file."
  echo "   -vkr filename.vkr"
  echo "        Pass in a vkr file. Requires the 'encrypt-vkr' tool"
  echo "        to be in the PATH."
  echo "   -vkx filename.vkx"
  echo "        Pass in a vkx file. Either a vkr or a vkx file must be specified."
  echo "   -h|--help|-?"
  echo "        Display this help."
  echo
  echo "Environment variables:"
  echo "   BVM_MKIMG_MONOLITH_JAR"
  echo "        Pass in a bvm monolith jar file."
  echo "   BVM_MKIMG_MONOLITH_PLATFORM"
  echo "        Specify the platform."
  echo "   BVM_MKIMG_OUTPUT_VMDK"
  echo "        Specify the output vmdk file."
  echo "   BVM_MKIMG_DCF"
  echo "        Pass in a default config file."
  echo "   BVM_MKIMG_VKR"
  echo "        Pass in a vkr file. Requires the 'encrypt-vkr' tool"
  echo "        to be in the PATH."
  echo "   BVM_MKIMG_VKX"
  echo "        Pass in a vkx file."
  echo
}

bvm_cleanup ()
{
  for i in 1 2 3; do 
    umount /mnt/loop2p$i >/dev/null 2>&1
  done
  kpartx -d /dev/loop2 >/dev/null 2>&1
  losetup -d /dev/loop2 >/dev/null 2>&1
}

# Handle a signal interrupt
bvm_handle_control_c ()
{
  echo
  echo -n "Exiting on signal interrupt... "
  bvm_cleanup
  if [ -d $TMPDIR ]; then rm -rf $TMPDIR; fi
  echo done
  exit 1
}

bvm_format_b1100 ()
{
    fdisk -H 64 -S 32 -u=cylinders /dev/loop2  << EOF >/dev/null 2>&1
d
1
d
2
d
3
d
4
n
p
1
2
98
n
p
2
99
1949
n
p
3
1950
3800
n
p
4
3801
15488
w
EOF

    # We're not checking the exit code to fdisk on purpose, it indicates failure
    # for Linux, at the end, after partitioning is done, to reread the partition
    # table
}

bvm_format ()
{
  case $BVM_MKIMG_MONOLITH_PLATFORM in
      b1100)
          bvm_format_b1100
          ;;
      nv40b)
          bvm_format_b1100
          ;;
      *)  # Default case: If no more options then break out of the loop.
          echo "Platform $BVM_MKIMG_MONOLITH_PLATFORM not supported"
          bvm_cleanup
          if [ -d $TMPDIR ]; then rm -rf $TMPDIR; fi
          exit 1
  esac
}

# Install the signal handler
trap bvm_handle_control_c SIGINT SIGTERM

# Parse the command line arguments
while :; do
  case $1 in
      -h|-\?|--help)
          bvm_mkimg_usage
          exit 0
          ;;
      -m|--monolith)
          if [ "$2" ]; then
              BVM_MKIMG_MONOLITH_JAR=$2
              shift
          else
              echo 'Error: Monolith not specified.'
              echo
              bvm_mkimg_usage
              exit 1
          fi
          ;;
      -p|--platform)
          if [ "$2" ]; then
              BVM_MKIMG_MONOLITH_PLATFORM=$2
              shift
          else
              echo 'Error: Monolith not specified.'
              echo
              bvm_mkimg_usage
              exit 1
          fi
          ;;          
      -dcf)
          if [ "$2" ]; then
              BVM_MKIMG_DCF=$2
              shift
          else
              echo 'Error: DCF not specified.'
              echo
              bvm_mkimg_usage
              exit 1
          fi
          ;;
      -vkr)
          if [ "$2" ]; then
              BVM_MKIMG_VKR=$2
              shift
          else
              echo 'Error: VKR not specified.'
              echo
              bvm_mkimg_usage
              exit 1
          fi
          ;;
      -vkx)
          if [ "$2" ]; then
              BVM_MKIMG_VKX=$2
              shift
          else
              echo 'Error: VKX not specified.'
              echo
              bvm_mkimg_usage
              exit 1
          fi
          ;;
      -o|--output)
          if [ "$2" ]; then
              BVM_MKIMG_OUTPUT_VMDK=$2
              shift
          else
              echo 'Error: Output file not specified.'
              echo
              bvm_mkimg_usage
              exit 1
          fi
          ;;
      -?*)
          printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
          ;;
      *)  # Default case: If no more options then break out of the loop.
          break
  esac
   
  shift
done

if [ x$BVM_MKIMG_MONOLITH_JAR = x ]; then
  echo 'Error: Monolith not specified.'
  echo
  bvm_mkimg_usage
  exit 1
fi

if [[ $BVM_MKIMG_MONOLITH_JAR != *monolith-*.jar ]]; then
  echo Invalid argument $BVM_MKIMG_MONOLITH_JAR: should be of form monolith-\*.jar
  echo
  bvm_mkimg_usage
  exit 1
fi

if [ x$BVM_MKIMG_MONOLITH_PLATFORM = x ]; then
  echo 'Error: Platform not specified.'
  echo
  bvm_mkimg_usage
  exit 1
fi

case $BVM_MKIMG_MONOLITH_PLATFORM in
    b1100)
        ;;
    nv40b)
        ;;
    *)
        echo "Platform ${BVM_MKIMG_MONOLITH_PLATFORM} not supported"
        bvm_cleanup
        if [ -d $TMPDIR ]; then rm -rf $TMPDIR; fi
        exit 1
esac

if [ x$BVM_MKIMG_DCF != x ]; then
  if [ ! -f $BVM_MKIMG_DCF ]; then 
    echo Error: DCF file $BVM_MKIMG_DCF not found
    bvm_mkimg_usage
    exit 1
  fi
fi

if [ x$BVM_MKIMG_VKR != x ]; then
  if [ ! -f $BVM_MKIMG_VKR ]; then 
    echo Error: VKR file $BVM_MKIMG_VKR not found
    bvm_mkimg_usage
    exit 1
  fi
fi

if [ x$BVM_MKIMG_VKX != x ]; then
  if [ ! -f $BVM_MKIMG_VKX ]; then 
    echo Error: VKX file $BVM_MKIMG_VKX not found
    bvm_mkimg_usage
    exit 1
  fi
  # Clear the VKR argument - passing in a VKX takes precedence
  BVM_MKIMG_VKR=
fi

if [ x$BVM_MKIMG_VKR != x ]; then
  # Is encrypt-vkr in the path?
  ENCRYPT_VKR=`type encrypt-vkr 2>/dev/null|awk '{print $3}'`
  if [ x$ENCRYPT_VKR = x ]; then
    echo "Error: encrypt-vkr not in the PATH"
    bvm_mkimg_usage
    exit 1    
  fi
  ldd $ENCRYPT_VKR >/dev/null 2>&1
  if [ $? != 0 ]; then
    echo "Error: encrypt-vkr library dependencies not in the LD_LIBRARY_PATH"
    bvm_mkimg_usage
    exit 1    
  fi
else 
  if [  x$BVM_MKIMG_VKX = x ]; then 
    echo "Error: VRK or VKX file must be specified"
    bvm_mkimg_usage
    exit 1
  fi
fi

INPUT_FILENAME_BASE=`echo ${BVM_MKIMG_MONOLITH_JAR##*/}|sed s/\.jar$//g`

if [ x$BVM_MKIMG_OUTPUT_VMDK = x ]; then
  BVM_MKIMG_OUTPUT_VMDK=${INPUT_FILENAME_BASE}.vmdk
fi

if [[ $BVM_MKIMG_OUTPUT_VMDK != *.vmdk ]]; then
  echo Image file extension invalid, should be \'.vmdk\'
  echo
  exit 1
fi

OUTPUT_FILENAME_BASE=`echo ${BVM_MKIMG_OUTPUT_VMDK##*/}|sed s/\.vmdk$//g`
OUTPUT_IMG=${OUTPUT_FILENAME_BASE}.img

if [ `id -u` != 0 ]; then 
    echo Error: Need to be user 'root' in order to execute $PROGNAME
    echo
    exit 1
fi

if [ ! -f $BVM_MKIMG_MONOLITH_JAR ]; then
    echo "The monolith jar file '${BVM_MKIMG_MONOLITH_JAR}' could not be found."
    exit 1
fi

# Clean up possible leftovers from previous runs
bvm_cleanup

echo "Operation started" `date`

TMPDIR=`mktemp -d /tmp/${INPUT_FILENAME_BASE}.XXXXXXXXXX`
echo "Creating temporary folder ${TMPDIR}... done"

echo -n "Unpacking ${BVM_MKIMG_MONOLITH_JAR}... "
cat $BVM_MKIMG_MONOLITH_JAR | (cd ${TMPDIR}; jar x)
if [ ! -f ${TMPDIR}/monolith.tgz ]; then
  echo fail
  echo Error: File monolith.tgz not found in $BVM_MKIMG_MONOLITH_JAR
  bvm_cleanup
  rm -rf ${TMPDIR}
  exit 1
fi
echo done

echo -n "Unpacking monolith.tgz from ${BVM_MKIMG_MONOLITH_JAR}... "
mkdir ${TMPDIR}/monolith
(cd ${TMPDIR}/monolith; tar xf ../monolith.tgz)

if [ ! -f ${TMPDIR}/monolith/rootfs.tgz ]; then
  echo fail
  echo Error: File rootfs.tgz not found in monolith.tgz
  bvm_cleanup
  rm -rf ${TMPDIR}
  exit 1
fi
echo done
echo hello
echo -n "Unpacking rootfs.tgz from monolith.tgz... "
mkdir ${TMPDIR}/monolith/rootfs
(cd ${TMPDIR}/monolith/rootfs; tar xf ../rootfs.tgz)
if [ ! -f ${TMPDIR}/monolith/rootfs/boot/vmlinuz ]; then
  echo fail
  bvm_cleanup
  rm -rf ${TMPDIR}
  exit 1
fi
echo done

# Which flash drive size should we use? Use 'fdisk', 'p' to determine
# the platform flash drive size, and update below
case $BVM_MKIMG_MONOLITH_PLATFORM in
    b1100)
        BVM_MKIMG_DISK_SIZE=16240345088
        ;;
    nv40b)
        BVM_MKIMG_DISK_SIZE=16240345088
        ;;
    *)  # Default case: If no more options then break out of the loop.
        echo "Platform ${BVM_MKIMG_MONOLITH_PLATFORM}: don't know disk/flash size"
        bvm_cleanup
        if [ -d $TMPDIR ]; then rm -rf $TMPDIR; fi
        exit 1
esac

# Create the disk file
echo -n "Creating $OUTPUT_IMG file... "
qemu-img create -f raw ${TMPDIR}/${OUTPUT_IMG} ${BVM_MKIMG_DISK_SIZE} >/dev/null 2>&1
if [ $? != 0 ]; then
  echo fail
  bvm_cleanup
  rm -rf $TMPDIR
  exit 1
fi
echo done
echo Hello Navya
echo -n "Creating the loop device... "
losetup /dev/loop2 ${TMPDIR}/$OUTPUT_IMG
if [ $? != 0 ]; then
  echo fail
  bvm_cleanup
  rm -rf $TMPDIR
  exit 1
fi
echo done

echo -n "Formatting $OUTPUT_IMG... "
bvm_format
echo done

echo -n "Adding device maps... "
kpartx -a -v /dev/loop2 >/dev/null 2>&1
if [ $? != 0 ]; then 
    echo fail
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi
echo done

echo -n "Make the boot file system... "
if ! mke2fs -j -L bootfs /dev/mapper/loop2p1 >/dev/null 2>&1; then
    echo fail
    echo  "Cannot build a filesystem on /dev/mapper/loop2p1"
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi
tune2fs -c 0 -i 0 /dev/mapper/loop2p1 >/dev/null 2>&1
echo done

echo -n "Make the primary root file system... "
if ! mke2fs -j -L rootfs1 /dev/mapper/loop2p2 >/dev/null 2>&1; then
    echo fail
    echo  "Cannot build a filesystem on /dev/mapper/loop2p2"
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi
tune2fs -c 0 -i 0 /dev/mapper/loop2p2 >/dev/null 2>&1
echo done

echo -n "Make the backup root file system... "
if ! mke2fs -j -L rootfs2 /dev/mapper/loop2p3 >/dev/null 2>&1; then
    echo fail
    echo  "Cannot build a filesystem on /dev/mapper/loop2p3"
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi
tune2fs -c 0 -i 0 /dev/mapper/loop2p3 >/dev/null 2>&1
echo done

echo -n "Mount the file systems... "
for i in 1 2 3; do 
    if [ ! -d /mnt/loop2p$i ]; then mkdir -p /mnt/loop2p$i; fi
    mount -t ext3 /dev/mapper/loop2p$i /mnt/loop2p$i >/dev/null 2>&1
    if [ $? != 0 ]; then 
        echo fail
        echo Failed to mount /dev/mapper/loop2p$i on /mnt/loop2p$i
        bvm_cleanup
        rm -rf $TMPDIR
        exit 1
    fi
done
echo done

echo -n "Unpack the primary root file system files... "
tar zxvf ${TMPDIR}/monolith/rootfs.tgz -C /mnt/loop2p2 >/dev/null 2>&1
if [ $? != 0 ]; then 
    echo fail
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi

# Set file ownership
chown -Rh 0:0 /mnt/loop2p2/* /mnt/loop2p2/.profile

# Set the root-device
echo sda2 >/mnt/loop2p2/var/brix/root-device

echo done

# Set up the environment DEBUG and KERNEL_VERSION
. /mnt/loop2p2/boot/install-tools/setup-env.sh

echo -n "Execute directory-post-setup script on the primary rootfs ... "
/mnt/loop2p2/boot/install-tools/exec-post-setup.sh ${DEBUG} ${KERNEL_VERSION} ${BVM_MKIMG_MONOLITH_PLATFORM} bvm x86_64 /mnt/loop2p2 sda sda2 no

echo done

echo -n "Unpack the backup root file system files... "
tar zxvf ${TMPDIR}/monolith/rootfs.tgz -C /mnt/loop2p3 >/dev/null 2>&1
if [ $? != 0 ]; then 
    echo fail
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi

# Set file ownership
chown -Rh 0:0 /mnt/loop2p3/* /mnt/loop2p3/.profile

# Set the root-device
echo sda3 >/mnt/loop2p3/var/brix/root-device

echo done

echo -n "Execute directory-post-setup script on the backup rootfs... "
/mnt/loop2p2/boot/install-tools/exec-post-setup.sh ${DEBUG} ${KERNEL_VERSION} ${BVM_MKIMG_MONOLITH_PLATFORM} bvm x86_64 /mnt/loop2p3 sda sda3 no

echo done

echo -n "Set up grub... "
mkdir -p /mnt/loop2p1/boot/grub

# Create grub.cfg
(
    echo \# 
    echo \# Grub file generated by the bvm-mkimg.sh script
    echo \#
    echo "set default=0"
    echo "set timeout=10"
    echo "insmod ext2"
    echo
    echo "menuentry 'Verifier' {"
    echo "  set root='(hd0,msdos2)'"
    echo "  linux /boot/vmlinuz ro root=LABEL=rootfs1 rootflags=data=journal rootfstype=ext3 console=tty0 console=ttyS0,115200n8 console=ttyS1,115200n8 3"
    echo "  initrd /boot/initrd.img"
    echo "  set debug= all"  
    echo "}"
    echo
    echo "menuentry 'Restore Factory Defaults' {"
    echo "  set root='(hd0,2)'"
    echo "  linux /boot/vmlinuz ro root=/dev/sda2 rootflags=data=journal rootfstype=ext3 console=tty0 console=ttyS0,115200n8 console=ttyS1,115200n8 5"
    echo "  initrd /boot/initrd.img"
    echo "}"
    echo
    echo "menuentry 'Diagnostics' {"
    echo "  set root='(hd0,2)'"
    echo "  linux /boot/vmlinuz ro root=/dev/sda2 rootflags=data=journal rootfstype=ext3 console=tty0 console=ttyS0,115200n8 console=ttyS1,115200n8 2"
    echo "  initrd /boot/initrd.img"
    echo "}"
    echo
    echo "menuentry 'Verifier Recovery' {"
    echo "  set root='(hd0,3)'"
    echo "  linux /boot/vmlinuz ro root=LABEL=rootfs3 rootflags=data=journal rootfstype=ext3 console=tty0 console=ttyS0,115200n8 console=ttyS1,115200n8 4"
    echo "  initrd /boot/initrd.img"
    echo "}"
) >/mnt/loop2p1/boot/grub/grub.cfg
cp /mnt/loop2p1/boot/grub/grub.cfg /mnt/loop2p1/boot/grub/.grub.cfg
ln -s /mnt/loop2p1/boot/grub /mnt/loop2p1/boot/grub2

${GRUB_INSTALL} --boot-directory=/mnt/loop2p1/boot /dev/loop2 >/dev/null 2>&1
if [ $? != 0 ]; then 
    echo fail
    bvm_cleanup
    rm -rf $TMPDIR
    exit 1
fi

echo done

echo -n "Creating sys.conf... "
mkdir -p /mnt/loop2p1/brix/conf
cat << EOF >/mnt/loop2p1/brix/conf/sys.conf
key-data = info.vkx
use-dcf = yes
oem-id = brix
EOF
echo done

if [ x$BVM_MKIMG_DCF != x ]; then
  echo -n "Installing ${BVM_MKIMG_DCF##*/}... "
  mkdir /mnt/loop2p1/brix/conf/dcf
  cp $BVM_MKIMG_DCF /mnt/loop2p1/brix/conf/dcf/dcf.xml
  echo -n dcf.xml >/mnt/loop2p1/brix/conf/dcf/index
  echo done
fi

if [ x$BVM_MKIMG_VKX != x ]; then
  echo -n "Installing ${BVM_MKIMG_VKX##*/}... "
  cp $BVM_MKIMG_VKX /mnt/loop2p1/brix/conf/info.vkx
  echo done
fi

if [ x$BVM_MKIMG_VKR != x ]; then
  echo -n "Encrypting and installing ${BVM_MKIMG_VKR##*/}... "
  cp $BVM_MKIMG_VKR ${TMPDIR}/info.vkr
  encrypt-vkr -o ${TMPDIR} ${TMPDIR}/info.vkr
  if [ $? != 0 ]; then 
    echo fail
    echo Encrypting $${BVM_MKIMG_VKR##*/} failed
    exit 1
  fi
  cp ${TMPDIR}/info.vkx /mnt/loop2p1/brix/conf/info.vkx
  echo done
fi

echo -n "Unmount file systems... "
bvm_cleanup
echo done

touch ${BVM_MKIMG_OUTPUT_VMDK}
if [ $? != 0 ]; then 
  bvm_cleanup
  rm -rf $TMPDIR
  exit 1
fi    

echo -n "Converting to vmdk... "
sync
qemu-img convert -f raw -O vmdk ${TMPDIR}/${OUTPUT_IMG} ${BVM_MKIMG_OUTPUT_VMDK}
if [ $? != 0 ]; then 
  echo fail
  bvm_cleanup
  rm -rf $TMPDIR
  exit 1
fi
echo done

echo "Operation ended" `date`

rm -rf $TMPDIR
exit 0
