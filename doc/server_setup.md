# NanoC server setup for server owners

German version: [server_setup_DE.md](server_setup_DE.md)

This guide describes how a server owner sets up the NanoC bridge with TLS so
that external clients (nanoc-client, nanoc-tui, VS Code, MCP) can access the
server's controllers securely.

It covers the server only. Players later need just the address, port,
certificate and the token of their controller.

## Placeholders

| Placeholder | Meaning |
|---|---|
| `<SERVER_MODS>` | Luanti server mods directory |
| `<NANOC_LIB>` | `nanoc_lib` source directory |
| `<CERT_DIR>` | Protected directory for certificate and key |
| `<SERVER_USER>` | User that runs the Luanti server |
| `<LAN_IP>` | LAN/VPN address of the server |
| `<LAN_CIDR>` | LAN subnet for firewall rules (e.g. the LAN address range) |
| `<PUBLIC_HOSTNAME>` | Name clients use to reach the server (e.g. DDNS) |
| `<PORT>` | TCP port of the bridge (default: `41100`) |
| `<TOKEN>` | Controller token from the controller form |
| `<CERT>` | Path to `cert.pem` |
| `<KEY>` | Path to `key.pem` |

## 1. Prerequisites

- Luanti server with access to the **insecure environment**
  (`secure.trusted_mods`).
- Build tools: C compiler, `make`, Lua 5.1 headers, LuaRocks.
- For TLS: OpenSSL development package (`libssl-dev` or `openssl-devel`).
- A TCP port for the bridge; this is **not** the UDP game port.
- Access to the router/firewall if clients connect from the internet.

## 2. Build and install `nanoclib`

There are two builds:

- **Standard** (no TLS, no OpenSSL dependency):
  ```bash
  cd <NANOC_LIB>
  sudo luarocks make --lua-version 5.1
  ```
- **TLS** (recommended for the bridge):
  ```bash
  cd <NANOC_LIB>
  sudo luarocks make tls/nanoc-0.1.0-2.rockspec --lua-version 5.1
  ```

Verify:

```bash
lua5.1 -e 'local n=require("nanoclib"); print(n.version(), n.net_tls_available())'
```

Expected: a current version (e.g. `0.2.5`) and `true` for the TLS build.
The Luanti process must find the module on the normal Lua package path.

## 3. Install the mod

Copy `nanoc_mod` to `<SERVER_MODS>/nanoc` (directory or symlink). Enable it in
`minetest.conf`:

```ini
secure.trusted_mods = <existing mods>,nanoc
```

Without this entry the mod cannot load its C library.

## 4. Create a TLS certificate

A self-signed certificate is sufficient for a private server. It is important
that the **name clients use** is present in the certificate (SAN).

```bash
mkdir -p <CERT_DIR>
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout <KEY> -out <CERT> -days 3650 \
  -subj "/CN=<PUBLIC_HOSTNAME>" \
  -addext "subjectAltName=DNS:<PUBLIC_HOSTNAME>,DNS:localhost,IP:<LAN_IP>,IP:127.0.0.1"
```

Notes:

- Clients should use the **name**, not a changing public IP. For a dynamic IP,
  put a DDNS name in `DNS:`.
- For LAN-only tests, also add the LAN IP as `IP:<LAN_IP>`.
- Add a public IP as `IP:` only if it is stable.
- A publicly trusted CA certificate can be used instead; the bridge is not an
  HTTP service, so DNS-01 or a private CA setup is required. For most servers,
  self-signed plus `--cafile` is simpler.

Set permissions:

```bash
chown <SERVER_USER>:<SERVER_USER> <KEY> <CERT>
chmod 600 <KEY>
chmod 644 <CERT>
```

If the server runs as `root`, the key may be owned by `root:root`. A dedicated
non-privileged server user is preferable.

Never share `<KEY>` or put it into backups/world folders. `<CERT>` is public
and may be distributed to clients.

### Publish the certificate to clients

`<CERT>` is public. Keep `<KEY>` on the server and publish the certificate
(download link, client pack, chat) or its SHA-256 fingerprint. A good server
location is `<CERT_DIR>` outside the world/mod directory (for example
`/etc/luanti/nanoc/`).

Clients store the certificate in a per-user directory, for example:

- Windows: `%APPDATA%\nanoc\cert.pem`
- Linux: `~/.config/nanoc/cert.pem`
- macOS: `~/Library/Application Support/nanoc/cert.pem`

They pass it with `--cafile` (VS Code `"cafile"`, MCP `NANOC_CAFILE`) or pin
it with `--tls-fingerprint`. Never distribute `<KEY>`. When the certificate is
renewed, send the new file or fingerprint to clients.

## 5. Configure `minetest.conf`

Stop the server first and back up the file; Luanti rewrites it on exit.

```ini
secure.trusted_mods = <existing mods>,nanoc

nanoc_bridge_enable = true
nanoc_bridge_bind = 0.0.0.0
nanoc_bridge_port = <PORT>
nanoc_bridge_tls = true
nanoc_bridge_tls_cert = <CERT>
nanoc_bridge_tls_key = <KEY>

# Optional: protection against too many/fast clients
nanoc_bridge_max_clients = 8
nanoc_bridge_handshake_timeout = 5
nanoc_bridge_cmd_rate = 100
```

Important:

