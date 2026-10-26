# NanoC-Server-Setup für Server-Owner

English version: [server_setup.md](server_setup.md)

Diese Anleitung beschreibt, wie ein Server-Owner die NanoC-Bridge mit TLS
einrichtet, damit externe Clients (nanoc-client, nanoc-tui, VS Code, MCP) sicher
auf die Controller des Servers zugreifen können.

Sie beschreibt nur den Server. Spieler benötigen später lediglich Adresse,
Port, Zertifikat und den Token des jeweiligen Controllers.

## Platzhalter

| Platzhalter | Bedeutung |
|---|---|
| `<SERVER_MODS>` | Mods-Verzeichnis des Luanti-Servers |
| `<NANOC_LIB>` | Quellverzeichnis von `nanoc_lib` |
| `<CERT_DIR>` | Geschütztes Verzeichnis für Zertifikat und Key |
| `<SERVER_USER>` | Benutzer, unter dem der Luanti-Server läuft |
| `<LAN_IP>` | LAN-/VPN-Adresse des Servers |
| `<LAN_CIDR>` | LAN-Subnetz für Firewall-Regeln (z. B. Adressbereich des LANs) |
| `<PUBLIC_HOSTNAME>` | Name, unter dem die Clients den Server erreichen (z. B. DDNS) |
| `<PORT>` | TCP-Port der Bridge (Standard: `41100`) |
| `<TOKEN>` | Token des Controllers aus dem Controller-Formular |
| `<CERT>` | Pfad zu `cert.pem` |
| `<KEY>` | Pfad zu `key.pem` |

## 1. Voraussetzungen

- Luanti-Server mit Zugriff auf die **Insecure Environment**
  (`secure.trusted_mods`).
- Build-Werkzeuge: C-Compiler, `make`, Lua-5.1-Header, LuaRocks.
- Für TLS: OpenSSL-Entwicklungspaket (`libssl-dev` bzw. `openssl-devel`).
- Ein TCP-Port für die Bridge; dieser ist **nicht** der UDP-Spielport.
- Zugriff auf Router/Firewall, falls Clients von außen zugreifen sollen.

## 2. `nanoclib` bauen und installieren

Es gibt zwei Builds:

- **Standard** (kein TLS, keine OpenSSL-Abhängigkeit):
  ```bash
  cd <NANOC_LIB>
  sudo luarocks make --lua-version 5.1
  ```
- **TLS** (empfohlen für die Bridge):
  ```bash
  cd <NANOC_LIB>
  sudo luarocks make tls/nanoc-0.1.0-2.rockspec --lua-version 5.1
  ```

Prüfen:

```bash
lua5.1 -e 'local n=require("nanoclib"); print(n.version(), n.net_tls_available())'
```

Erwartet: eine aktuelle Version (z. B. `0.2.6`) und `true` beim TLS-Build.
Der Luanti-Prozess muss das Modul über den normalen Lua-Paketpfad finden.

## 3. Mod installieren

`nanoc_mod` nach `<SERVER_MODS>/nanoc` kopieren (Verzeichnis oder Symlink).
In der `minetest.conf` freischalten:

```ini
secure.trusted_mods = <bestehende Mods>,nanoc
```

Ohne diesen Eintrag kann die Mod ihre C-Bibliothek nicht laden.

## 4. TLS-Zertifikat erstellen

Für einen eigenen Server reicht ein selbstsigniertes Zertifikat. Wichtig ist,
dass der **Name, den die Clients verwenden**, im Zertifikat steht (SAN).

```bash
mkdir -p <CERT_DIR>
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout <KEY> -out <CERT> -days 3650 \
  -subj "/CN=<PUBLIC_HOSTNAME>" \
  -addext "subjectAltName=DNS:<PUBLIC_HOSTNAME>,DNS:localhost,IP:<LAN_IP>,IP:127.0.0.1"
```

Hinweise:

- Clients sollen den **Namen** verwenden, nicht eine wechselnde öffentliche
  IP. Bei dynamischer IP daher einen DDNS-Namen in `DNS:` eintragen.
- Für reine LAN-Tests zusätzlich die LAN-IP als `IP:<LAN_IP>` aufnehmen.
- Eine öffentliche IP nur dann als `IP:` eintragen, wenn sie stabil ist.
- Alternativ kann ein Zertifikat einer öffentlichen CA verwendet werden; die
  Bridge ist kein HTTP-Dienst, daher ist DNS-01 oder ein eigenes CA-Setup
  nötig. Für die meisten Server ist selbstsigniert + `--cafile` einfacher.

Rechte setzen:

