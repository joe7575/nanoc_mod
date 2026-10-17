# NanoC – Handbuch

NanoC ist ein kleiner Computer für Luanti/Minetest. Man schreibt Programme in
einer C-ähnlichen Sprache, die auf dem Server ausgeführt werden. Damit lassen
sich Techage-/TechPack-Maschinen direkt (per Knotennummer) steuern.

## Aufbau

| Node | Zweck |
|---|---|
| `nanoc:controller` | Der Computer (Programm-Editor + Ausführung) |
| `nanoc:terminal` | Live-Anzeige der Terminal-Ausgabe des Controllers |

Optional kann ein `termlib:terminal1` (aus der `termlib`-Mod) als Anzeige
**und** Tastatur dienen – statt `nanoc:terminal`. Anschließen wie gewohnt:
Terminal in die Hand nehmen, Controller linksklicken, platzieren, `@connect`.
Getippte Kommandos kommen im Programm über `key()` an. Die Controller-Ausgabe
geht an termlib, daher wirken Steuerzeichen (`\a \b \t \n \r`) und
Escape-Sequenzen (`\27…`, z. B. `\27\1` Clear, `\27\2<row>`, `\27\3<font>`,
`\27\4<cmd>\n`, `\27\5<1|2>`, `\27\6<pos><row>`, `\27\7`) direkt – siehe
`examples/termlib_demo.nanoc`.

## Bedienung

1. **Controller** platzieren und rechtsklicken.
2. Programm in das obere Feld schreiben, **Save+Compile**, dann **Run**.
3. **`nanoc:terminal`** in der Nähe platzieren und rechtsklicken – es zeigt
   die Ausgabe laufend (ohne Tastendruck) an.

Buttons: `Save+Compile`, `Run`, `Stop`, `Reset`, `Clear`.

## Sprache (Beispiele)

```
int32 count = 0

while (1) {
    count = count + 1
    printf("count=%d\n", count)
    sleep(1000)
}
```

Unterstützt werden u. a. `int32`, `str8`, `while`, `if/else`, Funktionen
(`func`), Arrays, `printf` (Formate `%d`, `%u`, `%h`, `%s`, `%%`).

Funktionen haben **typisierte Parameter** und einen optionalen Rückgabetyp
**vor** dem Namen (weggelassen = `void`):

```
func int32 add(int32 a, int32 b) {
    return a + b
}

int32 x = add(3, 4)
```

Sprachreferenz:
<https://github.com/joe7575/nanoc/blob/main/docs/nanoc_reference.md>

### Typen, Variablen, Konstanten

`int32` (32-Bit-Ganzzahl), `str8` (String; Name endet auf `$`), Arrays
`int32 buf[10]`. `const NAME = wert` definiert eine Konstante. Variablen
entstehen automatisch bei Zuweisung; Anweisungen enden mit Zeilenende oder `;`.

```
int32 count = 0
str8 name$ = "Hallo"
int32 buf[10]
const MAX = 100
count = count + 1
buf[0] = count
```

Operatoren: `+ - * / % mod`, `& | ^ << >>`, `== != < <= > >=`, `and or not`,
`++ --`. Strings lassen sich mit `+` verketten und mit `== < >` vergleichen.

### Strings und Escape-Sequenzen

String-Literale unterstützen Escape-Sequenzen (zur Compile-Zeit dekodiert):

| Escape | Bedeutung |
| ------ | --------- |
| `\n` | Zeilenumbruch |
| `\t` | Tabulator |
| `\r` | Wagenrücklauf |
| `\a` | BEL (0x07) |
| `\b` | Backspace |
| `\f` | Seitenvorschub |
| `\v` | Vertikaltabulator |
| `\e` | ESC (0x1B) |
| `\\` | Backslash |
| `\"` `\'` | Anführungszeichen |
| `\xHH` | Hex-Byte, z. B. `\x1b` |
| `\ddd` | Dezimal-Byte, z. B. `\27` |

Es gibt **keine** C-Oktal-Escapes: `\ddd` ist dezimal, wie in Lua.

### Kontrollfluss

```
if (x > 0) { ... } else { ... }
while (i < 10) { i++ }
for i = 1 to 10 { printf("%d\n", i) }
for i = 10 to 0 step -1 { ... }
break            // innerste for/while-Schleife verlassen (C-Stil)
breakpoint()     // Debugger-Breakpoint (das frühere 'break')
dispatch(expr) { func0, func1, func2 }   // Aufruf per Index (0-basiert)
end      // Programm beenden
reti     // aus einem Interrupt-Handler zurückkehren
```

### Funktionen und Arrays

Parameter sind typisiert; der optionale Rückgabetyp steht **vor** dem Namen
(weggelassen = `void`). Array-Parameter werden per `int32[]` als Referenz
übergeben.

```
func int32 add(int32 a, int32 b) {
    return a + b
}

func sum(int32[] arr, int32 n) {
    int32 s = 0
    for i = 0 to n - 1 { s = s + arr[i] }
    return s
}
```

### Standardfunktionen

