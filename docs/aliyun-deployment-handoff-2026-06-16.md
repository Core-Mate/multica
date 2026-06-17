# Aliyun Deployment Handoff - 2026-06-16

This handoff is for the next agent continuing the Multica redeployment after the previous Volcengine instance became unavailable due to billing issues. Treat the old deployment as non-recoverable unless the user later provides new access or a backup.

## Current Objective

Redeploy Multica onto the new server and bring up a fresh self-hosted instance. The server-side deployment is now running; Alibaba Cloud security group access for inbound `80/tcp` still needs to be opened before the app is reachable from outside the server.

2026-06-17 recheck: SSH works and the Docker/Caddy stack is healthy from inside the server. External `80/tcp` still times out when bypassing local proxies, while external `3000/tcp` reaches an unrelated old CoreMate Lite Next.js service. Do not treat browser/proxy `502` responses as a Multica backend failure until `80/tcp` is opened in the Alibaba Cloud security group.

## Verified Server Access

New server:

```text
IP: 47.101.50.56
SSH user: root
SSH key: /Users/fenix/Downloads/lite-dev.pem
Cloud: Alibaba Cloud ECS
Region: cn-shanghai
Zone: cn-shanghai-e
Instance type: ecs.g9i.large
Hostname: iZuf640z2og5v1j32f6h2qZ
OS: Debian GNU/Linux 13 (trixie)
Kernel: 6.12.74+deb13+1-amd64
```

The PEM file exists locally and its permissions were fixed from `0644` to `0600`. SSH login as `root` has been verified.

Use this command:

```bash
ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes root@47.101.50.56
```

Key fingerprint seen locally:

```text
2048 SHA256:o2zW1FwvkJJKyWmgvQeV+4iFUwQfX2yevas8zRgi1yw no comment (RSA)
```

## Provider Evidence

Public registry and metadata checks both point to Alibaba Cloud, not Volcengine.

```text
ipinfo org: AS37963 Hangzhou Alibaba Advertising Co.,Ltd.
WHOIS netname: ALISOFT / Aliyun Computing Co., LTD
metadata region-id: cn-shanghai
metadata zone-id: cn-shanghai-e
metadata instance type: ecs.g9i.large
```

Metadata endpoint used from inside the server:

```bash
curl -fsS http://100.100.100.200/latest/meta-data/region-id
curl -fsS http://100.100.100.200/latest/meta-data/zone-id
curl -fsS http://100.100.100.200/latest/meta-data/instance/instance-type
```

## Remote Baseline

Initial baseline before deployment:

```text
Docker: missing
Docker Compose plugin: missing
Caddy: missing
/root/repos/multica: missing
Root disk: 40G total, 31G available, 17% used
Memory: 7.4Gi total, 6.2Gi available
Swap: none
SSH port 22: reachable
```

The next agent should install Docker, Docker Compose plugin, and a reverse proxy before deployment.

Current deployment state after execution:

```text
Docker: installed
Docker Compose: installed as docker compose / docker-compose 2.26.1
Caddy: installed and active
/root/repos/multica: present
Multica backend: running on 127.0.0.1:8080
Multica frontend: running on 127.0.0.1:3001 because public 3000 was already occupied
Postgres: running and healthy
External 80/tcp: blocked outside the server, likely Alibaba Cloud security group
```

## Relevant Repo Files

Use these as the deployment references:

```text
SELF_HOSTING.md
SELF_HOSTING_ADVANCED.md
docker-compose.selfhost.yml
docker-compose.selfhost.build.yml
Makefile
DEPLOY_VOLCENGINE.md
DEPLOY_ALIYUN.md
```

`DEPLOY_VOLCENGINE.md` is useful as a template, but it is stale for the new server. It points to the old Volcengine IP `115.190.130.45` and contains old environment examples. Do not copy secrets or old IP values blindly.

## Important Deployment Notes

The current `.env.example` contains old public URL values for `115.190.130.45`. If `make selfhost-build` creates `.env` from `.env.example`, edit the generated `.env` before treating the service as usable.

For the new IP, current public URL values are:

