#!/usr/bin/env bash
set -Eeuo pipefail

# SCOUT MINI / CANable 接続リセット
#
# CANable (gs_usb) を自動検出してリセットする。
# AGX Orin 内蔵CAN (mttcan) は対象外。
#
# 実行:
#   ./reset_scout_mini_can.sh

BITRATE=500000
TX_QUEUE_LEN=1000
WAIT_SECONDS=5

if [[ ${EUID} -ne 0 ]]; then
  echo "CANリセットのため管理者権限を取得します..."
  exec sudo -- "$(readlink -f "$0")" "$@"
fi

find_gs_usb_can() {
  local path
  local driver

  for path in /sys/class/net/can*; do
    [[ -e "${path}" ]] || continue

    driver="$(
      basename "$(readlink -f "${path}/device/driver")" 2>/dev/null || true
    )"

    if [[ "${driver}" == "gs_usb" ]]; then
      basename "${path}"
      return 0
    fi
  done

  return 1
}

echo "[1/7] CANを使用している確認用プロセスを停止します..."
pkill -x candump 2>/dev/null || true
pkill -x cangen 2>/dev/null || true

echo "[2/7] 現在のCANable (gs_usb) を検索します..."

CAN_IF="$(find_gs_usb_can || true)"

if [[ -n "${CAN_IF}" ]]; then
  echo "現在のCANableを検出しました: ${CAN_IF}"

  echo "[3/7] ${CAN_IF} を停止します..."
  ip link set "${CAN_IF}" down 2>/dev/null || true
else
  echo "現在は gs_usb のCANインターフェースが見つかりません。"
  echo "[3/7] 停止処理をスキップします..."
fi

echo "[4/7] gs_usb ドライバを再読み込みします..."
modprobe -r gs_usb 2>/dev/null || true
sleep 1
modprobe gs_usb

echo "[5/7] CANable (gs_usb) の再生成を待ちます..."

CAN_IF=""

for ((i=1; i<=WAIT_SECONDS*10; i++)); do
  if CAN_IF="$(find_gs_usb_can)"; then
    break
  fi

  CAN_IF=""
  sleep 0.1
done

if [[ -z "${CAN_IF}" ]]; then
  echo "エラー: CANable (gs_usb) が再生成されませんでした。" >&2
  echo >&2
  echo "USB-CANを一度抜き差ししてから、次を実行してください:" >&2
  echo "  ./connect_scout_mini_can.sh" >&2
  echo >&2
  echo "確認コマンド:" >&2
  echo "  lsusb" >&2
  echo "  ip -details link show type can" >&2
  exit 1
fi

echo "再生成されたCANableを検出しました: ${CAN_IF}"

echo
echo "現在のCANインターフェース:"
for path in /sys/class/net/can*; do
  [[ -e "${path}" ]] || continue

  ifname="$(basename "${path}")"
  driver="$(
    basename "$(readlink -f "${path}/device/driver")" 2>/dev/null || true
  )"

  printf "  %-6s driver=%s\n" "${ifname}" "${driver:-unknown}"
done

echo
echo "[6/7] ${CAN_IF} を再設定します..."
ip link set "${CAN_IF}" down 2>/dev/null || true
ip link set "${CAN_IF}" type can bitrate "${BITRATE}"
ip link set "${CAN_IF}" txqueuelen "${TX_QUEUE_LEN}"
ip link set "${CAN_IF}" up

echo "[7/7] 状態を確認します..."
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
echo "CANableの接続リセットが完了しました。"
echo
echo "SCOUT MINI CAN interface:"
echo "  ${CAN_IF}"

echo
echo "受信確認:"
echo "  candump ${CAN_IF}"

echo
echo "ROS 2起動例:"
echo "  ros2 launch scout_base scout_mini_base.launch.py port_name:=${CAN_IF}"