- Numerik: `rnd(n)`, `abs(n)`
- Strings: `len(s$)`, `left$(s$,n)`, `right$(s$,n)`, `mid$(s$,start,len)`,
  `str$(n)`, `hex$(n)`, `instr(start,s$,find$)`, `string$(n,char$)`
  (das `$` am Ende ist optional: `str8 name`, `left(...)`, `hex(...)`, …)
- String <-> Array: `str2arr(arr,offs,"text")` kopiert einen String inkl. `\0`
  in ein Byte-Array; `arr2str$(arr,offs)` / `arr2str(...)` liest ihn zurück
- Byte / Speicher: `u8(arr,offs[,val])`, `u16(...)`, `u32(...)`,
  `copy(src,soff,dst,doff,len)`, `free()`

(Dazu die NanoC-Computer-Funktionen in der Tabelle unten.)

## Eingebaute Funktionen

| Funktion | Bedeutung |
|---|---|
| `ta_send_cmd(nummer, topic, a, b, c)` | Kommando an eine Techage-Knotennummer → Status (0 = ok) |
| `ta_send_cmd_s(nummer, topic, "text")` | String-Kommando (z. B. Displays) → Status |
| `ta_signal(nummer, 0\|1)` | Signal (on/off) senden (Kurzform) |
| `ta_req_data(nummer, topic, a, b, c)` | Synchrone Anfrage → Zahl |
| `ta_req_data_s(nummer, topic, a, b, c)` | Synchrone Anfrage → String |
| `ta_recv()` | 1, wenn ein Kommando ankam (sonst 0) |
| `ta_port()`, `ta_topic()`, `ta_payload(i)` | das empfangene Kommando lesen |
| `ta_recv_sig()`, `ta_sig_port()`, `ta_sig_val()` | das empfangene Signal lesen |
| `key()` | nächste Taste als Zahl, oder -1 |
| `log("text")` | Log-/Debug-Meldung an den externen Debugger (VS-Code Debug Console); in-game ohne Wirkung |
| `sleep(ms)` | Programm für `ms` Millisekunden anhalten |
| `millis()` | Millisekunden seit Programmstart |

## Timing – wichtig

- **`sleep(ms)` ist in echten Millisekunden**, aber die *Aufwachzeit* hängt am
  Server-Takt: Luanti verarbeitet Node-Timer nur einmal pro Server-Step
  (Standard `dedicated_server_step` = **0,09 s**). Dazu kommt eine Untergrenze
  von 50 ms. Praktisch liegt die Auflösung also bei **ca. 0,1 Sekunden**.
- Das Programm wacht dadurch nie **zu früh** auf, kann aber bis zu einen
  Server-Step **zu spät** dran sein.
- **`millis()`** liefert echte Millisekunden und ist unabhängig vom Server-Step.
  Damit kann man Zeit messen, ohne anzuhalten.
- Die Ausführung läuft in **adaptiven Cycle-Budgets**: Der Controller führt pro
  Timer-Tick für ein kurzes Zeitfenster Instruktionen aus und gibt dann ab.
  Mehrere Controller laufen also kooperativ, nicht echt parallel.
- Für „alle Sekunde etwas tun" ist `sleep(1000)` in einer `while (1)`-Schleife
  der einfache Weg; für feinere Abläufe ohne Anhalten `millis()` verwenden.

## CPU-Budget (für Server-Betreiber)

NanoC erzwingt kein hartes Kommando-/RAM-Limit und bestraft den Owner nie.
Stattdessen misst jeder Controller, wie lange ein Tick wirklich dauert, und
passt sein VM-Instruktionsbudget an ein **Zeitziel** an (`nanoc_cpu_tick_ms`,
Standard 8 ms). Ein schnell fertiger Tick erhält beim nächsten Mal mehr, ein
langsamer weniger. Ein leerer Server bekommt so mehr Rechenzeit, ein
ausgelasteter weniger. Zusätzlich gilt: Eine techage-lastige Schleife
(`ta_req_data`/`ta_send_cmd`), die länger als das Budget braucht, **gibt einfach ab und
läuft im nächsten Tick weiter** – kein Fehler, kein Schaden. Wenn das Budget
drosselt, wird eine Info an das Debug-Terminal (Kanal 4) geschrieben, maximal
einmal pro Sekunde und Controller.

Einstellungen (minetest.conf / `settingtypes.txt`):

| Einstellung | Default | Bedeutung |
|---|---|---|
| `nanoc_cpu_tick_ms` | `8.0` | Ziel-CPU-Zeit pro Controller-Tick (ms) |
| `nanoc_cpu_tick_min_ms` | `1.0` | darunter nie |
| `nanoc_cpu_player_scale` | `true` | Budget durch Spieleranzahl teilen |
| `nanoc_vm_cycles_start` | `20000` | Start-Instruktionen pro Tick |
| `nanoc_vm_cycles_min` / `_max` | `500` / `100000` | Budget-Grenzen |

Für ein festes Budget `nanoc_cpu_player_scale = false` setzen, oder auf einem
stark belasteten Server `nanoc_cpu_tick_ms` senken (z. B. `3.0`).