- `nanoc_bridge_bind = 127.0.0.1` = local only.
- `0.0.0.0` = LAN/internet; **TLS only**.
- Each setting on its own line.
- Optional mutual TLS:
  `nanoc_bridge_tls_ca` and `nanoc_bridge_tls_verify_client = true`.
  The bundled Python client does not present a client certificate yet; use a
  different client or a TLS proxy for mTLS.

## 6. Firewall and router

Open the TCP port on the server, for example:

```bash
# ufw
sudo ufw allow from <LAN_CIDR> to any port <PORT> proto tcp

# firewalld
sudo firewall-cmd --add-port=<PORT>/tcp --permanent
sudo firewall-cmd --reload
```

For internet access, create a **TCP** forward from `<PORT>` to `<LAN_IP>` on
the router. Do not forward the UDP game port for NanoC.

If access via the public name fails from home while the forward is correct,
the router probably lacks **NAT loopback/hairpin**. This is not a server
error; test from outside (another network, mobile hotspot).

A VPN or SSH tunnel is better than an open port. If the port stays open,
restrict source IPs and close it after the test phase.

## 7. Start and verify the server

Restart the server. The log must contain:

```text
[nanoc] bridge listening on ...:<PORT> (TLS)
```

Check the TLS connection:

```bash
openssl s_client -connect <PUBLIC_HOSTNAME>:<PORT> \
  -servername <PUBLIC_HOSTNAME> -CAfile <CERT>
```

Expected: successful TLS handshake and `Verify return code: 0 (ok)`.

If the controller has no program/output yet, verify with `nanoc catalog`
(bridge/token) or `nanoc scan --radius 8` (controller area loaded); `nanoc read`
shows only terminal output.

## 8. Connect a client

Install the client in a virtual environment:

```bash
python3 -m venv <VENV>
<VENV>/bin/pip install nanoc-client
```

Get the **token** in-game from the controller's **Token** button. The token is
valid only for that controller and only for its owner or players with
`protection_bypass`. Treat it as a secret.

Test via the public name:

```bash
<VENV>/bin/nanoc read --host <PUBLIC_HOSTNAME> --port <PORT> \
  --tls --cafile <CERT> --token <TOKEN> --seconds 3
```

Test via the LAN IP (if the LAN IP is in the SAN):

```bash
<VENV>/bin/nanoc read --host <LAN_IP> --port <PORT> \
  --tls --cafile <CERT> --token <TOKEN> --seconds 3
```

Alternatives:

- Pin the certificate instead of using a CA file:
  `--tls-fingerprint <SHA256>`; get the fingerprint with
  `openssl x509 -in <CERT> -noout -fingerprint -sha256`.
- `--tls-insecure` only for testing, never permanently.
- With a CA-signed certificate, `<CERT>` can be omitted; the client then uses
  the system CA store.

VS Code (launch configuration): `host`, `port`, `token`, `"tls": true`,
`"cafile": "<CERT>"`. For MCP:

```text
NANOC_HOST=<PUBLIC_HOSTNAME>
NANOC_PORT=<PORT>
NANOC_TOKEN=<TOKEN>
NANOC_TLS=1
NANOC_CAFILE=<CERT>
```

## 9. Security

- **TLS + token** are the protection. Never expose the bridge in plaintext to
  the internet.
- The token allows control of the controller. Handle it per controller and
  share it only with trusted people.
- Do not run the server as `root`; then key/cert belong to the server user.
- Keep `key.pem` on the server (`chmod 600`); `cert.pem` may be distributed.
- Restrict access to source IPs where possible; prefer VPN/SSH tunnels.
- Renew/rotate the token if it may have leaked; regenerate the certificate
  when the name/IP changes and update clients.
- The bridge limits clients, handshake time and command rate; that does not
  replace a firewall.

## 10. Troubleshooting

| Symptom | Cause / solution |
|---|---|
| `connection refused` | Bridge not bound/started, wrong port, firewall, port forward |
| `connection reset` | Plaintext client against a TLS bridge (or TLS client against plaintext) |
| Certificate not verified | Hostname not in SAN, wrong CA file, raw IP instead of name |
| `bad token` | Token of another controller or outdated |
| `NOT_LOADED` | Controller area not loaded (player too far away, no forceload) |
| Bridge does not start | `secure.trusted_mods` missing `nanoc`, cert/key paths, port in use |
| "nanoclib has no TLS support" | `nanoclib` installed without the TLS build |
| LAN works, internet does not | Port forward, firewall, CGNAT or DDNS |
| No access via public name from home | NAT loopback missing; test from outside |

## 11. Updates and maintenance

After updating `nanoc_lib` or `nanoc_mod`:

1. Rebuild `nanoclib` (use the TLS rockspec for TLS).
2. Restart the server.
3. Check the log for the `(TLS)` line.
4. Back up the world first; NanoC images are recompiled automatically from the
   program text when the format changes.

## 12. Checklist

- [ ] `secure.trusted_mods` contains `nanoc`
- [ ] `nanoclib` built with TLS (`net_tls_available() == true`)
- [ ] Certificate/key present, permissions correct
- [ ] `minetest.conf`: bind, port, TLS, cert, key
- [ ] Firewall and, if needed, router forward (TCP)
- [ ] Server restarted; log shows `(TLS)`
- [ ] TLS handshake from a client successful
- [ ] Token of the correct controller tested
- [ ] Access restricted or port closed after the test
