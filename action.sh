#!/system/bin/sh 
# ============================================================================= 
# 方案 A 完美修正版：修復 LSPosed 慢速與 Zygisk 衝突誤報 
# ============================================================================= 
 
PATH=/system/bin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin:/debug_ramdisk:$PATH 
export PATH 
ZYGISKDIR="/data/adb/modules/zygisksu" 
LSPOSED_DIR="/data/adb/modules/zygisk_lsposed" 
[ -d "$LSPOSED_DIR" ] || LSPOSED_DIR="/data/adb/modules/lsposed" 
 
echo "[1] 徹底清理舊的 LSPosed 與 ZygiskSU 殘留行程與 Socket..." 
# 1. 精準清理所有進程變體 (包含 64 位元與 ptrace 注入器) 
for name in zygiskd zygiskd64 zygisk-ptrace zygisk-ptrace64 lspd; do 
    for p in $(pidof "$name" 2>/dev/null); do 
        kill -9 "$p" 2>/dev/null 
    done 
done 
pkill -9 -f "zygiskd" 2>/dev/null 
pkill -9 -f "zygisk-ptrace" 2>/dev/null 
pkill -9 -f "org.lsposed.lspd" 2>/dev/null 
killall -9 zygiskd zygiskd64 zygisk-ptrace lspd daemon 2>/dev/null 
sleep 1 
 
echo "[2] 刪除舊的狀態鎖與殘留通信節點 (防止衝突誤報)..." 
rm -f /data/adb/lspd/monitor 2>/dev/null 
rm -f /data/adb/lspd/lock 2>/dev/null 
rm -f /dev/*zygisk* /dev/.*zygisk* 2>/dev/null 
 
echo "[3] 重新啟動 ZygiskSU 守護進程..." 
if [ -d "$ZYGISKDIR" ]; then 
    cd "$ZYGISKDIR" || exit 1 
    setsid ./bin/zygiskd daemon </dev/null >/dev/null 2>&1 & 
    sleep 1 
    setsid ./bin/zygiskd service-stage </dev/null >/dev/null 2>&1 & 
    sleep 1 
else 
    echo "ERROR: 找不到 ZygiskSU 目錄 ($ZYGISKDIR)！" 
    exit 1 
fi 
 
echo "[4] 預先拉起 LSPosed 守護服務 (解決管理器打開卡慢問題)..." 
if [ -d "$LSPOSED_DIR" ]; then 
    if [ -f "$LSPOSED_DIR/service.sh" ]; then 
        ( cd "$LSPOSED_DIR" && setsid /system/bin/sh ./service.sh ) </dev/null >/dev/null 2>&1 & 
    elif [ -f "$LSPOSED_DIR/daemon.apk" ]; then 
        APP_PROC="/system/bin/app_process" 
        [ -x "$APP_PROC" ] || APP_PROC="/system/bin/app_process64" 
        Z_PID=$(pidof zygote64 zygote 2>/dev/null | awk '{print $1}') 
        B_CP=$(tr '\0' '\n' < /proc/"$Z_PID"/environ 2>/dev/null | grep -m1 '^BOOTCLASSPATH=') 
        setsid /system/bin/sh -c " 
            cd '$LSPOSED_DIR' 
            [ -n '$B_CP' ] && export $B_CP 
            exec $APP_PROC -Djava.class.path='$LSPOSED_DIR/daemon.apk' -Xnoimage-dex2oat /system/bin --nice-name=lspd org.lsposed.lspd.Main 
        " </dev/null >/dev/null 2>&1 & 
    fi 
    sleep 1 
fi 
 
echo "======================================================" 
echo "✅ 流程已就緒，觸發平滑熱重啟 (Soft Reboot)..." 
echo "======================================================" 
 
# 關鍵：同時重啟主次 Zygote，並放在腳本最末尾執行 
setprop ctl.restart zygote_secondary 2>/dev/null 
setprop ctl.restart zygote
