#!/usr/bin/env bash
set -Eeuo pipefail

# SCOUT MINI / CANable 接続・再接続時セットアップ
# 実行: ./connect_scount_mini_can.sh [CANインターフェース名]
# 例:   ./connect_scount_mini_can.sh
#       ./connect_scount_mini_can.sh can1

CAN_IF="${1:-can0}"
BITRATE=500000
TX_QUEUE_LEN=1000
WAIT_SECONDS=5

if [[ ${EUID} -ne 0 ]]; then
  echo "CAN設定のため管理者権限を取得します..."
  exec sudo -- "$(readlink -f "$0")" "$@"
fi

echo "[1/5] gs_usb を読み込みます..."
modprobe gs_usb

echo "[2/5] ${CAN_IF} の生成を待ちます..."
for ((i=1; i<=WAIT_SECONDS*10; i++)); do
  if ip link show "${CAN_IF}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! ip link show "${CAN_IF}" >/dev/null 2>&1; then
  echo "エラー: ${CAN_IF} が見つかりません。" >&2
  echo "USB-CANを接続し、次のコマンドでデバイスを確認してください:" >&2
  echo "  lsusb" >&2
  echo "  ip link show" >&2
  exit 1
fi

echo "[3/5] ${CAN_IF} を停止して送信キューをリセットします..."
ip link set "${CAN_IF}" down 2>/dev/null || true

echo "[4/5] ${CAN_IF} を ${BITRATE} bit/s で設定します..."
ip link set "${CAN_IF}" type can bitrate "${BITRATE}"
ip link set "${CAN_IF}" txqueuelen "${TX_QUEUE_LEN}"
ip link set "${CAN_IF}" up

echo "[5/5] 状態を確認します..."
DETAIL="$(ip -details -statistics link show "${CAN_IF}")"
printf '%s\n' "${DETAIL}"

if ! grep -q "bitrate ${BITRATE}" <<<"${DETAIL}"; then
  echo "エラー: ビットレートの設定を確認できませんでした。" >&2
  exit 1
fi

if ! grep -q "can state ERROR-ACTIVE" <<<"${DETAIL}"; then
  echo "警告: CAN状態が ERROR-ACTIVE ではありません。" >&2
  echo "USBの抜き差し、車両電源、CAN配線を確認してください。" >&2
  exit 1
fi

echo
echo "${CAN_IF} の設定が完了しました。"
echo "SCOUT MINIの受信確認:"
echo "  candump ${CAN_IF}"
