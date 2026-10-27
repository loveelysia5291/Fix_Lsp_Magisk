#!/system/bin/sh
# 方案 A 修復版：解決背景行程卡死導致 su / MT 管理器 CPU 100% 空轉的問題

PATH=/system/bin:/vendor/bin:/data/adb/ksu/bin:$PATH
export PATH
ZYGISKDIR="/data/adb/modules/zygisksu"

echo "[1] 徹底清理舊的 LSPosed 與 ZygiskSU 殘留行程..."
killall -9 lspd daemon zygiskd 2>/dev/null
for PID in $(ps -A -o PID,NAME 2>/dev/null | grep -E 'lspd|zygiskd' | awk '{print $1}'); do
    kill -9 "$PID" 2>/dev/null
done
sleep 2 

echo "[2] 刪除舊的 LSPosed 狀態鎖定檔..."
rm -f /data/adb/lspd/monitor 2>/dev/null
rm -f /data/adb/lspd/lock 2>/dev/null

echo "[3] 重新啟動 ZygiskSU 守護行程 (已隔離 I/O 避免 CPU 飆高)..."
if [ -d "$ZYGISKDIR" ]; then
    cd "$ZYGISKDIR" || exit 1
    
    # 關鍵修正：使用 setsid + </dev/null >/dev/null 2>&1 徹底切斷終端機關聯，防止卡死
    setsid ./bin/zygiskd daemon </dev/null >/dev/null 2>&1 &
    sleep 2
    
    setsid ./bin/zygiskd service-stage </dev/null >/dev/null 2>&1 &
    sleep 1
else
    echo "ERROR: 找不到 ZygiskSU 目錄 ($ZYGISKDIR)！"
    exit 1
fi

echo "[4] 觸發系統級平滑軟重啟..."
# 呼 power 服務執行 soft restart，這會通知所有驅動釋放資源
su -c "setprop ctl.restart zygote"


echo "======================================================"
echo "✅ 流程已觸發，請等待手機重載 (Soft Reboot)。"
echo "======================================================"