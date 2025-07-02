#!/bin/bash
set -euo pipefail

TARGET_FILE="/home/hyodol/Desktop/matterhub-platform/ot-br-posix/third_party/openthread/repo/src/posix/platform/multicast_routing.cpp"
BACKUP_FILE="${TARGET_FILE}.bak"
EXPECTED_SIGNATURE="void MulticastRoutingManager::InitMulticastRouterSock(void)"

echo "📌 대상 파일: $TARGET_FILE"

# 1. 백업
if [ ! -f "$BACKUP_FILE" ]; then
    cp "$TARGET_FILE" "$BACKUP_FILE"
    echo "🔁 백업 생성: $BACKUP_FILE"
fi

# 2. 함수 시작 줄 찾기
PATCH_START_LINE=$(grep -n "^$EXPECTED_SIGNATURE" "$TARGET_FILE" | cut -d: -f1 || true)

if [[ -z "$PATCH_START_LINE" ]]; then
    echo "❌ 함수 시그니처를 파일에서 찾을 수 없습니다."
    echo "   예상 시그니처: $EXPECTED_SIGNATURE"
    exit 1
fi

echo "🔍 함수 시작 위치: $PATCH_START_LINE줄"

# 3. 기존 함수 제거 (중괄호 수로 블록 판단)
echo "🛠️  InitMulticastRouterSock() 함수 패치 중..."

# 상단부 보존
head -n $((PATCH_START_LINE - 1)) "$TARGET_FILE" > "${TARGET_FILE}.patched"

# 새로운 함수 정의 추가
cat >> "${TARGET_FILE}.patched" <<'EOF'
void MulticastRoutingManager::InitMulticastRouterSock(void)
{
    int                 one = 1;
    struct icmp6_filter filter;
    struct mif6ctl      mif6ctl;

    // Create a Multicast Routing socket
    mMulticastRouterSock = SocketWithCloseExec(AF_INET6, SOCK_RAW, IPPROTO_ICMPV6, kSocketBlock);
    VerifyOrDie(mMulticastRouterSock != -1, OT_EXIT_ERROR_ERRNO);

    // Enable Multicast Forwarding in Kernel (MRT6_INIT)
    if (setsockopt(mMulticastRouterSock, IPPROTO_IPV6, MRT6_INIT, &one, sizeof(one)) != 0)
    {
        if (errno == ENOPROTOOPT)
        {
            fprintf(stderr, "MulticastRoutingManager: MRT6_INIT not supported by kernel, skipping multicast routing setup.\n");
            close(mMulticastRouterSock);
            mMulticastRouterSock = -1;
            return;
        }
        else
        {
            VerifyOrDie(false, OT_EXIT_ERROR_ERRNO);
        }
    }

    ICMP6_FILTER_SETBLOCKALL(&filter);
    VerifyOrDie(0 == setsockopt(mMulticastRouterSock, IPPROTO_ICMPV6, ICMP6_FILTER, (void *)&filter, sizeof(filter)),
                OT_EXIT_ERROR_ERRNO);

    memset(&mif6ctl, 0, sizeof(mif6ctl));
    mif6ctl.mif6c_flags     = 0;
    mif6ctl.vifc_threshold  = 1;
    mif6ctl.vifc_rate_limit = 0;

    mif6ctl.mif6c_mifi = kMifIndexThread;
    mif6ctl.mif6c_pifi = if_nametoindex(gNetifName);
    VerifyOrDie(mif6ctl.mif6c_pifi > 0, OT_EXIT_ERROR_ERRNO);
    VerifyOrDie(0 == setsockopt(mMulticastRouterSock, IPPROTO_IPV6, MRT6_ADD_MIF, &mif6ctl, sizeof(mif6ctl)),
                OT_EXIT_ERROR_ERRNO);

    mif6ctl.mif6c_mifi = kMifIndexBackbone;
    mif6ctl.mif6c_pifi = otSysGetInfraNetifIndex();
    VerifyOrDie(mif6ctl.mif6c_pifi > 0, OT_EXIT_ERROR_ERRNO);
    VerifyOrDie(0 == setsockopt(mMulticastRouterSock, IPPROTO_IPV6, MRT6_ADD_MIF, &mif6ctl, sizeof(mif6ctl)),
                OT_EXIT_ERROR_ERRNO);
}
EOF

# 하단부 이어붙이기 (기존 함수 블록 건너뛰기)
tail -n +$((PATCH_START_LINE + 1)) "$TARGET_FILE" | awk '
    BEGIN { skip = 1; braces = 0 }
    {
        if (skip) {
            braces += gsub("{", "{")
            braces -= gsub("}", "}")
            if (braces <= 0) {
                skip = 0
                next
            } else {
                next
            }
        }
        print
    }
' >> "${TARGET_FILE}.patched"

mv "${TARGET_FILE}.patched" "$TARGET_FILE"
echo "✅ 패치 완료: $TARGET_FILE"
