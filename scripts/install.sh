#!/usr/bin/env bash
set -euo pipefail

echo "🛠  Docker & docker-compose 확인"
command -v docker >/dev/null        || { echo "❌ docker 미설치"; exit 1; }
command -v docker compose >/dev/null || { echo "❌ docker compose 미설치"; exit 1; }

# ──────────────────────────────────────────────
# 1) OTBR 소스 클론 & 부트스트랩
OTBR_DIR=/home/hyodol/Desktop/matterhub-platform/ot-br-posix
if [ ! -d "$OTBR_DIR" ]; then
  echo "▶ OTBR 소스 다운로드"
  mkdir -p "$(dirname "$OTBR_DIR")"
  git clone https://github.com/openthread/ot-br-posix.git "$OTBR_DIR"
  (cd "$OTBR_DIR" && sudo ./script/bootstrap)
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
echo "▶ sudo docker compose up -d"
cd "$(dirname "$0")/.."
sudo docker compose up -d   # 이미지 자동 pull

# ──────────────────────────────────────────────
# 5) OTBR 서비스 등록 & mDNS 전환
echo "▶ OTBR 서비스 enable/restart 및 mDNS responder 전환"
sudo systemctl enable  systemd-resolved
sudo systemctl restart systemd-resolved

# systemd 서비스 매니저 재실행 (단, running 서비스는 유지)
sudo systemctl daemon-reexec

sudo systemctl enable otbr-agent
sudo systemctl restart otbr-agent

sudo systemctl disable avahi-daemon.socket || true
sudo systemctl disable avahi-daemon        || true
sudo systemctl stop avahi-daemon.socket
sudo systemctl stop avahi-daemon

# ──────────────────────────────────────────────
# 7) 로그 회전 설정
echo "▶ 로그 자동 회전 설정 중..."

# logrotate 설치 및 설정
sudo apt update -y
sudo apt install -y logrotate

# /var/log 권한 정리
sudo chmod 755 /var/log
sudo chown root:root /var/log

# rsyslog logrotate 설정에 su 옵션 추가 (권한 문제 예방)
CONF_PATH="/etc/logrotate.d/rsyslog"
if ! grep -q "su syslog adm" "$CONF_PATH"; then
  echo "  ⮑ 'su syslog adm' 추가"
  sudo sed -i '/\/var\/log\/syslog/ a\    su syslog adm' "$CONF_PATH"
else
  echo "  ⮑ 'su syslog adm' 항목 이미 존재"
fi

# logrotate 강제 실행 및 rsyslog 재시작
sudo logrotate -f "$CONF_PATH"
sudo systemctl restart rsyslog

echo "✅ 로그 자동 회전 설정 완료"
echo "✅ 설치 완료!"
echo "🌐 Home Assistant 접속:     http://<Jetson_IP>:8123"
