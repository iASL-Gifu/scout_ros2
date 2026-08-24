#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SCOUT MINI CAN startup script
#
# 安定した起動手順:
#
#   1. 車両電源をOFF
#   2. CANable (gs_usb) を確認
#   3. gs_usb をリセット
#   4. CANableを再検出
#   5. CANを500 kbit/sで設定
#   6. 車両電源をON
#   7. CANフレーム受信を確認
#   8. ROS 2起動可能状態にする
#
# AGX Orin内蔵CAN (mttcan) は使用しない。
# gs_usb のCANインターフェースだけを自動選択する。
#
# 実行:
#   ./scout_mini_can.sh
# ============================================================

BITRATE=500000
TX_QUEUE_LEN=1000

DEVICE_WAIT_SECONDS=5
CAN_RX_WAIT_SECONDS=10

# ============================================================
# Root
# ============================================================

if [[ ${EUID} -ne 0 ]]; then
  echo "CAN設定のため管理者権限を取得します..."
  exec sudo -- "$(readlink -f "$0")" "$@"
fi

# ============================================================
# Utility
# ============================================================

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

wait_for_gs_usb_can() {
  local can_if=""

  for ((i=1; i<=DEVICE_WAIT_SECONDS*10; i++)); do
    if can_if="$(find_gs_usb_can)"; then
      echo "${can_if}"
      return 0
    fi

    sleep 0.1
  done

  return 1
}

show_can_interfaces() {
  local path
  local ifname
  local driver

  echo
  echo "現在のCANインターフェース:"

  for path in /sys/class/net/can*; do
    [[ -e "${path}" ]] || continue

    ifname="$(basename "${path}")"

    driver="$(
      basename "$(readlink -f "${path}/device/driver")" 2>/dev/null || true
    )"

    printf "  %-6s driver=%s\n" \
      "${ifname}" \
      "${driver:-unknown}"
  done
}

wait_for_enter() {
  local message="$1"

  echo
  read -r -p "${message}"
}

# ============================================================
# STEP 1
# ============================================================

echo
echo "========================================"
echo "SCOUT MINI CAN STARTUP"
echo "========================================"
echo

echo "[1/8] 車両電源を確認します。"
echo
echo "SCOUT MINIの車両電源をOFFにしてください。"

wait_for_enter "車両電源をOFFにしたら Enter を押してください..."

# ============================================================
# STEP 2
# ============================================================

echo
echo "[2/8] CANableを確認します..."

modprobe gs_usb

CAN_IF="$(find_gs_usb_can || true)"

if [[ -z "${CAN_IF}" ]]; then
  echo
  echo "エラー: CANable (gs_usb) が見つかりません。" >&2
  echo
  echo "CANableをJetsonのUSBポートに接続してください。" >&2
  echo
  echo "確認コマンド:" >&2
  echo "  lsusb" >&2
  echo "  ip -details link show type can" >&2
  exit 1
fi

echo "CANableを検出しました: ${CAN_IF}"

show_can_interfaces

# ============================================================
# STEP 3
# ============================================================

echo
echo "[3/8] CANableを停止します..."

ip link set "${CAN_IF}" down 2>/dev/null || true

# candump / cangen が残っていれば停止
pkill -x candump 2>/dev/null || true
pkill -x cangen 2>/dev/null || true

# ============================================================
# STEP 4
# ============================================================

echo
echo "[4/8] gs_usbをリセットします..."

modprobe -r gs_usb 2>/dev/null || true

sleep 1

modprobe gs_usb

echo "gs_usbを再読み込みしました。"

# ============================================================
# STEP 5
# ============================================================

echo
echo "[5/8] CANableの再生成を待ちます..."

if ! CAN_IF="$(wait_for_gs_usb_can)"; then
  echo
  echo "エラー: CANableが再生成されませんでした。" >&2
  echo
  echo "USBの再接続が必要な可能性があります。" >&2
  echo
  echo "次の手順を実行してください:" >&2
  echo
  echo "  1. CANableをUSBから抜く" >&2
  echo "  2. 2〜3秒待つ" >&2
  echo "  3. CANableをUSBに接続する" >&2
  echo "  4. このスクリプトを再実行する" >&2
  echo
  exit 1
fi

echo "CANableを再検出しました: ${CAN_IF}"

show_can_interfaces

# ============================================================
# STEP 6
# ============================================================

echo
echo "[6/8] ${CAN_IF} を設定します..."

ip link set "${CAN_IF}" down 2>/dev/null || true

ip link set "${CAN_IF}" type can bitrate "${BITRATE}"

ip link set "${CAN_IF}" txqueuelen "${TX_QUEUE_LEN}"

ip link set "${CAN_IF}" up

DETAIL="$(
  ip -details -statistics link show "${CAN_IF}"
)"

printf '%s\n' "${DETAIL}"

if ! grep -q "bitrate ${BITRATE}" <<<"${DETAIL}"; then
  echo
  echo "エラー: bitrate ${BITRATE} の設定に失敗しました。" >&2
  exit 1
fi

if ! grep -q "can state ERROR-ACTIVE" <<<"${DETAIL}"; then
  echo
  echo "エラー: ${CAN_IF} がERROR-ACTIVEではありません。" >&2
  exit 1
fi

echo
echo "${CAN_IF} の設定が完了しました。"

# ============================================================
# STEP 7
# ============================================================

echo
echo "[7/8] 車両を起動します。"
echo
echo "SCOUT MINIの車両電源をONにしてください。"

wait_for_enter "車両電源をONにしたら Enter を押してください..."

echo
echo "CANフレームを待っています..."
echo "timeout: ${CAN_RX_WAIT_SECONDS} 秒"
echo

CAN_FRAME="$(
  timeout "${CAN_RX_WAIT_SECONDS}" \
    candump -n 1 "${CAN_IF}" 2>/dev/null || true
)"

if [[ -z "${CAN_FRAME}" ]]; then
  echo
  echo "========================================"
  echo "CAN受信失敗"
  echo "========================================"
  echo
  echo "${CAN_RX_WAIT_SECONDS}秒以内にCANフレームを受信できませんでした。"
  echo
  echo "現在の状態:"
  ip -details -statistics link show "${CAN_IF}"
  echo
  echo "今回と同じ症状の場合、USBの再接続で"
  echo "復旧する可能性があります。"
  echo
  echo "復旧手順:"
  echo
  echo "  1. 車両電源 OFF"
  echo "  2. CANableをUSBから抜く"
  echo "  3. 2〜3秒待つ"
  echo "  4. CANableをUSBに接続"
  echo "  5. このスクリプトを再実行"
  echo
  exit 1
fi

echo
echo "CANフレームを受信しました:"
echo
echo "  ${CAN_FRAME}"

# ============================================================
# STEP 8
# ============================================================

echo
echo "[8/8] CAN通信確認完了"

echo
echo "========================================"
echo "SCOUT MINI CAN READY"
echo "========================================"
echo
echo "CAN interface:"
echo "  ${CAN_IF}"
echo
echo "bitrate:"
echo "  ${BITRATE}"
echo
echo "CAN communication:"
echo "  OK"
echo
echo "継続して確認:"
echo "  candump ${CAN_IF}"
echo
echo "ROS 2起動:"
echo "  ros2 launch scout_base scout_mini_base.launch.py port_name:=${CAN_IF}"
echo
