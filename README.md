# Smart-Home Stack (HomeAssistant + Matter-server + OTBR Patch)

## 설치
$ git clone https://<repo>/matterhub-platform.git
$ cd matterhub-platform
$ ./scripts/install.sh

## 구성 요소
- HomeAssistant : ghcr.io/home-assistant/home-assistant:stable
- Matter-server : ghcr.io/home-assistant-libs/python-matter-server:stable
- OTBR          : OpenThread Border Router (patched for IPv6 MRT6)

## 기본 포트
- HomeAssistant UI : 8123 (host network)
