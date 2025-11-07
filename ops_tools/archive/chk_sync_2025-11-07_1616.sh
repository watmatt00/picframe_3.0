#!/bin/bash

rclone_config="/home/pi/.config/rclone/rclone.conf"
rclone_remotea="kfphotos:album/frame"
rclown_remote="kfgdrive:album/frame"
ldir="./Pictures/frame"
gdir_count=$(sudo rclone --config "$rclone_config" ls "$rclone_remote" |wc -l)
#ldir_count=$(ls ./Pictures/frame |wc -l)
ldir_count=$(ls $ldir |wc -l)


clear
clear
echo
echo
echo
echo
echo "Google Directory file count: $gdir_count"
echo "Local directory file count: $ldir_count"
echo
echo
echo
echo

# Compare the variables
# Compare the variables
if [ "$gdir_count" -eq "$ldir_count" ]; then

    echo -e "\e[320mDirectorys are in sync.\e[0m"
    echo
    echo
    echo
    echo

else
    echo -e "\e[31mDirectorys are NOT in sync.\e[0m"
    echo
    echo
    echo
    echo
#    rclone --config "$rclone_config" sync $rclone_remote $ldir
fi


