# Volcengine 自部署指南

服务器: `root@115.190.130.45:22` (Debian 12, 8GB RAM, 40GB SSD)

## 架构

```
Internet → Caddy (:80)
  ├─ /health → multica-backend (:8080)   ← CLI 健康检查
  ├─ /ws     → multica-backend (:8080)   ← WebSocket
  └─ /*      → multica-frontend (:3000) → Next.js rewrites → multica-backend (:8080)
                                                              → multica-postgres (:5432)
```

所有服务跑在 Docker 里，127.0.0.1 绑定。

---

## 前置条件

服务器已安装（一次性）:
- Docker 20.10 + docker-compose v2.29.1 (plugin 模式)
- Docker 镜像加速: `/etc/docker/daemon.json` → `docker.m.daocloud.io`
- Node.js 22、pnpm、PM2 (未使用，但可用)

---

## 初始化部署

```bash
# 1. rsync 源码到服务器 (排除构建产物)
rsync -av --progress \
  --exclude='node_modules' --exclude='.next' --exclude='.turbo' \
  --exclude='server/bin' --exclude='.pnpm-store' \
  --exclude='*.log' --exclude='.DS_Store' \
  -e "ssh" \
  /Users/fenix/repos/multica/ root@115.190.130.45:/root/repos/multica/

# 2. 服务器上构建 + 启动 (首次 10-20 分钟)
ssh root@115.190.130.45 \
  'cd /root/repos/multica && make selfhost-build'

# 3. 配置 Caddy 反代
# /health 和 /ws 直接转发后端（CLI 健康检查和 WebSocket），其余走前端
ssh root@115.190.130.45 'cat > /etc/caddy/Caddyfile <<EOF
:80 {
    handle /health {
        reverse_proxy localhost:8080
    }
    handle /ws {
        reverse_proxy localhost:8080
    }
    reverse_proxy localhost:3000
}
EOF
caddy reload --config /etc/caddy/Caddyfile'
```

访问: `http://115.190.130.45`

---

## 日常迭代部署

改完代码后: rsync → rebuild (Docker 缓存让改动层秒级完成)

```bash
rsync -av --progress \
  --exclude='node_modules' --exclude='.next' --exclude='.turbo' \
  --exclude='server/bin' --exclude='.pnpm-store' \
  --exclude='*.log' --exclude='.DS_Store' \
  -e "ssh" \
  /Users/fenix/repos/multica/ root@115.190.130.45:/root/repos/multica/ \
  && ssh root@115.190.130.45 \
    'cd /root/repos/multica && docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --build'
```

---

## 环境配置

服务器 `.env` 自定义项（写在 `.env.example` 中进 git 管理，首次部署后手动同步到服务器 `.env`）:

```env
# 免邮件注册
APP_ENV=development
MULTICA_DEV_VERIFICATION_CODE=888888           # 固定验证码

# 注册限制
ALLOWED_EMAIL_DOMAINS=dmyh.tech               # 只允许公司邮箱

# 飞书/Lark 集成
MULTICA_LARK_SECRET_KEY=<set-fresh-secret-on-server>
MULTICA_PUBLIC_URL=http://115.190.130.45       # 飞书身份绑定 + 守护进程 server-url

# 守护进程连接 (决定「添加电脑」弹窗的命令文案)
MULTICA_APP_URL=http://115.190.130.45          # 守护进程 app-url
FRONTEND_ORIGIN=http://115.190.130.45
```

### 飞书集成步骤

1. `.env` 配好上面两个变量，重建 backend 容器
2. 进 Web UI → **Settings → Integrations** 确认 "Lark 集成已启用"
3. 进 **Agents → 选 agent → Integrations → Bind to Feishu**，扫码授权
4. 其他成员首次给机器人发消息时会收到绑定身份卡片，点击完成绑定

飞书消息通过 WebSocket 长连接收发，无需公网回调 URL。

---

## 关键修改

以下文件已在服务端修改（镜像加速，首次构建必须）:

**Dockerfile** — 加了中国 Go 代理:
```dockerfile
FROM golang:1.26-alpine AS builder
RUN apk add --no-cache git
ENV GOPROXY=https://goproxy.cn,direct   # ← 新增
```

**Dockerfile.web** — 加了 npm 镜像:
```dockerfile
RUN pnpm config set registry https://registry.npmmirror.com  # ← 新增
RUN pnpm install --frozen-lockfile
```

**Docker Compose** — 安装了 compose plugin:
```bash
# compose 二进制放这里解决了 `docker compose` 命令
/usr/lib/docker/cli-plugins/docker-compose
```

---

## 常用命令

```bash
# 查看容器
ssh root@115.190.130.45 'docker ps'

# 查看后端日志
ssh root@115.190.130.45 \
  'docker compose -f /root/repos/multica/docker-compose.selfhost.yml logs backend -f'

# 重启某服务
ssh root@115.190.130.45 \
  'docker compose -f /root/repos/multica/docker-compose.selfhost.yml restart backend'

# 仅重建容器（不改代码，只改 env 后生效）
ssh root@115.190.130.45 \
  'cd /root/repos/multica && docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --no-build backend'

# 停止
ssh root@115.190.130.45 \
  'cd /root/repos/multica && make selfhost-stop'

# 查看 .env 配置 (JWT_SECRET 等)
ssh root@115.190.130.45 'cat /root/repos/multica/.env'
```
