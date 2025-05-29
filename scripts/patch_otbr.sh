#!/bin/bash

# 대상 파일 경로 (필요시 절대경로로 수정)
TARGET_FILE="/home/matterhub/Desktop/matterhub-platform/ot-br-posix/third_party/openthread/repo/src/posix/platform/multicast_routing.cpp"
PATCH_START_LINE=216

echo "📌 대상 파일: $TARGET_FILE"

# 1. 백업
if [ ! -f "${TARGET_FILE}.bak" ]; then
    cp "$TARGET_FILE" "${TARGET_FILE}.bak"
    echo "🔁 백업 생성: ${TARGET_FILE}.bak"
fi

# 2. 216번째 줄에 함수 선언이 있는지 검증
EXPECTED_SIGNATURE="void MulticastRoutingManager::InitMulticastRouterSock(void)"
ACTUAL_SIGNATURE=$(sed -n "${PATCH_START_LINE}p" "$TARGET_FILE")

if [[ "$ACTUAL_SIGNATURE" != "$EXPECTED_SIGNATURE" ]]; then
    echo "❌ 216번째 줄에서 예상한 함수 시그니처를 찾지 못했습니다."
    echo "   예상: $EXPECTED_SIGNATURE"
    echo "   실제: $ACTUAL_SIGNATURE"
    echo "   👉 파일 변경 또는 줄 수 오차가 있는지 확인하세요."
    exit 1
fi

# 3. 기존 함수 블록 제거 후 새 함수 삽입
echo "🛠️  InitMulticastRouterSock() 함수 패치 중..."

head -n $((PATCH_START_LINE - 1)) "$TARGET_FILE" > "${TARGET_FILE}.patched"

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
            // Can't use otbrLogWarning here — fallback to stderr
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

    // Filter all ICMPv6 messages
    ICMP6_FILTER_SETBLOCKALL(&filter);
    VerifyOrDie(0 == setsockopt(mMulticastRouterSock, IPPROTO_ICMPV6, ICMP6_FILTER, (void *)&filter, sizeof(filter)),
                OT_EXIT_ERROR_ERRNO);

    memset(&mif6ctl, 0, sizeof(mif6ctl));
    mif6ctl.mif6c_flags     = 0;
    mif6ctl.vifc_threshold  = 1;
    mif6ctl.vifc_rate_limit = 0;

    // Add Thread network interface to MIF
    mif6ctl.mif6c_mifi = kMifIndexThread;
    mif6ctl.mif6c_pifi = if_nametoindex(gNetifName);
    VerifyOrDie(mif6ctl.mif6c_pifi > 0, OT_EXIT_ERROR_ERRNO);
    VerifyOrDie(0 == setsockopt(mMulticastRouterSock, IPPROTO_IPV6, MRT6_ADD_MIF, &mif6ctl, sizeof(mif6ctl)),
                OT_EXIT_ERROR_ERRNO);

    // Add Backbone network interface to MIF
    mif6ctl.mif6c_mifi = kMifIndexBackbone;
    mif6ctl.mif6c_pifi = otSysGetInfraNetifIndex();
    VerifyOrDie(mif6ctl.mif6c_pifi > 0, OT_EXIT_ERROR_ERRNO);
    VerifyOrDie(0 == setsockopt(mMulticastRouterSock, IPPROTO_IPV6, MRT6_ADD_MIF, &mif6ctl, sizeof(mif6ctl)),
                OT_EXIT_ERROR_ERRNO);
}
EOF

# 함수 끝 이후부터 이어붙이기
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

# 덮어쓰기
mv "${TARGET_FILE}.patched" "$TARGET_FILE"

echo "✅ 패치 완료: $TARGET_FILE"
