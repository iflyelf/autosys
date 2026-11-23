# autosys

autosys（自动化平台）是 [Semaphore UI](https://github.com/semaphoreui/semaphore) 的中文定制版 Docker 镜像，
提供 Ansible / Terraform / OpenTofu / Terragrunt / Shell 任务的 Web 管理界面。

- 上游项目：<https://github.com/semaphoreui/semaphore>
- 本仓库：<https://github.com/iflyelf/autosys>
- 镜像地址：
  - Docker Hub：`iflyelf/autosys`
  - 华为云 SWR（国内推荐）：`swr.cn-east-3.myhuaweicloud.com/iflyelf/autosys`
- 镜像 tag：`latest` 与上游版本号（如 `2.20.23`）
- 支持架构：`linux/amd64`、`linux/arm64`

## 与上游的差异

| 项目 | 上游 Semaphore | autosys |
|------|---------------|---------|
| 界面语言 | 17 种语言 | 只保留简体中文。上游 zh_cn 缺失的 600 多条词条已补译，上游新增但尚未翻译的词条回退显示英文 |
| 品牌 | Semaphore UI | 自动化平台 |
| 命令名 | `semaphore` | `autosys`（如 `autosys user add`、`autosys runner start`） |
| 默认路径 | `/etc/semaphore`、`/var/lib/semaphore`、`/tmp/semaphore` | `/etc/autosys`、`/var/lib/autosys`、`/tmp/autosys` |
| 默认时区 | `UTC` | `Asia/Shanghai` |
| 运行用户 | `semaphore`（uid 1001） | `root` |
| 基础镜像 | Alpine | `iflyelf/ubuntu:lite`（Ubuntu） |

配置用的环境变量名与上游一致（`SEMAPHORE_*`），上游文档中的配置项可以直接使用。

### 定制方式

旧版直接用整份文件覆盖上游源码，上游每次升级都要手工合并。现在改为在构建时打补丁：

1. 拉取上游指定版本源码；
2. [`scripts/apply-patches.js`](./scripts/apply-patches.js) 删除其他语言，并修改品牌、命令名、默认路径和时区。
   每处替换都必须命中，上游代码有变动时构建直接失败，不会漏改；
3. [`scripts/merge-i18n.js`](./scripts/merge-i18n.js) 按 `en.js` 的 key 合并上游 `zh_cn.js`
   和 [`i18n/zh_cn.json`](./i18n/zh_cn.json) 中的补译，生成最终的 `zh_cn.js`。

上游新增词条后，构建日志会打印 `WARN: N 条上游新增词条暂无中文`。把这些 key 的中文写进 `i18n/zh_cn.json` 即可。

## 特性

- **分阶段构建**
  - 构建阶段：`iflyelf/ubuntu:latest`，已预装 Go、Node、Python 和完整工具链
  - 运行阶段：`iflyelf/ubuntu:lite`，只拷贝编译产物，再补齐运行依赖
  - 前端与架构无关，Go 用 `CGO_ENABLED=0` 交叉编译，多架构构建时不用 QEMU 跑编译器
- 运行阶段内置：
  - Ansible（独立 venv：`/opt/autosys/apps/ansible/venv`），附带 `boto3`、`pywinrm`、`paramiko`、`jmespath`、`netaddr` 等常用库
  - OpenTofu、Terraform、Terragrunt
  - `openssh-client`、`sshpass`、`rsync`、`git`、MySQL 和 PostgreSQL 客户端
- 自定义 [`ansible.cfg`](./conf/ansible/ansible.cfg)：YAML 输出、SSH 连接复用、pipelining
- `tini` 作为 PID 1，回收 ansible 产生的僵尸进程
- 内置 `HEALTHCHECK`，探测 `/api/ping`
- 自动跟随上游最新正式版，每天定时检查

## 快速开始

### Docker Compose（推荐）

```bash
mkdir -p autosys && cd autosys
curl -fsSLO https://raw.githubusercontent.com/iflyelf/autosys/main/docker-compose.yml
# 修改 SEMAPHORE_ADMIN_PASSWORD 等配置
docker compose up -d
docker logs -f autosys
```

浏览器打开 `http://<宿主机IP>:3000`，用 `SEMAPHORE_ADMIN` / `SEMAPHORE_ADMIN_PASSWORD` 登录。

### docker run

```bash
docker run -d --name autosys --restart always \
  -p 3000:3000 \
  -e SEMAPHORE_DB_DIALECT=sqlite \
  -e SEMAPHORE_ADMIN=admin \
  -e SEMAPHORE_ADMIN_PASSWORD=change-me \
  -e SEMAPHORE_ADMIN_NAME=管理员 \
  -e SEMAPHORE_ADMIN_EMAIL=admin@localhost \
  -v "$PWD/config:/etc/autosys" \
  -v "$PWD/data:/var/lib/autosys" \
  swr.cn-east-3.myhuaweicloud.com/iflyelf/autosys:latest
```

使用 MySQL 或 PostgreSQL 时，把 `SEMAPHORE_DB_DIALECT` 设为 `mysql` / `postgres`，
并设置 `SEMAPHORE_DB_HOST`、`SEMAPHORE_DB_USER`、`SEMAPHORE_DB_PASS`、`SEMAPHORE_DB`。
启动脚本会先用 `nc -z` 等待数据库端口可用。

## 端口

| 端口 | 说明 |
|------|------|
| `3000` | Web 界面与 API |

## 数据卷

| 路径 | 说明 |
|------|------|
| `/etc/autosys` | `config.json`（首次启动自动生成）、`requirements.txt` |
| `/var/lib/autosys` | SQLite 数据库 `database.sqlite` |

## 环境变量

常用变量如下，完整列表见 [上游配置文档](https://docs.semaphoreui.com/administration-guide/configuration/)。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SEMAPHORE_DB_DIALECT` | `mysql` | `sqlite` / `mysql` / `postgres` |
| `SEMAPHORE_DB_HOST` | sqlite 时为 `/var/lib/autosys/database.sqlite` | 数据库地址，可带端口 |
| `SEMAPHORE_DB_USER` / `SEMAPHORE_DB_PASS` | - | 数据库账号（支持 `_FILE` 后缀读取文件） |
| `SEMAPHORE_DB` | `autosys` | 数据库名 |
| `SEMAPHORE_ADMIN` / `SEMAPHORE_ADMIN_PASSWORD` | - | 首次启动创建的管理员 |
| `SEMAPHORE_ADMIN_NAME` / `SEMAPHORE_ADMIN_EMAIL` | - | 管理员名称与邮箱 |
| `SEMAPHORE_ACCESS_KEY_ENCRYPTION` | - | 密钥存储加密 key（`head -c32 /dev/urandom \| base64`） |
| `SEMAPHORE_SCHEDULE_TIMEZONE` | `Asia/Shanghai` | 计划任务时区 |
| `SEMAPHORE_CONFIG_PATH` | `/etc/autosys` | 配置目录 |
| `SEMAPHORE_TMP_PATH` | `/tmp/autosys` | 项目临时目录 |
| `SEMAPHORE_IMPORT_PROJECT_FILE` | - | 首次启动时导入的项目备份文件 |
| `TZ` | `Asia/Shanghai` | 容器时区 |

额外的 Python 依赖写进 `/etc/autosys/requirements.txt`，容器启动时会安装到 ansible venv。

## 常用命令

```bash
# 查看用户 / 修改密码 / 新增管理员
docker exec -it autosys autosys user list --config /etc/autosys/config.json
docker exec -it autosys autosys user change-by-login --login admin --password 新密码 --config /etc/autosys/config.json
docker exec -it autosys autosys user add --admin --login ops --name 运维 --email ops@example.com --password 密码 --config /etc/autosys/config.json

# 版本信息
docker exec autosys autosys version
docker exec autosys ansible --version
```

## 本地构建

```bash
# 默认版本见 Dockerfile 中的 SEMAPHORE_REF
docker buildx build -t autosys:local .

# 构建指定上游版本（branch / tag / commit 均可）
docker buildx build -t autosys:local \
  --build-arg SEMAPHORE_REF=v2.20.23 \
  --build-arg VERSION=v2.20.23 .

# 冒烟测试：SQLite 初始化、登录、中文界面、工具链
bash scripts/smoke-test.sh autosys:local
```

默认使用国内镜像（`goproxy.cn`、`registry.npmmirror.com`）。海外构建可以通过 `GOPROXY`、
`NPM_REGISTRY`、`PIP_INDEX_URL` 这几个 build-arg 改回官方源。

## 自动构建（GitHub Actions）

| 工作流 | 触发 | 作用 |
|--------|------|------|
| [`docker-publish.yml`](./.github/workflows/docker-publish.yml) | push（Dockerfile / scripts / i18n / conf）、手动、每天 05:00、Star | 通过 GitHub API 解析上游最新正式 release，构建 amd64 和 arm64 镜像，推送到 Docker Hub 与华为云 SWR，再跑冒烟测试 |
| [`update-version.yml`](./.github/workflows/update-version.yml) | 每天 04:00、手动 | 检查 semaphore、OpenTofu、Terraform、Terragrunt、Ansible 的最新稳定版，有更新就改写 Dockerfile 的 `ARG`、提交，并触发构建 |

两个工作流都配置了 `concurrency`，同一分支只保留最新一次运行。手动构建时可以在 `version` 输入框指定上游 Tag。

### 所需 Secrets

| Secret | 说明 |
|--------|------|
| `DOCKER_USERNAME` / `DOCKER_PASSWORD` | Docker Hub 账号 |
| `SWR_USERNAME` / `SWR_PASSWORD` | 华为云 SWR 登录凭据（`cn-east-3@<AK>` / 登录密钥） |
| `SWR_AK` / `SWR_SK` | 可选，华为云 AK/SK，用于把 SWR 仓库设为公开 |

## 许可

上游 Semaphore UI 以 MIT 许可发布，本仓库同样使用 [MIT](./LICENSE)。
