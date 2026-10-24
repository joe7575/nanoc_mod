# NanoC – Handbuch

NanoC ist ein kleiner Computer für Luanti/Minetest. Man schreibt Programme in
einer C-ähnlichen Sprache, die auf dem Server ausgeführt werden. Damit lassen
sich Techage-/TechPack-Maschinen direkt (per Knotennummer) steuern.

## Aufbau

| Node | Zweck |
|---|---|
| `nanoc:controller` | Der Computer (VM-Ausführung + Log-Panel) |

Das Terminal ist ein **`termlib:terminal1`** (aus der benötigten `termlib`-Mod):
es dient als Anzeige **und** Tastatur. Anschließen wie gewohnt: Terminal in die
Hand nehmen, Controller linksklicken, platzieren, öffnen, `@connect`. Getippte
Kommandos kommen im Programm über `key()` an. Die Controller-Ausgabe geht an
termlib, daher wirken Steuerzeichen (`\a \b \t \n \r`) und Escape-Sequenzen
(`\27…`, z. B. `\27\1` Clear, `\27\2<row>`, `\27\3<font>`, `\27\4<cmd>\n`,
`\27\5<1|2>`, `\27\6<pos><row>`, `\27\7`) direkt – siehe
`examples/termlib_demo.nanoc`.

## Bedienung

1. **Controller** und ein **`termlib:terminal1`** platzieren; Terminal
   verbinden (in die Hand nehmen, Controller linksklicken, platzieren, öffnen,
   `@connect`).
2. Code wird **extern** bearbeitet/debuggt (VS-Code-Debugger oder `nanoc-tui`)
   und von dort hochgeladen; das Terminal zeigt die `printf`-Ausgabe und nimmt
   Tastatureingaben an.
3. Rechtsklick auf den Controller öffnet das **Log-Panel**. Es zeigt nur die
   `log()`-Meldungen; Buttons: **Run**, **Stop**, **Reset**, **Clear** (Log),
   **Token**.
4. Dem Controller einen **Namen** geben über den Techage Info Tool
   (Schraubenschlüssel): schleichen + platzieren auf dem Controller. Name und
   Knotennummer stehen im Infotext (`NanoC Controller "<Name>" <Nummer>`) – so
   lassen sich Controller den VS-Code-Projekten zuordnen.

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
| `ta_send_cmd(nummer, topic, payload)` | Kommando → Status (0 = ok); payload = `int32[]` oder String (topic ≥ 64) |
| `ta_signal(nummer, 0\|1)` | Signal (on/off) senden (Kurzform) |
| `ta_req_data(nummer, topic, payload)` | Anfrage → Zahl; payload = `int32[]` oder String (topic ≥ 192) |
| `ta_req_data_s(nummer, topic, payload)` | Anfrage → String |
| `ta_recv(cmd[])` | Kommando in `cmd` = `[nummer, topic, p0, p1, …]` lesen; 1 wenn eines ankam |
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

## Techage / TechPack

Der Controller ist selbst ein Techage-Node (Nummer steht im Formular) und
adressiert andere Nodes **direkt über ihre Nummer** – kein I/O-Modul/Port-
Mapping nötig (NanoC hat 32-Bit-Variablen).

```
int32 kiste = 5                              // eine Techage-Knotennummer

int32 p[0]                                   // Payload-Array (1 Element)
p[0] = 1

int32 zustand = ta_req_data(kiste, 131, p)   // Anfrage -> Zahl
str8  name$   = ta_req_data_s(kiste, 128, p) // Anfrage -> String
int32 anzahl  = ta_req_data(kiste, 192, "techage:lighter") // String-Payload -> Zahl

int32 sts = ta_send_cmd(kiste, 1, p)         // Kommando -> Status (p[0] = 1)
ta_send_cmd(kiste, 67, "text")               // String-Payload (topic >= 64)
```

Der Payload ist ein `int32[]`-Array für numerische Topics oder ein String für
die Beduino-String-Bereiche (≥ 192 bei Anfragen, ≥ 64 bei Kommandos).
`ta_req_data`/`ta_req_data_s` liefern die Antwort **direkt** (synchron, wie bei
Techage `basic_terminal`) – kein `sleep`+`ta_recv`-Polling für Anfragen nötig.
`ta_send_cmd` liefert den **Status** (`0` = ok).

Eingehende Kommandos werden in ein Array gelesen:
```
int32 cmd[4]
if (ta_recv(cmd) == 1) {
    int32 num = cmd[0]      // sendende Knotennummer
    int32 topic = cmd[1]
    int32 p0 = cmd[2]       // Payload...
}
```

Eingehende Kommandos anderer Nodes werden an das Programm zugestellt. Topic
`1` (run/stop) ist für den Controller reserviert.

Beispiel: `examples/techage_monitor.nanoc`.

Topic-Referenz (BEP 005):
<https://github.com/joe7575/beduino/blob/main/BEPs/bep-005_ta_cmnd.md>

## Externes Terminal / Debugger (Python-Client)

Ein Controller ist vom PC aus per TCP erreichbar. Der Server-Admin muss die
Bridge einschalten (siehe `README.md` der Mod).

1. **Im Spiel**: Controller öffnen und **Token** drücken – nur der Owner (oder
   ein Spieler mit `protection_bypass`) darf das; der Token erscheint in einem
   kleinen Fenster mit selektierbarem Textfeld (Text markieren, dann Ctrl+C).
   Nur an vertrauenswürdige Personen weitergeben (z. B. Moderator).
2. **Am PC**:
   ```bash
   python -m nanoc_client.cli --host <server> --port 41100 --token <TOKEN>
   # mit TLS: --tls --cafile cert.pem (oder --tls-fingerprint <sha256>)
   ```
   Kommandos: `state`, `attach`, `bp <line>`, `step`, `cont`, `vars`, `key`,
   `help`.

Der Token ist der einzige Schlüssel: ohne ihn kann sich kein Client verbinden,
und kein anderer Spieler hängt sich an einen fremden Controller. Der Controller
ist selbst ein Techage-Node (Nummer steht im Formular): Techage kann ihn
ein-/ausschalten (`topic 1`) und seinen Zustand lesen (`topic 129`).

Ein komplettes Überwachungs-Beispiel: `examples/techage_monitor.nanoc`
(Eingangskisten leer, Ausgangskiste voll, Autocrafter blockiert/Störung).

### Verbindungsprobleme (externes Terminal/Debugger)

- Token über den **Token**-Button im Controller-Formular kopieren und exakt im
  Client eintragen (`--token ...`).
- Meldet der Client „connection refused", ist die Bridge aus deinem Netz nicht
  erreichbar. Frage den Server-Admin (Admin-Setup und Fehlerdiagnose: siehe
  `README.md` der Mod).
- Die Bridge läuft auf dem **Server**, nicht im Spiel-Client.
- Der Controller muss **geladen** sein: bleib in seiner Nähe (oder ein anderer
  Spieler / Forceload hält das Gebiet geladen). Ist das Gebiet entladen (du bist
  weit weg oder ausgeloggt), meldet der Client `NOT_LOADED`.

## Persistenz

Der Zustand (Variablen, Programmzähler, …) wird beim **sauberen Beenden** des
Servers gespeichert und beim nächsten Start wiederhergestellt. Ein Upload eines
geänderten Programms (externer Client) startet es bewusst von vorn. Bei einem
Server-Absturz geht der Zwischenstand verloren.
