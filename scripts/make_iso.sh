#!/usr/bin/env bash
# Copyright (c) 2018-2019 by Alain Maibach
# Licensed under the terms of the GPL v3

set -eu -o pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/bin:/usr/sbin

err_report() {
  echo "Error on line $@"
  if [ ${!buildir[@]} ]; then
    rm -rf ${buildir}
  fi
  printf "$0 Cleanly exited\n"
  exit 1
}

expandPath() {
  local path
  local -a pathElements resultPathElements
  IFS=':' read -r -a pathElements <<<"$1"
  : "${pathElements[@]}"
  for path in "${pathElements[@]}"; do
    : "$path"
    case $path in
      "~+"/*)
        path=$PWD/${path#"~+/"}
        ;;
      "~-"/*)
        path=$OLDPWD/${path#"~-/"}
        ;;
      "~"/*)
        path=$HOME/${path#"~/"}
        ;;
      "~"*)
        username=${path%%/*}
        username=${username#"~"}
        IFS=: read _ _ _ _ _ homedir _ < <(getent passwd "$username")
        if [[ $path = */* ]]; then
          path=${homedir}/${path#*/}
        else
          path=$homedir
        fi
        ;;
    esac
    resultPathElements+=( "$path" )
  done
  local result
  printf -v result '%s:' "${resultPathElements[@]}"
  printf '%s\n' "${result%:}"
}

centosISO="CentOS-7-x86_64-Minimal-1810.iso"
kickstart=""

usage (){
    local usage="$0 --dest /path/to/tarball/dir/"
    local options="
    --kickstart       [kickstart name or regex] --> (Mandatory)   Define the kickstart filename (or path regex) to use. It must be present in kickstarts direcotry.
    --base-isoname    [CentOS-X-isoname.iso]    --> (optional, default: ${centosISO}) Set which CentOS minimal iso to use.
    --help | -h                                 --> (optional)    Show this help.
    "
    printf "\n$usage\n$options\n" 2>&1
    exit $1
}

trap 'err_report ${LINENO}: \""$BASH_COMMAND"\" failed.' ERR

if [ $# -lt 1 ]; then
    usage 1
fi

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELFDIR="$(cd -P "$(dirname "$SOURCE")" && pwd )"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kickstart) kickstart="${2}"; shift 2;;
    --base-isoname) centosISO=${2}; shift 2;;
    --help|-h) usage 0 ; shift 2 ;;
    -*) printf "unknown option: $1\n" >&2 ; usage 1;;
    *) printf "unrecognized argument: $1\n" >&2; usage 1; shift 1;;
  esac
done

isoDir='/tmp/isoshare'

if [ "${kickstart}" = "" ]; then
	usage 1
fi

numberFound=$(find $SELFDIR/../kickstarts -type f -regextype posix-extended  -iregex ".*$kickstart$" |wc -l)
if [ $numberFound -gt 1 ]; then
  printf "\n$numberFound files found:\n\n$(find $SELFDIR/../ -type f -regextype posix-extended -iregex ".*$kickstart$"|xargs -I {} basename {}|grep -F '.cfg')\n\n"
  read -p 'Please enter the good filename > ' kickstart
  numberFound=$(find $SELFDIR/../kickstarts -type f -regextype posix-extended -iregex "$kickstart$" |wc -l)
  if [ $numberFound -gt 1 ]; then
    printf "\nYou entered a bad filename, exiting...\n"
    rm -fr $SELFDIR/../
    exit 1
  else
    kickstartpath=$(find $SELFDIR/../kickstarts -type f -regextype posix-extended -iregex ".*$kickstart\.cfg$")
  fi
else
  kickstartpath=$(find $SELFDIR/../kickstarts -type f -regextype posix-extended -iregex ".*$kickstart\.cfg$")
fi

if [ ! -f "$kickstartpath" ]; then
    printf "Unable to find file $kickstart\n"
    exit 1
fi

kickstartname="$(basename $kickstartpath | sed 's/.cfg//')"

if [ ! -d "$isoDir" ]; then
    mkdir -p "${isoDir}/"
fi

originalpath="$(pwd)"

buildir="$(mktemp -d -p ./)"
cd $buildir
buildir="$(pwd)"

workdir="$(mktemp -d)"

printf "System setup\n"
yum makecache fast
yum install --assumeyes --nogpgcheck --skip-broken deltarpm
yum clean all
yum install --assumeyes --nogpgcheck --skip-broken util-linux coreutils pykickstart sed curl grep createrepo genisoimage syslinux tk which rsync git

mkdir -vp ${workdir}/CentOS-7-respin/{CentOS-7-unpacked,CentOS-7-iso}

