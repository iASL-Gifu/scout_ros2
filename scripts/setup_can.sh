#!/usr/bin/env bash
set -Eeuo pipefail

# SCOUT MINI / CANable 初回セットアップ
# 実行: sudo ./setup_can_once.sh

if [[ ${EUID} -ne 0 ]]; then
  echo "エラー: sudo で実行してください。" >&2
  echo "例: sudo ./setup_can_once.sh" >&2
  exit 1
fi

echo "[1/3] 必要なパッケージをインストールします..."
apt-get update
apt-get install -y can-utils

echo "[2/3] gs_usb を起動時に自動読み込みするよう設定します..."
printf '%s\n' "gs_usb" > /etc/modules-load.d/gs_usb.conf
modprobe gs_usb

echo "[3/3] 設定を確認します..."
if lsmod | grep -q '^gs_usb'; then
  echo "gs_usb: loaded"
else
  echo "エラー: gs_usb を読み込めませんでした。" >&2
  exit 1
fi

echo
echo "初回セットアップが完了しました。"
echo "USB-CANを接続した後、次を実行してください:"
echo "  sudo ./setup_can.sh"
