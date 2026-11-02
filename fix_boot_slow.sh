#!/bin/sh
# 一加 13T (PKX110) 开机慢修复：从传感器 HAL 的必需清单中移除固件不会上报的 lux_aod
# 用法: ./fix_boot_slow.sh [--reboot]
#   --reboot  修改后自动重启并打印开机各阶段耗时
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$DIR/backup"
REMOTE_LIST=/mnt/vendor/persist/sensors/sensors_list.txt
REMOTE_TMP=/data/local/tmp/sensors_bak
SENSOR=lux_aod

rsu() { adb shell "su -c '$1'" | tr -d '\r'; }

adb get-state >/dev/null 2>&1 || { echo "未检测到 adb 设备"; exit 1; }
[ "$(rsu id | grep -c 'uid=0')" = "1" ] || { echo "无法获取 root（su）"; exit 1; }
[ "$(rsu "[ -f $REMOTE_LIST ] && echo ok")" = "ok" ] || { echo "找不到 $REMOTE_LIST"; exit 1; }

echo "设备: $(adb shell getprop ro.product.model | tr -d '\r')  $(adb shell getprop ro.build.display.id | tr -d '\r')"

if [ "$(rsu "grep -cx $SENSOR $REMOTE_LIST || true")" = "0" ]; then
    echo "清单中已没有 ${SENSOR}，无需修改（已修复过）"
else
    mkdir -p "$BACKUP_DIR"
    STAMP=$(date +%Y%m%d-%H%M%S)
    rsu "mkdir -p $REMOTE_TMP && cp -p $REMOTE_LIST $REMOTE_TMP/sensors_list.txt.$STAMP && chmod 644 $REMOTE_TMP/sensors_list.txt.$STAMP" >/dev/null
    adb pull "$REMOTE_TMP/sensors_list.txt.$STAMP" "$BACKUP_DIR/sensors_list.txt.$STAMP" >/dev/null
    [ -f "$BACKUP_DIR/sensors_list.txt.orig" ] || cp "$BACKUP_DIR/sensors_list.txt.$STAMP" "$BACKUP_DIR/sensors_list.txt.orig"
    echo "已备份: $BACKUP_DIR/sensors_list.txt.$STAMP (md5 $(md5 -q "$BACKUP_DIR/sensors_list.txt.$STAMP"))"

    # 用 cat 覆盖而不是替换文件，保留原 inode 的属主、权限和 SELinux 标签
    rsu "grep -vx $SENSOR $REMOTE_LIST > $REMOTE_TMP/new.txt; cat $REMOTE_TMP/new.txt > $REMOTE_LIST && sync"
    [ "$(rsu "grep -cx $SENSOR $REMOTE_LIST || true")" = "0" ] || { echo "修改失败"; exit 1; }
    echo "已从清单移除 $SENSOR"
fi

rsu "ls -laZ $REMOTE_LIST; md5sum $REMOTE_LIST"

if [ "$1" = "--reboot" ]; then
    echo "正在重启并等待开机完成..."
    adb reboot
    sleep 5
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
    adb logcat -b events -d | grep -E "boot_progress_(start|pms_ready|ams_ready|enable_screen)|sf_stop_bootanim"
    echo "（最后一列为开机后的毫秒数；修复前 ams_ready 约 50000，修复后约 13000）"
else
    echo "重启手机后生效"
fi