## Techage / TechPack

Der Controller ist selbst ein Techage-Node (Nummer steht im Formular) und
adressiert andere Nodes **direkt über ihre Nummer** – kein I/O-Modul/Port-
Mapping nötig (NanoC hat 32-Bit-Variablen).

```
int32 kiste = 5                              // eine Techage-Knotennummer

int32 zustand = ta_req_data(kiste, 131, 0, 0, 0) // synchrone Anfrage -> Zahl
str8  name$   = ta_req_data_s(kiste, 128, 0, 0, 0)// synchrone Anfrage -> String

int32 sts = ta_send_cmd(kiste, 1, 1, 0, 0)       // Kommando (topic < 128) -> Status
ta_send_cmd_s(kiste, 67, "text")                 // String-Kommando (Displays)
```

`ta_req_data`/`ta_req_data_s` liefern die Antwort **direkt** (synchron, wie bei
Techage `basic_terminal`) – kein `sleep`+`ta_recv`-Polling für Anfragen nötig.
`ta_send_cmd`/`ta_send_cmd_s` liefern den **Status** (`0` = ok, wie
Beduino/NanoBasic).

Für asynchrone Antworten/Kommandos können diese weiterhin gelesen werden:
```
ta_recv()                          // 1, wenn Antwort/Kommando ankam
int32 num = ta_port()              // die betroffene Knotennummer
int32 topic = ta_topic()
int32 val = ta_payload(0)
```

Eingehende Kommandos anderer Nodes werden an das Programm zugestellt. Topic
`1` (run/stop) ist für den Controller reserviert.

Beispiel: `examples/techage_monitor.nanoc`.

## Externes Terminal / Debugger (Python-Client)

Ein Controller ist vom PC aus per TCP erreichbar:

1. **Server**: Bridge einschalten (`nanoc_bridge_enable = true` in
   `minetest.conf`). Sie lauscht standardmäßig auf `127.0.0.1:41100`
   (`nanoc_bridge_bind` / `nanoc_bridge_port`). Keine extra Abhängigkeit – die
   Sockets stecken in `nanoclib`.
2. **Im Spiel**: Controller öffnen und **Token** drücken – nur der Owner (oder
   ein Spieler mit `protection_bypass`) darf das; der Token erscheint in einem
   kleinen Fenster mit selektierbarem Textfeld (Text markieren, dann Ctrl+C).
   Nur an vertrauenswürdige Personen weitergeben (z. B. Moderator).
3. **Am PC**:
   ```bash
   python -m nanoc_client.cli --host 127.0.0.1 --port 41100 --token <TOKEN>
   ```
   Kommandos: `state`, `attach`, `bp <line>`, `step`, `cont`, `vars`, `key`,
   `help`.

Der Token ist der einzige Schlüssel: ohne ihn kann sich kein Client verbinden,
und kein anderer Spieler hängt sich an einen fremden Controller. Die Bridge
lauscht standardmäßig nur auf `127.0.0.1`. Limits (siehe `settingtypes.txt`):
`nanoc_bridge_max_clients`, `nanoc_bridge_handshake_timeout`,
`nanoc_bridge_cmd_rate`, `nanoc_bridge_idle_timeout`. Der Controller ist selbst
ein Techage-Node (Nummer steht im Formular): Techage kann ihn ein-/ausschalten
(`topic 1`) und seinen Zustand lesen (`topic 129`).

Ein komplettes Überwachungs-Beispiel: `examples/techage_monitor.nanoc`
(Eingangskisten leer, Ausgangskiste voll, Autocrafter blockiert/Störung).

### Testphase: Zugriff aus dem LAN

Um Terminal/Debugger von einem zweiten PC aus zu nutzen, während der
Spielserver z. B. auf `192.168.178.246` läuft, in `minetest.conf` setzen:

```
nanoc_bridge_enable = true
nanoc_bridge_bind = 0.0.0.0
nanoc_bridge_port = 41100
```

und dann mit `--host 192.168.178.246 --port 41100 --token <TOKEN>` verbinden.
Nur in einem **vertrauenswürdigen LAN** tun: `0.0.0.0` macht den Port für jedes
Gerät im Netz erreichbar, und die Verbindung ist **Klartext** (TLS gibt es noch
nicht). Der Token ist der einzige Schutz – und er erlaubt Programm-Upload/
-Download. Diesen Port **nicht** im Router freigeben und nicht auf einem
öffentlichen/VPS-Server betreiben – erst TLS ergänzen. Standard `127.0.0.1`
beibehalten, wenn der Client auf derselben Maschine wie der Server läuft.

Die Bridge niemals ohne Tunnel/TLS ins Internet exposen.

## Persistenz

Der Zustand (Variablen, Programmzähler, …) wird beim **sauberen Beenden** des
Servers gespeichert und beim nächsten Start wiederhergestellt. `Save+Compile`
startet ein geändertes Programm bewusst von vorn. Bei einem Server-Absturz geht
der Zwischenstand verloren.
