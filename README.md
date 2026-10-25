# nanoc_mod

Luanti/Minetest mod for the **NanoC** computer: a small C-like language and
virtual machine with a source-level debugger.

The VM itself lives in the external Lua C module `nanoclib` from the repo
[`nanoc_lib`](../nanoc_lib); this mod is pure Lua and only wires the VM to
nodes, formspecs and techage I/O. The terminal is provided by the `termlib`
mod.

## Dependencies

- `nanoclib` via LuaRocks:
  ```bash
  luarocks make --lua-version 5.1   # in nanoc_lib
  ```
- `secure.trusted_mods` must contain `nanoc`.
- Required mods: **`techage`** (pulls in `tubelib2`) and **`termlib`**.

## minetest.conf

NanoC loads its C module through the insecure environment, so `nanoc` must be
trusted. For the external debugger/terminal, enable the TCP bridge. Add these
to `minetest.conf`:

```ini
# allow the mod to load nanoclib (insecure environment)
secure.trusted_mods = <existing mods>,nanoc

# external terminal/debugger bridge (VS Code / nanoc-tui)
nanoc_bridge_enable = true
nanoc_bridge_port = 41100
nanoc_bridge_bind = 127.0.0.1
```

Each setting must be on its **own line** (`key = value`); do not put several
settings on one line separated by commas. `secure.trusted_mods` itself takes a
comma-separated list of mod names.

For access from another PC in the LAN use `nanoc_bridge_bind = 0.0.0.0` only
together with TLS (see below) or inside a trusted LAN. Never forward the port
on the router — see `doc/manual.md`. All settings and defaults are listed in
[`settingtypes.txt`](settingtypes.txt).

## TLS for the bridge

TLS is built into the bridge, but the C module must be compiled with OpenSSL:

```bash
# Debian/Ubuntu
sudo apt install libssl-dev
# Fedora/RHEL
sudo dnf install openssl-devel

cd ~/Projekte/nanoc_lib
sudo luarocks make tls/nanoc-0.1.0-2.rockspec --lua-version 5.1
```

Without TLS the default build is `sudo luarocks make --lua-version 5.1`. If
`nanoc_bridge_tls = true` is set but nanoclib was built without TLS, the bridge
logs an error and stays disabled. Generate a certificate whose SAN matches the
host/IP used by the clients (a self-signed one is fine for a private server):

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem \
  -days 365 -subj "/CN=nanoc" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
chmod 600 key.pem
```

`minetest.conf`:

```ini
nanoc_bridge_tls = true
nanoc_bridge_tls_cert = /etc/luanti/nanoc-cert.pem
nanoc_bridge_tls_key = /etc/luanti/nanoc-key.pem
# optional: require a client certificate
# nanoc_bridge_tls_ca = /etc/luanti/nanoc-ca.pem
# nanoc_bridge_tls_verify_client = true
```

Clients use `--tls` plus one of:

- `--cafile cert.pem` — normal verification (hostname/IP must match the SAN)
- `--tls-fingerprint <sha256>` — pin the certificate, no CA needed
- `--tls-insecure` — no verification (testing only)

Example: `nanoc-tui --host <server> --tls --cafile cert.pem --token ...`.
For MCP set `NANOC_TLS=1` and either `NANOC_CAFILE`,
`NANOC_TLS_FINGERPRINT` or `NANOC_TLS_INSECURE=1`.

`cert.pem` is public and can be distributed to clients (or publish its
SHA-256 fingerprint); `key.pem` stays on the server. Clients store the
certificate in a per-user directory and pass it with `--cafile`/`NANOC_CAFILE`.

For a complete step-by-step server-owner guide, see
[`doc/server_setup.md`](doc/server_setup.md) (English) or
[`doc/server_setup_DE.md`](doc/server_setup_DE.md) (German).

## Bridge troubleshooting

Symptom: the external client (`nanoc-tui`, VS Code DAP) reports
`error: [Errno 111] Verbindungsaufbau abgelehnt` / "connection refused".

The bridge runs on the **server** (where the world and the mod run), not in the
client. Check the server log after start-up for:

```
[nanoc] bridge listening on <bind>:<port>
```

If that line is missing, the bridge is not active. If it says
`127.0.0.1:<port>` but the client runs on another machine, the bind is wrong.

Common causes:

- `nanoc_bridge_enable` is not `true`, the wrong `minetest.conf` was edited, or
  the server was not **fully restarted** (world reload is not enough; settings
  are read at start-up).
- Typo in the setting name, e.g. `anoc_bridge_bind` → the mod falls back to
  `127.0.0.1`.
- `nanoc_bridge_bind = 127.0.0.1` while the client is on another PC → use
  `0.0.0.0`.
- A firewall on the server blocks TCP 41100.
- Wrong host/port/token. The token is per controller (press **Token** in the
  controller form; only the owner may create it).
- The socket is IPv4-only; use an IPv4 address.
- The controller's **mapblock must be loaded** (a player nearby, or forceload).
  Otherwise the handshake/attach is refused with `NOT_LOADED` and control
  commands answer `NOT_LOADED`. This ties CPU/techage I/O to loaded areas.

Verification:

```bash
# on the server itself (loopback) - must work once the bridge is up
nanoc-tui --host 127.0.0.1 --port 41100 --token <TOKEN>