```env
FRONTEND_ORIGIN=http://47.101.50.56
MULTICA_APP_URL=http://47.101.50.56
MULTICA_PUBLIC_URL=http://47.101.50.56
CORS_ALLOWED_ORIGINS=http://47.101.50.56
```

The remote `.env` also uses `FRONTEND_PORT=3001` to avoid an unrelated existing Node service on public port `3000`.

Generate fresh secrets on the new server:

```bash
openssl rand -hex 32
openssl rand -hex 24
```

Use those for `JWT_SECRET` and `POSTGRES_PASSWORD`. Do not reuse values from old docs unless the user explicitly confirms they are intended for the new instance.

Public-login warning: `MULTICA_DEV_VERIFICATION_CODE=888888` is convenient for private testing, but it is unsafe on a publicly reachable instance. For a public IP deployment, set `APP_ENV=production` and clear `MULTICA_DEV_VERIFICATION_CODE`, then prefer configuring email delivery or reading one-time codes from backend logs during bootstrap.

## Suggested Next Steps

1. Open inbound `80/tcp` in the Alibaba Cloud security group for `47.101.50.56`.
2. Verify `curl --noproxy '*' http://47.101.50.56/health` from the local machine.
3. Visit `http://47.101.50.56`.
4. Log in, create the first workspace, then decide whether to lock down signup/workspace creation.
5. If a domain is added, open `443/tcp`, switch Caddy to the domain, and update URL env vars.

## Candidate Sync Command

Run from the local repo after verifying the target directory exists:

```bash
rsync -av --progress \
  --exclude='node_modules' \
  --exclude='.next' \
  --exclude='.turbo' \
  --exclude='server/bin' \
  --exclude='.pnpm-store' \
  --exclude='*.log' \
  --exclude='.DS_Store' \
  -e "ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes" \
  /Users/fenix/repos/multica/ root@47.101.50.56:/root/repos/multica/
```

Avoid `--delete` on the first sync unless the next agent has inspected the remote directory and confirmed it is safe.

## Candidate Caddyfile

For plain HTTP on the IP address:

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

Use `3001` here because the Multica frontend container is published as `127.0.0.1:3001->3000/tcp`. The public host port `3000` is already occupied by an unrelated `/opt/coremate-lite-backend/apps/admin` Next.js process.

If a domain is added later, switch to the domain name and update `FRONTEND_ORIGIN`, `MULTICA_APP_URL`, `MULTICA_PUBLIC_URL`, `CORS_ALLOWED_ORIGINS`, and any OAuth callback URLs.

## Verification Commands Already Run

Local key check:

```bash
stat -f '%Sp %Su %Sg %z %N' /Users/fenix/Downloads/lite-dev.pem
ssh-keygen -l -f /Users/fenix/Downloads/lite-dev.pem
```

SSH identity and OS check:

```bash
ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes -o BatchMode=yes root@47.101.50.56 \
  'hostname && id && uname -a && lsb_release -a'
```

Cloud metadata check:

```bash
ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes root@47.101.50.56 \
  'curl -fsS http://100.100.100.200/latest/meta-data/region-id; echo; curl -fsS http://100.100.100.200/latest/meta-data/zone-id; echo; curl -fsS http://100.100.100.200/latest/meta-data/instance/instance-type; echo'
```

Remote baseline check:

```bash
ssh -i /Users/fenix/Downloads/lite-dev.pem -o IdentitiesOnly=yes root@47.101.50.56 \
  'docker --version; docker compose version; caddy version; df -h /; free -h; test -d /root/repos/multica && echo repo-present || echo repo-missing'
```

## Open Questions For The Next Agent

1. Should the replacement deployment stay on bare IP HTTP, or will the user provide a domain and HTTPS?
2. Should signup be locked down after the first admin workspace is created?
3. Which email delivery path should be used for auth codes: Resend, SMTP, or temporary log-copy bootstrap?
4. Are Feishu/Lark and GitHub App integrations required on the replacement server, and if so, what fresh secrets should be used?
5. Should the stale Volcengine deployment guide be renamed, replaced, or kept as historical reference after the new deployment succeeds?
