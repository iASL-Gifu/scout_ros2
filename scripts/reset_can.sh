#!/usr/bin/env bash
set -Eeuo pipefail

# SCOUT MINI / CANable 接続リセット
# 実行:
#   ./reset_scount_mini_can.sh
#   ./reset_scount_mini_can.sh can1

CAN_IF="${1:-can0}"
BITRATE=500000
TX_QUEUE_LEN=1000
WAIT_SECONDS=5

if [[ ${EUID} -ne 0 ]]; then
  echo "CANリセットのため管理者権限を取得します..."
  exec sudo -- "$(readlink -f "$0")" "$@"
fi

echo "[1/6] CANを使用している確認用プロセスを停止します..."
pkill -x candump 2>/dev/null || true
pkill -x cangen 2>/dev/null || true

echo "[2/6] ${CAN_IF} を停止します..."
if ip link show "${CAN_IF}" >/dev/null 2>&1; then
  ip link set "${CAN_IF}" down 2>/dev/null || true
fi

echo "[3/6] gs_usb ドライバを再読み込みします..."
modprobe -r gs_usb 2>/dev/null || true
sleep 1
modprobe gs_usb

echo "[4/6] ${CAN_IF} の再生成を待ちます..."
for ((i=1; i<=WAIT_SECONDS*10; i++)); do
  if ip link show "${CAN_IF}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! ip link show "${CAN_IF}" >/dev/null 2>&1; then
  echo "エラー: ${CAN_IF} が再生成されませんでした。" >&2
  echo "USB-CANを一度抜き差ししてから、次を実行してください:" >&2
  echo "  ./connect_scount_mini_can.sh ${CAN_IF}" >&2
  exit 1
fi

echo "[5/6] ${CAN_IF} を再設定します..."
ip link set "${CAN_IF}" down 2>/dev/null || true
ip link set "${CAN_IF}" type can bitrate "${BITRATE}"
ip link set "${CAN_IF}" txqueuelen "${TX_QUEUE_LEN}"
ip link set "${CAN_IF}" up

echo "[6/6] 状態を確認します..."
DETAIL="$(ip -details -statistics link show "${CAN_IF}")"
printf '%s\n' "${DETAIL}"

if ! grep -q "bitrate ${BITRATE}" <<<"${DETAIL}"; then
  echo "エラー: ビットレート ${BITRATE} の設定を確認できませんでした。" >&2
  exit 1
fi

if ! grep -q "can state ERROR-ACTIVE" <<<"${DETAIL}"; then
  echo "警告: CAN状態が ERROR-ACTIVE ではありません。" >&2
  echo "USB-CANの抜き差し、車両電源、CAN配線を確認してください。" >&2
  exit 1
fi

echo
echo "${CAN_IF} の接続リセットが完了しました。"
echo "受信確認:"
echo "  candump ${CAN_IF}"
