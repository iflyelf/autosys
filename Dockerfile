# syntax=docker/dockerfile:1
#=================================================
# autosys 自动化平台镜像
# 上游: https://github.com/semaphoreui/semaphore
# 镜像: https://github.com/iflyelf/autosys
# Lisence: MIT
#=================================================
#
# 分阶段构建:
#   builder = iflyelf/ubuntu:latest  预装 Go / Node / Python / 完整工具链,
#                                     无需重复安装庞大的依赖列表, 构建更快更稳
#   runtime = iflyelf/ubuntu:lite    仅拷贝编译产物, 再补齐 ansible 运行所需依赖
#
# 构建时拉取上游指定版本源码, 通过 scripts/apply-patches.js 应用 autosys 定制
# (仅保留中文界面、品牌与命令改名、默认时区与路径), 不再整文件覆盖上游代码,
# 因此可以直接跟随上游最新版本。

#############################
#      构建阶段 builder      #
#############################
# 在本机架构构建: 前端产物与架构无关, Go 通过 CGO_ENABLED=0 交叉编译,
# 避免多架构构建时让 npm / Go 编译器跑在 QEMU 模拟环境里。
FROM --platform=$BUILDPLATFORM iflyelf/ubuntu:latest AS builder

LABEL org.opencontainers.image.authors="iflyelf" \
      org.opencontainers.image.vendor="iflyelf" \
      org.opencontainers.image.title="autosys" \
      org.opencontainers.image.description="autosys 自动化平台 (builder)"

ARG TZ=Asia/Shanghai
ENV TZ=${TZ}

# 上游源码与版本: GitHub Actions 解析上游最新 release 后通过 --build-arg 注入
# SEMAPHORE_REF 支持 branch / tag / commit
ARG SEMAPHORE_REPO=https://github.com/semaphoreui/semaphore.git
ARG SEMAPHORE_REF=v2.20.23
ARG VERSION=v2.20.23

# Go 模块代理 / npm 源 (海外构建可覆盖为官方源)
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}
ARG NPM_REGISTRY=https://registry.npmmirror.com

WORKDIR /src

# 拉取指定版本源码 (fetch 指定 ref 后可兼容 branch / tag / commit)
RUN set -eux; \
    git init -q .; \
    git remote add origin "${SEMAPHORE_REPO}"; \
    git fetch --depth 1 origin "${SEMAPHORE_REF}"; \
    git checkout -q --detach FETCH_HEAD; \
    echo "semaphore source: $(git rev-parse HEAD)"

# 应用 autosys 定制补丁并生成只含中文的语言包
COPY scripts/ /autosys/scripts/
COPY i18n/ /autosys/i18n/
RUN set -eux; \
    node /autosys/scripts/apply-patches.js /src; \
    node /autosys/scripts/merge-i18n.js /src/web/src/lang /autosys/i18n/zh_cn.json

# 编译前端 (输出到 api/public, 由 go:embed 打包进二进制)
RUN --mount=type=cache,target=/root/.npm \
    set -eux; \
    cd web; \
    npm config set registry "${NPM_REGISTRY}"; \
    npm ci --no-audit --no-fund; \
    npm run build; \
    test -f ../api/public/index.html

# 交叉编译后端
ARG TARGETOS=linux
ARG TARGETARCH
RUN --mount=type=cache,target=/opt/golang/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eux; \
    IMPORT=github.com/semaphoreui/semaphore; \
    COMMIT="$(git rev-parse --short HEAD)"; \
    DATE="$(date +%s)"; \
    CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH:-$(go env GOARCH)}" \
    go build -tags netgo -trimpath \
        -ldflags "-s -w -X ${IMPORT}/util.Ver=${VERSION} -X ${IMPORT}/util.Commit=${COMMIT} -X ${IMPORT}/util.Date=${DATE}" \
        -o /out/autosys ./cli; \
    install -m 0755 deployment/docker/server/server-wrapper /out/server-wrapper; \
    ls -lh /out

# IaC 工具: OpenTofu / Terraform / Terragrunt (版本由 update-version.yml 自动更新)
ARG OPENTOFU_VERSION=1.13.9
ARG TERRAFORM_VERSION=1.17.2
ARG TERRAGRUNT_VERSION=1.2.2
RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    tmp="$(mktemp -d)"; \
    curl -fsSL --retry 3 -o "$tmp/tofu.tar.gz" \
        "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_${arch}.tar.gz"; \
    tar -xzf "$tmp/tofu.tar.gz" -C "$tmp" tofu; \
    curl -fsSL --retry 3 -o "$tmp/terraform.zip" \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"; \
    unzip -q "$tmp/terraform.zip" terraform -d "$tmp"; \
    curl -fsSL --retry 3 -o "$tmp/terragrunt" \
        "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${arch}"; \
    install -m 0755 "$tmp/tofu" "$tmp/terraform" "$tmp/terragrunt" /out/; \
    rm -rf "$tmp"


#############################
#      运行阶段 runtime      #
#############################
FROM iflyelf/ubuntu:lite

