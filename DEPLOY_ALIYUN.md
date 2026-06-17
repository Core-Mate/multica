# Aliyun Self-Hosted Deployment Guide

Server: `root@47.101.50.56:22` via `/Users/fenix/Downloads/lite-dev.pem`

## Current State

This deployment was created on 2026-06-16 as a fresh replacement for the unavailable Volcengine server.

```text
Cloud: Alibaba Cloud ECS
Region: cn-shanghai
Zone: cn-shanghai-e
Instance type: ecs.g9i.large
OS: Debian GNU/Linux 13 (trixie)
Hostname: iZuf640z2og5v1j32f6h2qZ
Project path: /root/repos/multica
```

Multica is running in Docker Compose with locally built images:

```text
multica-postgres-1   pgvector/pgvector:pg17   healthy
multica-backend-1    multica-backend:dev      127.0.0.1:8080->8080
multica-frontend-1   multica-web:dev          127.0.0.1:3001->3000
```

The frontend host port is `3001` because this server already had unrelated Node services listening on public ports `3000` and `9527`. Do not stop or reuse those ports without confirming ownership.

## External Access Blocker

Server-local checks pass:

```bash
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1/health
curl -I http://127.0.0.1:3001
```

External access to `47.101.50.56:80` currently times out when bypassing local proxies:

```bash
curl --noproxy '*' --max-time 15 http://47.101.50.56/health
nc -vz -G 8 47.101.50.56 80
```

The server firewall is not blocking it (`iptables` INPUT policy is `ACCEPT`, Caddy listens on `*:80`). Open inbound `80/tcp` in the Alibaba Cloud security group. If a domain is added later, also open `443/tcp`.

## Architecture

```text
Internet -> Caddy (:80)
  -> /health -> multica-backend (:8080)
  -> /ws     -> multica-backend (:8080)
  -> /*      -> multica-frontend (:3001 host -> 3000 container)
```

Docker-published application ports are bound to `127.0.0.1` only. Public access should go through Caddy.

## Installed Server Packages

Installed with apt from Aliyun/Debian mirrors:

```text
docker.io
docker-compose
caddy
curl
ca-certificates
```

Docker Hub pulls timed out initially, so `/etc/docker/daemon.json` was created with a registry mirror:

```json
{"registry-mirrors":["https://docker.m.daocloud.io"]}
```

## Environment

Remote env file:

```text
/root/repos/multica/.env
```

Important non-secret values:

```env
APP_ENV=production
MULTICA_DEV_VERIFICATION_CODE=
BACKEND_PORT=8080
FRONTEND_PORT=3001
FRONTEND_ORIGIN=http://47.101.50.56
MULTICA_APP_URL=http://47.101.50.56
MULTICA_PUBLIC_URL=http://47.101.50.56
CORS_ALLOWED_ORIGINS=http://47.101.50.56
GOOGLE_REDIRECT_URI=http://47.101.50.56/auth/callback
COOKIE_DOMAIN=
MULTICA_LARK_SECRET_KEY=
MULTICA_LARK_HTTP_BASE_URL=
MULTICA_LARK_CALLBACK_BASE_URL=
```

`JWT_SECRET` and `POSTGRES_PASSWORD` were generated fresh on the server and are not documented here.

Email is not configured yet. Verification codes are printed in backend logs until `RESEND_API_KEY` or SMTP settings are configured.

## Caddy

Current `/etc/caddy/Caddyfile`:

```caddyfile
:80 {
	handle /health {
		reverse_proxy 127.0.0.1:8080
	}

	handle /ws {
		reverse_proxy 127.0.0.1:8080
	}

	reverse_proxy 127.0.0.1:3001
}
```

The package default Caddyfile was backed up before replacement at `/etc/caddy/Caddyfile.backup.<timestamp>`.

## Daily Deployment

From the local checkout:

```bash
rsync -av --progress \
  --exclude='node_modules' \
  --exclude='.next' \
  --exclude='.turbo' \
  --exclude='server/bin' \
  --exclude='.pnpm-store' \
  --exclude='*.log' \
  --exclude='.DS_Store' \
  --exclude='.git' \
  -e "ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes" \
  /Users/fenix/repos/multica/ root@47.101.50.56:/root/repos/multica/
```

Then rebuild on the server:

```bash
ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes root@47.101.50.56 \
  'cd /root/repos/multica && docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --build'
```

Do not use `rsync --delete` until the remote directory has been inspected.

## Common Commands

```bash
# SSH
ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes root@47.101.50.56

# Container status
cd /root/repos/multica
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml ps

# Logs
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml logs --tail=120 backend
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml logs --tail=120 frontend

# Health from the server
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1/health

# Restart backend after env changes
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml restart backend

# Reload Caddy after Caddyfile changes
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

## First Login

After Alibaba Cloud security group opens `80/tcp`, visit:

```text
http://47.101.50.56
```

If email remains unconfigured, request a login code in the UI and read it from backend logs:

```bash
cd /root/repos/multica
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml logs --tail=200 backend
```

After creating the first workspace, decide whether to lock down signup/workspace creation with:

```env
ALLOW_SIGNUP=false
DISABLE_WORKSPACE_CREATION=true
```

If more users need to sign up first, prefer a domain allowlist and only disable workspace creation:

```env
ALLOWED_EMAIL_DOMAINS=dmyh.tech
DISABLE_WORKSPACE_CREATION=true
```

## Files Changed For China Network Build

The local `Dockerfile` now rewrites Alpine repositories to `https://mirrors.aliyun.com/alpine` before `apk add`.

The local `Dockerfile.web` now sets `COREPACK_NPM_REGISTRY=https://registry.npmmirror.com` before `corepack prepare`.

These changes were needed because the first build stalled on Alpine package downloads and Docker Hub pulls from the new ECS.
