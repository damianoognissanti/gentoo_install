#!/bin/bash
# Very simple script to copy relevant configs from earlier generation.

RUUID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
COPYFROM="gentoo_YYYYMMDD_HHMM"

mkdir -p Mount
sudo mount /dev/disk/by-uuid/"$RUUID" Mount/

cp -a Mount/$COPYFROM/home/damiano/.config/{google-chrome,nvim} .config/
cp -a Mount/$COPYFROM/home/damiano/.cache/{thunderbird,google-chrome} .cache/
cp -a Mount/$COPYFROM/home/damiano/{.thunderbird,Passwords.kdbx,Pictures,.bashrc} .
umount Mount