LABEL org.opencontainers.image.authors="iflyelf" \
      org.opencontainers.image.vendor="iflyelf" \
      org.opencontainers.image.title="autosys" \
      org.opencontainers.image.description="autosys 自动化平台 - 基于 Semaphore UI 的中文版 Ansible / Terraform / OpenTofu Web 平台" \
      org.opencontainers.image.source="https://github.com/iflyelf/autosys" \
      org.opencontainers.image.url="https://github.com/iflyelf/autosys"

ARG TZ=Asia/Shanghai
ENV TZ=${TZ}

# 运行阶段按需补充依赖 (lite 已自带 bash/curl/wget/git/jq/tar/zip/unzip/sshpass/tini/tzdata/locales,
# 这里显式声明, 防止 lite 后续精简导致运行期缺包):
#   python3 / python3-venv / python3-pip   ansible 运行环境 (独立 venv)
#   openssh-client / sshpass               ansible 通过 SSH 连接主机
#   rsync                                  synchronize 模块
#   netcat-openbsd                         启动脚本 nc -z 探测数据库端口
#   default-mysql-client / postgresql-client  数据库客户端 (与上游镜像一致)
#   gnupg                                  校验 / 导入签名
#   git / curl / ca-certificates / jq      拉取仓库与启动脚本解析 config.json
#   tini / tzdata / locales                PID 1 信号回收、时区与中文 locale
ARG PKG_DEPS="\
    bash \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    tar \
    zip \
    unzip \
    gnupg \
    openssh-client \
    sshpass \
    rsync \
    netcat-openbsd \
    default-mysql-client \
    postgresql-client \
    python3 \
    python3-venv \
    python3-pip \
    tini \
    tzdata \
    locales"
ENV PKG_DEPS=${PKG_DEPS}

RUN set -eux; \
    apt-get update -qq; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ${PKG_DEPS}; \
    # 逐个校验依赖是否真正安装成功, 缺失则构建失败
    for pkg in ${PKG_DEPS}; do \
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then \
            echo "ERROR: 依赖包未成功安装: $pkg" >&2; exit 1; \
        fi; \
    done; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Ansible 安装在独立 venv 中 (版本由 update-version.yml 跟随 PyPI 自动更新)
ARG ANSIBLE_VERSION=13.5.0
ENV ANSIBLE_VERSION=${ANSIBLE_VERSION}
ARG ANSIBLE_VENV_PATH=/opt/autosys/apps/ansible/venv
ARG PIP_INDEX_URL=https://pypi.org/simple
RUN set -eux; \
    python3 -m venv "${ANSIBLE_VENV_PATH}" --system-site-packages; \
    "${ANSIBLE_VENV_PATH}/bin/pip" install --no-cache-dir --no-compile --index-url "${PIP_INDEX_URL}" --upgrade pip; \
    "${ANSIBLE_VENV_PATH}/bin/pip" install --no-cache-dir --no-compile --index-url "${PIP_INDEX_URL}" \
        "ansible==${ANSIBLE_VERSION}" boto3 botocore requests pywinrm passlib paramiko jmespath netaddr; \
    find "${ANSIBLE_VENV_PATH}" -name __pycache__ -prune -exec rm -rf {} +; \
    "${ANSIBLE_VENV_PATH}/bin/ansible" --version

# SSH 默认不校验主机密钥 (与上游镜像一致)
RUN set -eux; \
    mkdir -p /etc/ssh/ssh_config.d; \
    printf 'Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n' > /etc/ssh/ssh_config.d/autosys.conf; \
    mkdir -p /etc/autosys /var/lib/autosys /tmp/autosys /etc/ansible

COPY conf/ansible/ansible.cfg /etc/ansible/ansible.cfg
COPY --from=builder /out/autosys /out/server-wrapper /usr/local/bin/
COPY --from=builder /out/tofu /out/terraform /out/terragrunt /usr/local/bin/

# 环境变量:
#   VIRTUAL_ENV / PATH   默认使用镜像内的 ansible venv (requirements.txt 也装进该 venv)
#   SEMAPHORE_*          上游配置变量名保持不变, 仅默认路径改为 autosys
ENV VIRTUAL_ENV=${ANSIBLE_VENV_PATH} \
    PATH=${ANSIBLE_VENV_PATH}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    ANSIBLE_CONFIG=/etc/ansible/ansible.cfg \
    SEMAPHORE_CONFIG_PATH=/etc/autosys \
    SEMAPHORE_DB_PATH=/var/lib/autosys \
    SEMAPHORE_TMP_PATH=/tmp/autosys \
    SEMAPHORE_SCHEDULE_TIMEZONE=Asia/Shanghai

RUN set -eux; \
    autosys version; \
    tofu version; \
    terraform version; \
    terragrunt --version

# 与旧版 autosys 一致, 默认以 root 运行 (便于挂载 docker.sock / 宿主机密钥等)
USER root
WORKDIR /root

VOLUME ["/etc/autosys", "/var/lib/autosys"]

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:3000/api/ping || exit 1

# tini 作为 PID 1 回收 ansible 僵尸进程
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/server-wrapper"]