```bash
chown <SERVER_USER>:<SERVER_USER> <KEY> <CERT>
chmod 600 <KEY>
chmod 644 <CERT>
```

Läuft der Server als `root`, kann der Key `root:root` gehören. Besser ist ein
eigener, nicht-privilegierter Server-Benutzer.

`<KEY>` niemals weitergeben oder in Backups/Weltordner legen. `<CERT>` ist
öffentlich und darf an Clients verteilt werden.

### Zertifikat an Clients verteilen

`<CERT>` ist öffentlich. `<KEY>` bleibt auf dem Server; das Zertifikat kann
per Download, Client-Paket oder Chat verteilt werden, alternativ der
SHA-256-Fingerprint. Ein guter Server-Ort ist `<CERT_DIR>` außerhalb von
Welt-/Mod-Verzeichnissen (z. B. `/etc/luanti/nanoc/`).

Clients legen das Zertifikat in einem Benutzerverzeichnis ab, z. B.:

- Windows: `%APPDATA%\nanoc\cert.pem`
- Linux: `~/.config/nanoc/cert.pem`
- macOS: `~/Library/Application Support/nanoc/cert.pem`

Sie übergeben es mit `--cafile` (VS Code `"cafile"`, MCP `NANOC_CAFILE`) oder
pinnen es mit `--tls-fingerprint`. `<KEY>` niemals weitergeben. Bei einer
Zertifikatserneuerung das neue Zertifikat bzw. den Fingerprint verteilen.

## 5. `minetest.conf` konfigurieren

Server vorher stoppen und die Datei sichern; Luanti schreibt sie beim Beenden
neu.

```ini
secure.trusted_mods = <bestehende Mods>,nanoc

nanoc_bridge_enable = true
nanoc_bridge_bind = 0.0.0.0
nanoc_bridge_port = <PORT>
nanoc_bridge_tls = true
nanoc_bridge_tls_cert = <CERT>
nanoc_bridge_tls_key = <KEY>

# Optional: Schutz vor zu vielen/zu schnellen Clients
nanoc_bridge_max_clients = 8
nanoc_bridge_handshake_timeout = 5
nanoc_bridge_cmd_rate = 100
```

Wichtig:

- `nanoc_bridge_bind = 127.0.0.1` = nur lokal.
- `0.0.0.0` = LAN/Internet; **nur zusammen mit TLS** verwenden.
- Jede Einstellung in einer eigenen Zeile.
- Optionale gegenseitige TLS-Authentifizierung:
  `nanoc_bridge_tls_ca` und `nanoc_bridge_tls_verify_client = true`.
  Der mitgelieferte Python-Client präsentiert derzeit kein Client-Zertifikat;
  für mTLS ist ein anderer Client oder ein TLS-Proxy nötig.

## 6. Firewall und Router

Auf dem Server den TCP-Port freigeben, z. B.:

```bash
# ufw
sudo ufw allow from <LAN_CIDR> to any port <PORT> proto tcp

# firewalld
sudo firewall-cmd --add-port=<PORT>/tcp --permanent
sudo firewall-cmd --reload
```

Für Zugriff aus dem Internet im Router eine **TCP**-Weiterleitung von
`<PORT>` auf `<LAN_IP>` einrichten. Nicht den UDP-Spielport weiterleiten.

Wenn der Zugriff von zu Hause über den öffentlichen Namen nicht funktioniert,
obwohl die Weiterleitung stimmt, fehlt oft **NAT-Loopback/Hairpin**. Das ist
kein Serverfehler; von außen (anderes Netz, Mobilfunk-Hotspot) testen.

Besser als ein offener Port sind VPN oder SSH-Tunnel. Wenn der Port offen
bleibt: auf Quell-IPs beschränken und nach der Testphase schließen.

## 7. Server starten und prüfen

Server neu starten. Im Log muss stehen:

```text
[nanoc] bridge listening on ...:<PORT> (TLS)
```

TLS-Verbindung prüfen:

```bash
openssl s_client -connect <PUBLIC_HOSTNAME>:<PORT> \
  -servername <PUBLIC_HOSTNAME> -CAfile <CERT>
```

Erwartet: TLS-Handshake erfolgreich und
`Verify return code: 0 (ok)`.

Hat der Controller noch kein Programm bzw. keine Ausgabe, mit `nanoc catalog`
(Bridge/Token) oder `nanoc scan --radius 8` (Controller-Bereich geladen)
prüfen; `nanoc read` zeigt nur Terminalausgabe.

## 8. Client verbinden

Client in einer virtuellen Umgebung installieren:

