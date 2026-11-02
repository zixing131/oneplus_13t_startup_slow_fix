#!/bin/sh
# 将 /mnt/vendor/persist/sensors/sensors_list.txt 还原为修改前的版本（需 root）
# 用法: ./restore_boot_slow.sh [备份文件]   默认使用 backup/sensors_list.txt.orig
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$DIR/backup/sensors_list.txt.orig}"
REMOTE_LIST=/mnt/vendor/persist/sensors/sensors_list.txt
REMOTE_TMP=/data/local/tmp/sensors_list.restore

rsu() { adb shell "su -c '$1'" | tr -d '\r'; }

[ -s "$SRC" ] || { echo "备份文件不存在或为空: $SRC"; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "未检测到 adb 设备"; exit 1; }
[ "$(rsu id | grep -c 'uid=0')" = "1" ] || { echo "无法获取 root（su）"; exit 1; }

WANT=$(md5 -q "$SRC")
adb push "$SRC" "$REMOTE_TMP" >/dev/null
# 用 cat 覆盖而不是替换文件，保留原 inode 的属主、权限和 SELinux 标签
rsu "cat $REMOTE_TMP > $REMOTE_LIST && sync && rm -f $REMOTE_TMP"
GOT=$(rsu "md5sum $REMOTE_LIST" | awk '{print $1}')
[ "$GOT" = "$WANT" ] || { echo "还原后校验不一致: $GOT != $WANT"; exit 1; }

rsu "ls -laZ $REMOTE_LIST"
echo "已还原（md5 ${GOT}），重启手机后生效"