if [ ! -f ./CentOS-7-x86_64-Minimal.iso ]; then
    if [ ! -f "${originalpath}/${centosISO}" ]; then
        printf "Downloading CentOS 7 minimal iso from the Internet.\n"
        curl -k -# -L "http://isoredirect.centos.org/centos/7/isos/x86_64/${centosISO}" -o "${buildir}/CentOS-7-x86_64-Minimal.iso"
    else
      printf "Copying local file ${centosISO} .\n"
      rsync -vahP "${originalpath}/${centosISO}" "${buildir}/CentOS-7-x86_64-Minimal.iso"
    fi
fi

printf "Extracting CentOS original ISO ${centosISO}\n"
losetup -f &>/dev/null
install -d /mnt/ISO
mount -o loop ${buildir}/CentOS-7-x86_64-Minimal.iso /mnt/ISO
rsync -hP --recursive --delete --partial /mnt/ISO/* ${workdir}/CentOS-7-respin/CentOS-7-unpacked/ &>/dev/null

umount /mnt/ISO
rm -rf /mnt/ISO ${buildir}/CentOS-7-x86_64-Minimal.iso

printf "Creating ISO file repository\n"

pushd "${workdir}/CentOS-7-respin/CentOS-7-unpacked/" &>/dev/null

# Use these two lines to be able to disable YUM groups in kickstarts
repodata="$(grep -A 2 -i '<data type="group">' ./repodata/repomd.xml | grep -Eo 'repodata/.*\.xml')"
createrepo --update -g $repodata -o "${workdir}/CentOS-7-respin/CentOS-7-unpacked/" "${workdir}/CentOS-7-respin/CentOS-7-unpacked/"

popd &>/dev/null

volabel="${kickstartname}"

#####################
# setup legacy part #
#####################

#str2add="menu separator\n" ; \
#str2add="${str2add}\nlabel linux_${kickstartname}\n  menu label ^Install CentOS 7 for $kickstartname \n  kernel vmlinuz\n  append initrd=initrd.img inst.stage2=hd:LABEL=\"${volabel}\" ks=hd:LABEL=\"${volabel}\":/ks.cfg\n" ; \
#str2add="${str2add}\nmenu separator\n" ; \
#sed -i "/label check/i${str2add}" ${workdir}/CentOS-7-respin/CentOS-7-unpacked/isolinux/isolinux.cfg
cat > "${workdir}/CentOS-7-respin/CentOS-7-unpacked/isolinux/isolinux.cfg" << EOF
default vesamenu.c32
timeout 5

display boot.msg

# Clear the screen when exiting the menu, instead of leaving the menu displayed.
# For vesamenu, this means the graphical background is still displayed without
# the menu itself for as long as the screen remains in graphics mode.
menu clear
menu background splash.png
menu title CentOS 7
menu vshift 8
menu rows 18
menu margin 8
#menu hidden
menu helpmsgrow 15
menu tabmsgrow 13

# Border Area
menu color border * #00000000 #00000000 none

# Selected item
menu color sel 0 #ffffffff #00000000 none

# Title bar
menu color title 0 #ff7ba3d0 #00000000 none

# Press [Tab] message
menu color tabmsg 0 #ff3a6496 #00000000 none

# Unselected menu item
menu color unsel 0 #84b8ffff #00000000 none

# Selected hotkey
menu color hotsel 0 #84b8ffff #00000000 none

# Unselected hotkey
menu color hotkey 0 #ffffffff #00000000 none

# Help text
menu color help 0 #ffffffff #00000000 none

# A scrollbar of some type? Not sure.
menu color scrollbar 0 #ffffffff #ff355594 none

# Timeout msg
menu color timeout 0 #ffffffff #00000000 none
menu color timeout_msg 0 #ffffffff #00000000 none

# Command prompt text
menu color cmdmark 0 #84b8ffff #00000000 none
menu color cmdline 0 #ffffffff #00000000 none

# Do not display the actual menu unless the user presses a key. All that is displayed is a timeout message.

menu tabmsg Press Tab for full configuration options on menu items.

menu separator # insert an empty line
menu separator # insert an empty line

label linux_${kickstartname}
  menu label ^Install CentOS 7 for ${kickstartname}
<<<<<<< 4ff20bf26c8b887a9f297d72326d7ef53b045bf7
=======
  menu default
>>>>>>> Add UEFI support
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${volabel} ks=hd:LABEL=${volabel}:/ks.cfg

menu separator

label check
  menu label Test this ^media & install CentOS 7 for ${kickstartname}
<<<<<<< 4ff20bf26c8b887a9f297d72326d7ef53b045bf7
=======
>>>>>>> Add UEFI support
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${volabel} rd.live.check quiet

menu separator # insert an empty line

# utilities submenu
menu begin ^Troubleshooting
  menu title Troubleshooting

label vesa
  menu indent count 5
  menu label Install CentOS 7 in ^basic graphics mode
  text help
    Try this option out if you're having trouble installing
    CentOS 7.
  endtext
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${volabel} xdriver=vesa nomodeset quiet

label rescue
  menu indent count 5
  menu label ^Rescue a CentOS system
  text help
    If the system will not boot, this lets you access files
    and edit config files to try to get it booting again.
  endtext
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${volabel} rescue quiet

label memtest
  menu label Run a ^memory test
  text help
    If your system is having issues, a problem with your
    system's memory may be the cause. Use this utility to
    see if the memory is working correctly.
  endtext
  kernel memtest

menu separator # insert an empty line

label local
  menu label Boot from ^local drive
  localboot 0xffff

menu separator # insert an empty line
menu separator # insert an empty line

label returntomain
  menu label Return to ^main menu
  menu exit

menu end
EOF

##################
# Setup EFI part #
##################

if [ -f "${kickstartpath}" ]; then
    cp -a "${kickstartpath}" ${workdir}/CentOS-7-respin/CentOS-7-unpacked/uefi-ks.cfg
    mkdir EFI/
    chmod 644 ${workdir}/CentOS-7-respin/CentOS-7-unpacked/images/efiboot.img
    #mknod /dev/loop0 -m0777 b 7 0
    mount -o loop ${workdir}/CentOS-7-respin/CentOS-7-unpacked/images/efiboot.img EFI/
    cat > "EFI/EFI/BOOT/grub.cfg" << EOF
set default="0"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=5
### END /etc/grub.d/00_header ###

search --no-floppy --set=root -l '${volabel}'

### BEGIN /etc/grub.d/10_linux ###
menuentry 'Install CentOS 7 for ${kickstartname}' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} inst.ks=hd:LABEL=${volabel}:/uefi-ks.cfg text
        initrdefi /images/pxeboot/initrd.img
}
menuentry 'Test this media & install CentOS 7' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} rd.live.check quiet
        initrdefi /images/pxeboot/initrd.img
}
submenu 'Troubleshooting -->' {
        menuentry 'Install CentOS 7 in basic graphics mode' --class fedora --class gnu-linux --class gnu --class os {
                linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} xdriver=vesa nomodeset quiet
                initrdefi /images/pxeboot/initrd.img
        }
        menuentry 'Rescue a CentOS system' --class fedora --class gnu-linux --class gnu --class os {
                linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} rescue quiet
                initrdefi /images/pxeboot/initrd.img
        }
}
EOF
    umount EFI/
    chmod 444 ${workdir}/CentOS-7-respin/CentOS-7-unpacked/images/efiboot.img

    cat > "${workdir}/CentOS-7-respin/CentOS-7-unpacked/EFI/BOOT/grub.cfg" << EOF
set default="0"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=5
### END /etc/grub.d/00_header ###

search --no-floppy --set=root -l '${volabel}'

### BEGIN /etc/grub.d/10_linux ###
menuentry 'Install CentOS 7 for ${kickstartname}' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} inst.ks=hd:LABEL=${volabel}:/uefi-ks.cfg text
        initrdefi /images/pxeboot/initrd.img
}
menuentry 'Test this media & install CentOS 7' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} rd.live.check quiet
        initrdefi /images/pxeboot/initrd.img
}
submenu 'Troubleshooting -->' {
        menuentry 'Install CentOS 7 in basic graphics mode' --class fedora --class gnu-linux --class gnu --class os {
                linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} xdriver=vesa nomodeset quiet
                initrdefi /images/pxeboot/initrd.img
        }
        menuentry 'Rescue a CentOS system' --class fedora --class gnu-linux --class gnu --class os {
                linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${volabel} rescue quiet
                initrdefi /images/pxeboot/initrd.img
        }
}
EOF
    isoname="${kickstartname}.iso"
else
    isoname="${kickstartname}_legacyOnly.iso"
fi

########################
# Copy kickstart files #
########################

cp -a "${kickstartpath}" ${workdir}/CentOS-7-respin/CentOS-7-unpacked/ks.cfg

ksvalidator ${workdir}/CentOS-7-respin/CentOS-7-unpacked/ks.cfg ; if [ $? -ne 0 ]; then printf "Oops\n" ;rm -r $workdir; exit 1 ; fi

if [ -f "${workdir}/CentOS-7-respin/CentOS-7-unpacked/uefi-ks.cfg" ]; then
    ksvalidator ${workdir}/CentOS-7-respin/CentOS-7-unpacked/uefi-ks.cfg
    if [ $? -ne 0 ]; then
        rm -r $workdir
        exit 1
    fi
fi

##################################################
# Creating Bootable hybrid ISO (legacy and uefi) #
##################################################

genisoimage \
    -V "${volabel}" \
    -A "${volabel}" \
    -o "${isoDir}/${isoname}" \
    -joliet-long \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot -e images/efiboot.img \
    -no-emul-boot \
    -R -J -T \
    -q \
    "${workdir}/CentOS-7-respin/CentOS-7-unpacked"

printf "\nGiving to ${isoname} the ability to boot\n"
isohybrid --uefi "${isoDir}/${isoname}"

chmod 777 "${isoDir}/${isoname}"
#printf "Iso generated successfully in ${isoDir}/${isoname}\n"
rm -r $workdir "${buildir}"
