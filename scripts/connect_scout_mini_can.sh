#!/usr/bin/env bash
set -Eeuo pipefail

# SCOUT MINI / CANable 接続・再接続時セットアップ
#
# CANable (gs_usb) を自動検出して設定する。
# AGX Orin 内蔵CAN (mttcan) は対象外。
#
# 実行:
#   ./connect_scout_mini_can.sh

BITRATE=500000
TX_QUEUE_LEN=1000
WAIT_SECONDS=5

if [[ ${EUID} -ne 0 ]]; then
  echo "CAN設定のため管理者権限を取得します..."
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

echo "[1/6] gs_usb を読み込みます..."
modprobe gs_usb

echo "[2/6] CANable (gs_usb) を検索します..."

CAN_IF=""

for ((i=1; i<=WAIT_SECONDS*10; i++)); do
  if CAN_IF="$(find_gs_usb_can)"; then
    break
  fi

  CAN_IF=""
  sleep 0.1
done

if [[ -z "${CAN_IF}" ]]; then
  echo "エラー: CANable (gs_usb) が見つかりません。" >&2
  echo >&2
  echo "USB-CANを接続し、以下を確認してください:" >&2
  echo "  lsusb" >&2
  echo "  ip -details link show type can" >&2
  echo >&2
  echo "CANドライバ確認:" >&2
  echo '  for c in /sys/class/net/can*; do' >&2
  echo '    echo "=== $(basename "$c") ==="' >&2
  echo '    basename "$(readlink -f "$c/device/driver")" 2>/dev/null || true' >&2
  echo '  done' >&2
  exit 1
fi

echo "SCOUT MINI用CANableを検出しました: ${CAN_IF}"

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
echo "[3/6] ${CAN_IF} を停止します..."
ip link set "${CAN_IF}" down 2>/dev/null || true

echo "[4/6] ${CAN_IF} を ${BITRATE} bit/s で設定します..."
ip link set "${CAN_IF}" type can bitrate "${BITRATE}"
ip link set "${CAN_IF}" txqueuelen "${TX_QUEUE_LEN}"
ip link set "${CAN_IF}" up

echo "[5/6] 状態を確認します..."
DETAIL="$(ip -details -statistics link show "${CAN_IF}")"
printf '%s\n' "${DETAIL}"

if ! grep -q "bitrate ${BITRATE}" <<<"${DETAIL}"; then
  echo "エラー: ビットレート ${BITRATE} の設定を確認できませんでした。" >&2
  exit 1
fi

if ! grep -q "can state ERROR-ACTIVE" <<<"${DETAIL}"; then
  echo "警告: CAN状態が ERROR-ACTIVE ではありません。" >&2
  echo "USBの抜き差し、車両電源、CAN配線を確認してください。" >&2
  exit 1
fi

echo "[6/6] 設定完了"

echo
echo "SCOUT MINI CAN interface:"
echo "  ${CAN_IF}"

echo
echo "受信確認:"
echo "  candump ${CAN_IF}"

echo
echo "ROS 2起動例:"
echo "  ros2 launch scout_base scout_mini_base.launch.py port_name:=${CAN_IF}"
