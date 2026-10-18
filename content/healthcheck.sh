#!/bin/bash
# 容器健康探针：镜像内没有 curl/wget，用 bash 的 /dev/tcp 发一次 HTTP 请求。
# 期望登录页返回 200；其它情况按失败处理（连接失败、5xx、301/302 都算异常）。
set -u
resp="$( { exec 3<>/dev/tcp/127.0.0.1/8080; printf 'GET /login HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' >&3; timeout 5 cat <&3; } 2>/dev/null | head -1 )"
case "$resp" in
  *" 200 "*) exit 0 ;;
  *) echo "probe failed: '$resp'"; exit 1 ;;
esac