# from the client machine: is the TCP port reachable?
nc -vz <server> 41100
# Linux/macOS without nc:
timeout 2 bash -c 'cat </dev/null >/dev/tcp/<server>/41100' && echo open
```

Windows PowerShell: `Test-NetConnection <server> -Port 41100`.
Do **not** test the game port 30000 with TCP — Luanti uses **UDP**.

Firewall examples (allow TCP 41100 from the LAN):

```bash
# ufw (Debian/Ubuntu)
sudo ufw allow from <LAN_CIDR> to any port 41100 proto tcp
# firewalld (Fedora/RHEL)
sudo firewall-cmd --add-port=41100/tcp --permanent && sudo firewall-cmd --reload
```

Security: the bridge is a separate **TCP** service; Luanti's game protocol
(UDP) is unrelated and does not protect it. Without TLS it is plaintext and
guarded only by the token. Keep the default bind on `127.0.0.1`; for access
from another machine use TLS or an SSH tunnel
(`ssh -L 41100:127.0.0.1:41100 user@server`)/VPN. Bind `0.0.0.0` only when TLS
is enabled and never forward the port on the router.

## Bridge clients

At most `nanoc_bridge_max_clients` (default **8**) clients can be connected at
once (debugger + terminal/TUI). To see who is connected and to free a slot:

```
/nanoc_bridge              # list: id, controller name/number, owner, role, idle
/nanoc_bridge kick <id>    # disconnect that client
```

Requires the `server` privilege. `role` is `debug` for the controller's debug
owner and `viewer` for the other clients. The protocol does not transmit whether
a client is VS Code or `nanoc-tui` (only the controller token is known).

## CPU budget (server owners)

NanoC does not enforce a hard command/RAM limit and never penalises the owner.
Instead each controller measures how long a tick really takes and adapts its VM
instruction budget to stay near a **time target** (`nanoc_cpu_tick_ms`, default
8 ms). A tick that finishes early gets a larger budget next time; a slow tick
gets a smaller one. An idle server thus gives more compute, a busy one less.
On top of that, a techage-heavy loop (`ta_req_data`/`ta_send_cmd`) that runs
longer than the budget simply **yields and continues in the next tick** - no
error, no damage. When the budget throttles a program, an info message is
written to the debug terminal (channel 4), at most once per second per
controller.

Settings (minetest.conf / `settingtypes.txt`):

| Setting | Default | Meaning |
|---|---|---|
| `nanoc_cpu_tick_ms` | `8.0` | target CPU time per controller tick (ms) |
| `nanoc_cpu_tick_min_ms` | `1.0` | never go below this per tick |
| `nanoc_cpu_player_scale` | `true` | divide the budget by the number of players |
| `nanoc_vm_cycles_start` | `20000` | initial VM instructions per tick |
| `nanoc_vm_cycles_min` / `_max` | `500` / `100000` | instruction budget bounds |

Set `nanoc_cpu_player_scale = false` for a fixed budget, or lower
`nanoc_cpu_tick_ms` on a heavily loaded server (e.g. `3.0`).

## Player manual

Documentation is English by default; a German translation is provided.

- [`doc/manual.md`](doc/manual.md) – English (default)
- [`doc/manual_DE.md`](doc/manual_DE.md) – German

Covers usage, the language, the built-in functions and the timing behaviour of
`sleep()`/`millis()`.

## Install (development)

The authoritative git repo lives outside the Luanti tree. Symlink it into the
mods directory:

```bash
ln -s ~/Projekte/nanoc_mod ~/luanti-5.11.0/mods/nanoc
```

## Contract

The mod validates `nanoclib.protocol()` and `nanoclib.version()` at start-up.
See [`doc/protocol.md`](../nanoc_lib/doc/protocol.md) in `nanoc_lib`.

## Features

- one NanoC VM per controller, cooperative cycle budget per server step
  (adaptive CPU budget, server-owner tunable)
- techage I/O by node number (`ta_send_cmd`, `ta_req_data`, `ta_signal`),
  synchronous like techage's `basic_terminal`
- termlib terminal as display **and** keyboard (control chars + `ESC` sequences)
- simplified in-game panel: only `log()` messages + `Run`, `Stop`, `Reset`,
  `Clear`, `Token`, `Update` (code/terminal are external)
- controller **name** via the Techage Info Tool; infotext
  `NanoC Controller "<name>" <number>`
- external debugger/terminal via `nanoc_client` (TCP, optional TLS)

## License

AGPLv3 or later. See [`LICENSE.txt`](LICENSE.txt).