```bash
python3 -m venv <VENV>
<VENV>/bin/pip install nanoc-client
```

Den **Token** im Spiel am Controller über die Schaltfläche **Token** holen.
Der Token gilt nur für diesen Controller und nur für dessen Owner bzw. Spieler
mit `protection_bypass`. Er ist ein Geheimnis.

Test über den öffentlichen Namen:

```bash
<VENV>/bin/nanoc read --host <PUBLIC_HOSTNAME> --port <PORT> \
  --tls --cafile <CERT> --token <TOKEN> --seconds 3
```

Test über die LAN-IP (wenn die LAN-IP im SAN steht):

```bash
<VENV>/bin/nanoc read --host <LAN_IP> --port <PORT> \
  --tls --cafile <CERT> --token <TOKEN> --seconds 3
```

Alternativen:

- Zertifikat pinnen statt CA-Datei:
  `--tls-fingerprint <SHA256>`; Fingerprint mit
  `openssl x509 -in <CERT> -noout -fingerprint -sha256` ermitteln.
- `--tls-insecure` nur zum Testen, niemals im Dauerbetrieb.
- Bei einem CA-signierten Zertifikat kann `<CERT>` entfallen; der Client nutzt
  dann den System-CA-Speicher.

VS Code (Launch-Konfiguration): `host`, `port`, `token`, `"tls": true`,
`"cafile": "<CERT>"`. Für MCP:

```text
NANOC_HOST=<PUBLIC_HOSTNAME>
NANOC_PORT=<PORT>
NANOC_TOKEN=<TOKEN>
NANOC_TLS=1
NANOC_CAFILE=<CERT>
```

## 9. Sicherheit

- **TLS + Token** sind die Absicherung. Die Bridge nie im Klartext ins
  Internet stellen.
- Der Token erlaubt die Steuerung des Controllers. Pro Controller getrennt
  behandeln und nur an vertrauenswürdige Personen geben.
- Der Server sollte nicht als `root` laufen; dann gehören Key/Cert dem
  Server-Benutzer.
- `key.pem` bleibt auf dem Server (`chmod 600`), `cert.pem` darf verteilt
  werden.
- Zugriff nach Möglichkeit auf Quell-IPs beschränken; besser VPN/SSH-Tunnel.
- Token bei Verdacht auf Weitergabe erneuern; Zertifikat bei Namens-/IP-
  Änderung neu erzeugen und bei den Clients austauschen.
- Die Bridge begrenzt Clients, Handshake-Zeit und Kommandorate; das ersetzt
  keine Firewall.

## 10. Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| `connection refused` | Bridge nicht gebunden/gestartet, falscher Port, Firewall, Portweiterleitung |
| `connection reset` | Klartext-Client gegen TLS-Bridge (oder TLS-Client gegen Klartext-Bridge) |
| Zertifikat nicht verifiziert | Hostname nicht im SAN, falsche CA-Datei, rohe IP statt Name |
| `bad token` | Token eines anderen Controllers oder veraltet |
| `NOT_LOADED` | Controller-Bereich ist nicht geladen (Spieler weit weg, kein Forceload) |
| Bridge startet nicht | `secure.trusted_mods` ohne `nanoc`, fehlende Cert/Key-Pfade, Port belegt |
| „nanoclib has no TLS support“ | `nanoclib` ohne TLS-Build installiert |
| LAN ok, Internet nicht | Portweiterleitung, Firewall, CGNAT oder DDNS |
| Von zu Hause über öffentlichen Namen kein Zugriff | NAT-Loopback fehlt; von außen testen |

## 11. Updates und Wartung

Nach einem Update von `nanoc_lib` oder `nanoc_mod`:

1. `nanoclib` neu bauen (bei TLS mit dem TLS-Rockspec).
2. Server neu starten.
3. Log auf die `(TLS)`-Zeile prüfen.
4. Welt vorher sichern; NanoC-Images werden bei Formatänderungen automatisch
   aus dem Programmtext neu kompiliert.

## 12. Checkliste

- [ ] `secure.trusted_mods` enthält `nanoc`
- [ ] `nanoclib` mit TLS gebaut (`net_tls_available() == true`)
- [ ] Zertifikat/Key vorhanden, Rechte korrekt
- [ ] `minetest.conf`: Bind, Port, TLS, Cert, Key
- [ ] Firewall und ggf. Router-Weiterleitung (TCP)
- [ ] Server neu gestartet, Log zeigt `(TLS)`
- [ ] TLS-Handshake vom Client erfolgreich
- [ ] Token des richtigen Controllers getestet
- [ ] Zugriff beschränkt bzw. nach Test wieder geschlossen
