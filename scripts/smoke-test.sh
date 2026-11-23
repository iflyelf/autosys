#!/usr/bin/env bash
# autosys 镜像冒烟测试: SQLite 初始化、登录、中文界面、ansible / IaC 工具可用
# 用法: scripts/smoke-test.sh <镜像> [宿主机端口]
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image> [port]}"
PORT="${2:-13000}"
NAME=autosys-smoke
PASS=Smoke-Test-123

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$NAME" -p "${PORT}:3000" \
  -e SEMAPHORE_DB_DIALECT=sqlite \
  -e SEMAPHORE_ADMIN=admin \
  -e SEMAPHORE_ADMIN_PASSWORD="$PASS" \
  -e SEMAPHORE_ADMIN_NAME=Admin \
  -e SEMAPHORE_ADMIN_EMAIL=admin@localhost \
  "$IMAGE" >/dev/null

READY=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/ping" >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done
if [ "$READY" != 1 ]; then
  echo "ERROR: 服务未在 60 秒内就绪"
  docker logs "$NAME"
  exit 1
fi
echo "✅ /api/ping 正常"

# 管理员登录
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d "{\"auth\":\"admin\",\"password\":\"${PASS}\"}" "http://127.0.0.1:${PORT}/api/auth/login")
[ "$CODE" = 204 ] || { echo "ERROR: 登录失败 HTTP $CODE"; docker logs "$NAME"; exit 1; }
echo "✅ 管理员登录正常"

# 前端标题为中文, 只打包了中文国旗
curl -fsS "http://127.0.0.1:${PORT}/" | grep -q '<title>自动化平台</title>'
curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/flags/zh_cn.svg"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/flags/en.svg")
[ "$CODE" != 200 ] || { echo "ERROR: 仍包含其他语言资源"; exit 1; }
echo "✅ 中文界面正常"

# 容器内工具链
docker exec "$NAME" sh -c '
  set -e
  autosys version
  ansible --version | head -1
  ansible-playbook --version | head -1
  tofu version | head -1
  terraform version | head -1
  terragrunt --version
  test -f /etc/autosys/config.json
  test -f /var/lib/autosys/database.sqlite
  date +%Z
'
echo "✅ 冒烟测试通过"
