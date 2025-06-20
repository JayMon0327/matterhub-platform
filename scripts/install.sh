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
# 6) Zeroconf Relay Agent 설치 및 실행(Matter<->OTBR 연동)
echo "▶ Zeroconf Relay Agent 설치 중..."

# python + zeroconf 설치
sudo apt-get update
sudo apt-get install -y python3 python3-pip avahi-daemon
pip3 install zeroconf

# relay_zeroconf.py 저장
sudo tee /opt/relay_zeroconf.py > /dev/null << 'EOF'
import re
import socket
import subprocess
from zeroconf import Zeroconf, ServiceInfo

SERVICE_TYPE = "_matter._udp.local."
PORT = 5540

zeroconf = Zeroconf()
registered = {}

def register_mdns_service(hostname: str, ip6: str):
    global registered
    service_name = f"{hostname}.{SERVICE_TYPE}"
    server_name = f"{hostname}.local."

    if service_name in registered:
        return

    try:
        info = ServiceInfo(
            SERVICE_TYPE,
            service_name,
            addresses=[socket.inet_pton(socket.AF_INET6, ip6)],
            port=PORT,
            properties={},
            server=server_name,
        )
        zeroconf.register_service(info)
        registered[service_name] = info
        print(f"[+] Registered mDNS service: {hostname} → {ip6}")
    except Exception as e:
        print(f"[!] Registration failed: {hostname}, reason: {e}")

def parse_logs():
    print("[*] Watching otbr-agent logs (via journalctl)...")
    cmd = ["journalctl", "-u", "otbr-agent", "-f", "-n", "0"]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)

    pattern = re.compile(r"Host:([A-Z0-9]+)\.default\.service\.arpa.*(?:address.*)?(?:\[)?([a-fA-F0-9:]{4,})?")

    for line in process.stdout:
        match = pattern.search(line)
        if match:
            hostname = match.group(1)
            ip6 = match.group(2)
            if ip6:
                register_mdns_service(hostname, ip6)

try:
    parse_logs()
except KeyboardInterrupt:
    print("\n[!] Stopping Zeroconf relay.")
    zeroconf.close()
EOF

# systemd 서비스 등록
sudo tee /etc/systemd/system/relay-zeroconf.service > /dev/null << EOF
[Unit]
Description=Relay OTBR hostname to Zeroconf mDNS
After=network.target otbr-agent.service

[Service]
ExecStart=/usr/bin/python3 /opt/relay_zeroconf.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 서비스 적용
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now relay-zeroconf.service

echo "✅ 설치 완료!"
echo "🔎 Zeroconf Relay 상태 확인: sudo systemctl status relay-zeroconf.service"
echo "🔎 로그 실시간 보기:        journalctl -u relay-zeroconf.service -f"
echo "🌐 Home Assistant 접속:     http://<Jetson_IP>:8123"
