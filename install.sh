#!/bin/bash
# (C) Adafruit Industries, Creative Commons 3.0 - Attribution Share Alike
#
# Instructions!
# cd ~
# wget https://raw.githubusercontent.com/unematiii/pitft-st7789/main/install.sh
# chmod +x install.sh
# sudo ./install.sh

if [ $(id -u) -ne 0 ]; then
    echo "Installer must be run as root."
    echo "Try 'sudo bash $0'"
    exit 1
fi

ADAFRUIT_GITHUB=https://raw.githubusercontent.com/adafruit/Raspberry-Pi-Installer-Scripts/master
UPDATE_DB=false
UNINSTALL=false

ST7789_MODULE=("Makefile" "fb_st7789v.c" "fbtft.h")

warning() {
    echo WARNING : $1
}

############################ Script assisters ############################

# Given a list of strings representing options, display each option
# preceded by a number (1 to N), display a prompt, check input until
# a valid number within the selection range is entered.
selectN() {
    for ((i = 1; i <= $#; i++)); do
        echo $i. ${!i}
    done
    echo
    REPLY=""
    while :; do
        echo -n "SELECT 1-$#: "
        read
        if [[ $REPLY -ge 1 ]] && [[ $REPLY -le $# ]]; then
            return $REPLY
        fi
    done
}

function print_version() {
    echo "Adafruit PiTFT Helper v2.1.0"
    exit 1
}

function print_help() {
    echo "Usage: $0 "
    echo "    -h            Print this help"
    echo "    -v            Print version information"
    echo "    -u [homedir]  Specify path of primary user's home directory (defaults to /home/pi)"
    exit 1
}

group=ADAFRUIT
function info() {
    system="$1"
    group="${system}"
    shift
    FG="1;32m"
    BG="40m"
    echo -e "[\033[${FG}\033[${BG}${system}\033[0m] $*"
}

function bail() {
    FG="1;31m"
    BG="40m"
    echo -en "[\033[${FG}\033[${BG}${group}\033[0m] "
    if [ -z "$1" ]; then
        echo "Exiting due to error"
    else
        echo "Exiting due to error: $*"
    fi
    exit 1
}

function ask() {
    # http://djm.me/ask
    while true; do

        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question
        read -p "$1 [$prompt] " REPLY

        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi

        # Check if the reply is valid
        case "$REPLY" in
        Y* | y*) return 0 ;;
        N* | n*) return 1 ;;
        esac
    done
}

function has_repo() {
    # Checks for the right raspbian repository
    # http://mirrordirector.raspbian.org/raspbian/ stretch main contrib non-free rpi firmware
    if [[ $(grep -h ^deb /etc/apt/sources.list /etc/apt/sources.list.d/* | grep "mirrordirector.raspbian.org") ]]; then
        return 0
    else
        return 1
    fi
}

progress() {
    count=0
    until [ $count -eq $1 ]; do
        echo -n "..." && sleep 1
        ((count++))
    done
    echo
}

sysupdate() {
    if ! $UPDATE_DB; then
        # echo "Checking for correct software repositories..."
        # has_repo || { warning "Missing Apt repo, please add deb http://mirrordirector.raspbian.org/raspbian/ stretch main contrib non-free rpi firmware to /etc/apt/sources.list.d/raspi.list" && exit 1; }
        echo "Updating apt indexes..." && progress 3 &
        sudo apt update 1>/dev/null || { warning "Apt failed to update indexes!" && exit 1; }
        sudo apt-get update 1>/dev/null || { warning "Apt failed to update indexes!" && exit 1; }
        echo "Reading package lists..."
        progress 3 && UPDATE_DB=true
    fi
}

# Given a filename, a regex pattern to match and a replacement string,
# perform replacement if found, else append replacement to end of file.
# (# $1 = filename, $2 = pattern to match, $3 = replacement)
reconfig() {
    grep $2 $1 >/dev/null
    if [ $? -eq 0 ]; then
        # Pattern found; replace in file
        sed -i "s/$2/$3/g" $1 >/dev/null
    else
        # Not found; append (silently)
        echo $3 | sudo tee -a $1 >/dev/null
    fi
}

############################ Sub-Scripts ############################

function softwareinstall() {
    echo "Installing Pre-requisite Software...This may take a few minutes!"
    apt-get install -y device-tree-compiler 1>/dev/null || { warning "Apt failed to install software!" && exit 1; }
}

# Remove any old flexfb/fbtft stuff
function uninstall_bootconfigtxt() {
    if grep -q "pitft" "/boot/config.txt"; then
        echo "Already have an pitft section in /boot/config.txt."
        echo "Removing old section..."
        cp /boot/config.txt /boot/configtxt.bak
        sed -i -e "/^# --- pitft/,/^# --- end pitft/d" /boot/config.txt
    fi
}

# update /boot/config.txt with appropriate values
function update_configtxt() {
    uninstall_bootconfigtxt

    if [ "${pitfttype}" == "st7789_240x320" ]; then
        wget -P overlays/ "$ADAFRUIT_GITHUB/overlays/st7789v_240x320-overlay.dts"
        dtc -@ -I dts -O dtb -o /boot/overlays/drm-st7789v_240x320.dtbo overlays/st7789v_240x320-overlay.dts
        overlay="dtoverlay=drm-st7789v_240x320,rotate=${pitftrot},fps=30"
    fi

    if [ "${pitfttype}" == "st7789_240x240" ]; then
        wget -P overlays/ "$ADAFRUIT_GITHUB/overlays/minipitft13-overlay.dts"
        dtc -@ -I dts -O dtb -o /boot/overlays/drm-minipitft13.dtbo overlays/minipitft13-overlay.dts
        overlay="dtoverlay=drm-minipitft13,rotate=${pitftrot},fps=60"
    fi

    if [ "${pitfttype}" == "st7789_240x135" ]; then
        wget -P overlays/ "$ADAFRUIT_GITHUB/overlays/minipitft114-overlay.dts"
        dtc -@ -I dts -O dtb -o /boot/overlays/drm-minipitft114.dtbo overlays/minipitft114-overlay.dts
        overlay="dtoverlay=drm-minipitft114,rotation=${pitftrot},fps=60"
    fi

    # any/all st7789's need their own kernel driver
    if [ "${pitfttype}" == "st7789_240x240" ] || [ "${pitfttype}" == "st7789_240x320" ] || [ "${pitfttype}" == "st7789_240x135" ]; then
        echo "############# UPGRADING KERNEL ###############"
        sudo apt update || { warning "Apt failed to update itself!" && exit 1; }
        sudo apt-get upgrade || { warning "Apt failed to install software!" && exit 1; }
        apt-get install -y raspberrypi-kernel-headers 1>/dev/null || { warning "Apt failed to install software!" && exit 1; }
        [ -d /lib/modules/$(uname -r)/build ] || { warning "Kernel was updated, please reboot now and re-run script!" && exit 1; }

        echo "############# COMPILING DRIVERS ###############"
        for src_file in "${ST7789_MODULE[@]}"
        do
            wget -P st7789_module/ "$ADAFRUIT_GITHUB/st7789_module/$src_file"
        done

        pushd st7789_module
        make -C /lib/modules/$(uname -r)/build M=$(pwd) modules || { warning "Apt failed to compile ST7789V drivers!" && exit 1; }
        mv /lib/modules/$(uname -r)/kernel/drivers/staging/fbtft/fb_st7789v.ko /lib/modules/$(uname -r)/kernel/drivers/staging/fbtft/fb_st7789v.BACK
        mv fb_st7789v.ko /lib/modules/$(uname -r)/kernel/drivers/staging/fbtft/fb_st7789v.ko
        popd
    fi

    date=$(date)

    cat >>/boot/config.txt <<EOF
# --- pitft $date ---
dtparam=spi=on
dtparam=i2c1=on
dtparam=i2c_arm=on
$overlay
# --- end pitft $date ---
EOF
}

####################################################### MAIN
target_homedir="/home/pi"

clear
echo "This script downloads and installs"
echo "PiTFT Support using userspace touch"
echo "controls and a DTO for display drawing."
echo "one of several configuration files."
echo "Run time of up to 5 minutes. Reboot required!"
echo

echo "Select configuration:"
selectN "PiTFT Mini 1.3\" or 1.54\" display (240x240) - WARNING! WILL UPGRADE YOUR KERNEL TO LATEST" \
    "MiniPiTFT 1.14\" display (240x135) - WARNING! WILL UPGRADE YOUR KERNEL TO LATEST" \
    "ST7789V 2.0\" no touch (240x320) - WARNING! WILL UPGRADE YOUR KERNEL TO LATEST" \
    "Uninstall PiTFT" \
    "Quit without installing"
PITFT_SELECT=$?
if [ $PITFT_SELECT -gt 8 ]; then
    exit 1
fi

if [ $PITFT_SELECT -eq 8 ]; then
    UNINSTALL=true
fi

if ! $UNINSTALL; then
    echo "Select rotation:"
    selectN "90 degrees (landscape)" \
        "180 degrees (portrait)" \
        "270 degrees (landscape)" \
        "0 degrees (portrait)"
    PITFT_ROTATE=$?
    if [ $PITFT_ROTATE -gt 4 ]; then
        exit 1
    fi
fi

PITFT_ROTATIONS=("90" "180" "270" "0")
PITFT_TYPES=("st7789_240x240" "st7789_240x135" "st7789_240x320")
WIDTH_VALUES=(240 240 320)
HEIGHT_VALUES=(240 135 240)

args=$(getopt -uo 'hvri:o:b:u:' -- $*)
[ $? != 0 ] && print_help
set -- $args

for i; do
    case "$i" in

    -h)
        print_help
        ;;
    -v)
        print_version
        ;;
    -u)
        target_homedir="$2"
        echo "Homedir = ${2}"
        shift
        shift
        ;;
    esac
done

# check init system (technique borrowed from raspi-config):
info PITFT 'Checking init system...'
if command -v systemctl >/dev/null && systemctl | grep -q '\-\.mount'; then
    echo "Found systemd"
    SYSTEMD=1
elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
    echo "Found sysvinit"
    SYSTEMD=0
else
    bail "Unrecognised init system"
fi

if grep -q boot /proc/mounts; then
    echo "/boot is mounted"
else
    echo "/boot must be mounted. if you think it's not, quit here and try: sudo mount /dev/mmcblk0p1 /boot"
    if ask "Continue?"; then
        echo "Proceeding."
    else
        bail "Aborting."
    fi
fi

if [[ ! -e "$target_homedir" || ! -d "$target_homedir" ]]; then
    bail "$target_homedir must be an existing directory (use -u /home/foo to specify)"
fi

if ! $UNINSTALL; then
    pitfttype=${PITFT_TYPES[$PITFT_SELECT - 1]}
    pitftrot=${PITFT_ROTATIONS[$PITFT_ROTATE - 1]}
    touchrot=$pitftrot

    if [ "${pitfttype}" != "st7789_240x240" ] && [ "${pitfttype}" != "st7789_240x320" ] && [ "${pitfttype}" != "st7789_240x135" ]; then
        echo "Type must be one of:"
        echo "  'st7789_240x240' (1.54\" or 1.3\" no touch)"
        echo "  'st7789_320x240' (2.0\" no touch)"
        echo "  'st7789_240x135' (1.14\" no touch)"
        echo
        print_help
    fi

    info PITFT "System update"
    sysupdate || bail "Unable to apt-get update"

    info PITFT "Installing software..."
    softwareinstall || bail "Unable to install software"

    info PITFT "Updating /boot/config.txt..."
    update_configtxt || bail "Unable to update /boot/config.txt"
else
    info PITFT "Uninstalling PiTFT"
    uninstall_bootconfigtxt
fi

info PITFT "Success!"
echo
echo "Settings take effect on next boot."
echo
echo -n "REBOOT NOW? [y/N] "
read
if [[ ! "$REPLY" =~ ^(yes|y|Y)$ ]]; then
    echo "Exiting without reboot."
    exit 0
fi
echo "Reboot started..."
reboot
exit 0
