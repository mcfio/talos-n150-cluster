# Forgejo operational runbook

Deployment lives in `kubernetes/apps/forgejo-system/`. This doc covers how git
reaches Forgejo and how to connect git-over-SSH from off-LAN.

## Access model (how git reaches Forgejo)

| Path                  | Transport          | Where it's wired                                                                                                                                                                                                  |
| --------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Web UI, on/off-LAN    | HTTPS              | Split-horizon HTTPRoutes. Internal (chart `httpRoute`) → internal gateway; external away-path (`http-route-external.yaml`) → cloudflared → external gateway, `/user/login` redirected into Cloudflare Access SSO. |
| git-over-HTTPS        | HTTPS + PAT        | Same routes. Password Basic auth is off (`ENABLE_BASIC_AUTHENTICATION: false`); use a Personal Access Token.                                                                                                      |
| git-over-SSH, on-LAN  | raw TCP :22        | Chart `tcpRoute` → internal gateway `ssh` listener → `forgejo-ssh`. `git@git.mcf.io`.                                                                                                                             |
| git-over-SSH, off-LAN | SSH-over-WebSocket | `git-ssh.mcf.io` → cloudflared `ssh://forgejo-ssh` origin, Access-gated. No open firewall port.                                                                                                                   |

## Off-LAN git+SSH

Off-LAN SSH does **not** use `git.mcf.io` — that host is HTTP (away-path). It
uses `git-ssh.mcf.io`, which the tunnel maps to an `ssh://` origin, gated by a
Cloudflare Access self-hosted app. Per client:

1. Install `cloudflared` locally (`brew install cloudflared`).
2. Add to `~/.ssh/config`:
    ```
    Host git-ssh.mcf.io
      ProxyCommand cloudflared access ssh --hostname %h
    ```
3. Register your SSH key on Forgejo (User Settings → SSH Keys) as usual.
4. Clone with the explicit host: `git clone git@git-ssh.mcf.io:owner/repo.git`.
   First connect opens a browser for the Access login.

> On-LAN keeps using `git@git.mcf.io` (direct, faster, no Access round-trip).
> Point your remotes at whichever matches where the machine usually lives; a
> laptop that roams can carry both remotes or just use `git-ssh.mcf.io`
> everywhere (it works on-LAN too, just via the edge).
