#!/system/bin/sh
#
# Helper script to prepare runtime directories and mounts
#
sleep 1
mount -w /product > /dev/null
mount -w /vendor > /dev/null
mount -w /odm > /dev/null
mount -w /system_ext > /dev/null
mount -w /system_root > /dev/null

sleep 1
umount /product > /dev/null
umount /vendor > /dev/null
umount /odm > /dev/null
umount /system_ext > /dev/null
umount /system_root > /dev/null

sleep 1
mkdir /data/media
mkdir /tmp/install
mkdir /tmp/install/bin

# Runtime CPU performance boost to eliminate UI lag
for cpu in 0 1 2 3 4 5 6 7; do
    echo 1 > /sys/devices/system/cpu/cpu${cpu}/online 2>/dev/null
    echo performance > /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor 2>/dev/null
done
echo 1056000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null
echo 1324800 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq 2>/dev/null

# Ensure touch modules are accessible at /vendor/lib/modules/
if [ -d /vendor/lib/modules/1.1 ]; then
    for ko in /vendor/lib/modules/1.1/*.ko; do
        [ -f "$ko" ] && ln -sf "$ko" /vendor/lib/modules/ 2>/dev/null
    done
fi

exit 0
#
