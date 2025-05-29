#!/usr/bin/env bash
set -euo pipefail

echo "🛠  Docker & docker-compose 확인"
command -v docker >/dev/null        || { echo "❌ docker 미설치"; exit 1; }
command -v docker compose >/dev/null || { echo "❌ docker compose 미설치"; exit 1; }

# ──────────────────────────────────────────────
# 1) OTBR 소스 클론 & 부트스트랩
OTBR_DIR=/home/matterhub/Desktop/matterhub-platform/ot-br-posix
if [ ! -d "$OTBR_DIR" ]; then
  echo "▶ OTBR 소스 다운로드"
  mkdir -p "$(dirname "$OTBR_DIR")"
  git clone https://github.com/openthread/ot-br-posix.git "$OTBR_DIR"
  (cd "$OTBR_DIR" && ./script/bootstrap)
else
  echo "▶ OTBR 소스 존재 → 건너뜀"
fi

# ──────────────────────────────────────────────
# 2) 패치 적용
echo "▶ OTBR 패치 실행"
chmod +x "$(dirname "$0")/patch_otbr.sh"
bash   "$(dirname "$0")/patch_otbr.sh"

# ──────────────────────────────────────────────
# 3) OTBR setup
echo "▶ OTBR setup (FIREWALL=0, wlan0)"
(cd "$OTBR_DIR" && FIREWALL=0 INFRA_IF_NAME=wlan0 ./script/setup)

# ──────────────────────────────────────────────
# 4) HomeAssistant + Matter-server 기동
echo "▶ docker compose up -d"
cd "$(dirname "$0")/.."
docker compose up -d   # 이미지 자동 pull

# ──────────────────────────────────────────────
# 5) OTBR 서비스 등록 & mDNS 전환
echo "▶ OTBR 서비스 enable/restart 및 mDNS responder 전환"
sudo systemctl enable  systemd-resolved
sudo systemctl restart systemd-resolved

# systemd 서비스 매니저 재실행 (단, running 서비스는 유지)
sudo systemctl daemon-reexec

sudo systemctl enable otbr-agent
sudo systemctl restart otbr-agent

echo "✅ 설치 완료!   Home Assistant → http://<HOST>:8123"

sudo systemctl disable avahi-daemon.socket || true
sudo systemctl disable avahi-daemon        || true
sudo systemctl stop avahi-daemon.socket
sudo systemctl stop avahi-daemon
