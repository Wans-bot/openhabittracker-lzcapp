#!/bin/bash
# OpenHabitTracker 首装初始化：把默认界面语言改成简体中文。
#
# 为什么需要：上游给新用户的界面语言默认值是 en（SettingsModel.Culture 的代码默认值），
# 中文语言包本身完整，但全新安装第一眼是英文，而且首装自动生成的欢迎笔记也会是英文。
# 这里在应用就绪后、用户第一次打开之前，用上游自己的公开接口把设置改成 zh：
#   1) POST /api/Auth/jwt-token          用部署账号换 JWT
#   2) GET  /api/DataAccess/settings     读当前用户的设置
#   3) PUT  /api/DataAccess/settings     写回同一份设置，只把 Culture 改成 zh
# 镜像里没有 curl/wget，用 bash 的 /dev/tcp 发 HTTP/1.0 请求（响应不 chunked，正文可直接取）。
# 只改语言，不动其它字段；重复执行结果相同。
set -u

BASE_HOST="${OHT_HOST:-openhabittracker}"
BASE_PORT="${OHT_PORT:-8080}"
USER_NAME="${LZC_ADMIN_USER:-admin}"
PASSWORD="${LZC_ADMIN_PASSWORD:-}"

# 发一次请求，打印完整响应（含响应头）
http() {
  local method="$1" path="$2" body="$3" token="$4"
  local req=""
  req+="${method} ${path} HTTP/1.0\r\n"
  req+="Host: ${BASE_HOST}\r\n"
  req+="Connection: close\r\n"
  if [ -n "$body" ]; then
    req+="Content-Type: application/json\r\n"
    req+="Content-Length: ${#body}\r\n"
  fi
  if [ -n "$token" ]; then
    req+="Authorization: Bearer ${token}\r\n"
  fi
  req+="\r\n${body}"
  { exec 3<>"/dev/tcp/${BASE_HOST}/${BASE_PORT}"; } 2>/dev/null || return 1
  printf "%b" "$req" >&3
  timeout 15 cat <&3
  exec 3<&- 3>&-
}

# 只取响应正文（HTTP/1.0 + Connection: close，正文在第一个空行之后）
body_of() { awk 'BEGIN{b=0} { if (b) print; else if ($0 ~ /^\r?$/) b=1 }'; }

ready=0
for _ in $(seq 1 60); do
  if http GET /login "" "" | head -1 | grep -q " 200 "; then ready=1; break; fi
  sleep 5
done
if [ "$ready" -ne 1 ]; then
  echo "[init] 应用 300 秒内未就绪，跳过语言初始化" >&2
else
  jwt=""
  for _ in $(seq 1 30); do
    resp=$(http POST /api/Auth/jwt-token "{\"userName\":\"${USER_NAME}\",\"password\":\"${PASSWORD}\"}" "" | body_of)
    jwt=$(printf '%s' "$resp" | sed -n 's/.*"JwtToken":"\([^"]\{20,\}\)".*/\1/p' | head -1)
    [ -n "$jwt" ] && break
    sleep 2
  done
  if [ -z "$jwt" ]; then
    echo "[init] 未取到 JWT，跳过语言初始化" >&2
  else
    changed=0
    for _ in $(seq 1 20); do
      settings=$(http GET /api/DataAccess/settings "" "$jwt" | body_of)
      case "$settings" in
        *'"Culture":"zh"'*|*'"culture":"zh"'*) echo "[init] 界面语言已经是 zh"; changed=1; break ;;
      esac
      if printf '%s' "$settings" | grep -q '"Culture"'; then
        updated=$(printf '%s' "$settings" | sed 's/"Culture":"[^"]*"/"Culture":"zh"/; s/"culture":"[^"]*"/"culture":"zh"/')
        code=$(http PUT /api/DataAccess/settings "$updated" "$jwt" | head -1)
        echo "[init] PUT /api/DataAccess/settings -> ${code%$'\r'}"
        changed=1
        break
      fi
      sleep 3
    done
    [ "$changed" -eq 0 ] && echo "[init] 未读到用户设置，保持默认语言" >&2
  fi
fi

# 常驻，避免容器反复退出；healthcheck 恒为 true。
while true; do sleep 3600; done
