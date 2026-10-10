# NanoC – Handbuch

NanoC ist ein kleiner Computer für Luanti/Minetest. Man schreibt Programme in
einer C-ähnlichen Sprache, die auf dem Server ausgeführt werden. Über ein
I/O-Modul lassen sich damit Techage-/TechPack-Maschinen steuern.

## Aufbau

| Node | Zweck |
|---|---|
| `nanoc:controller` | Der Computer (Programm-Editor + Ausführung) |
| `nanoc:terminal` | Live-Anzeige der Terminal-Ausgabe des Controllers |
| `nanoc:io_module` | Brücke zu Techage-/TechPack-Maschinen (Ports ↔ Node-Nummern) |

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
(`func`), Arrays, `printf` (Formate `%d`, `%u`, `%X`, `%s`, `%%`).

Funktionen haben **typisierte Parameter** und einen optionalen Rückgabetyp
**vor** dem Namen (weggelassen = `void`):

```
func int32 add(int32 a, int32 b) {
    return a + b
}

int32 x = add(3, 4)
```

## Eingebaute Funktionen

| Funktion | Bedeutung |
|---|---|
| `ta_send(port, topic, a, b, c)` | Kommando an Techage senden (`topic < 128`) |
| `ta_send_s(port, topic, "text")` | String-Kommando (z. B. für Displays) |
| `ta_signal(port, 0\|1)` | Signal (on/off) senden |
| `ta_recv()` | 1, wenn ein Kommando ankam (sonst 0) |
| `ta_port()`, `ta_topic()`, `ta_payload(i)` | das empfangene Kommando lesen |
| `ta_recv_sig()`, `ta_sig_port()`, `ta_sig_val()` | das empfangene Signal lesen |
| `key()` | nächste Taste als Zahl, oder -1 |
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
- Die Ausführung läuft in **Cycle-Budgets**: Der Controller führt pro Timer-Tick
  bis zu 50.000 Instruktionen aus und gibt dann ab. Mehrere Controller laufen
  also nacheinander (kooperativ), nicht echt parallel.
- Für „alle Sekunde etwas tun" ist `sleep(1000)` in einer `while (1)`-Schleife
  der einfache Weg; für feinere Abläufe ohne Anhalten `millis()` verwenden.

## Techage / TechPack

1. `nanoc:io_module` im Umkreis von 3 Blöcken um den Controller platzieren.
2. I/O-Modul rechtsklicken: Portbasis + Techage-Nummern eintragen, speichern.
3. Am Controller **Stop**, dann **Run** – damit wird die Port-Zuordnung
   registriert.

Jeder Port steht für eine Techage-/TechPack-Node-Nummer. `ta_send` mit
`topic < 128` schickt ein Kommando, `topic >= 128` fragt Daten an (Antwort
landet in der Empfangs-Queue, abholbar mit `ta_recv()`).

## Externes Terminal / Debugger (Python-Client)

Ein Controller ist vom PC aus per TCP erreichbar:

1. **Server**: Bridge einschalten (`nanoc_bridge_enable = true` in
   `minetest.conf`). Sie lauscht standardmäßig auf `127.0.0.1:41100`
   (`nanoc_bridge_bind` / `nanoc_bridge_port`). Keine extra Abhängigkeit – die
   Sockets stecken in `nanoclib`.
2. **Im Spiel**: Controller öffnen; unten steht der „External token". Der
   Button `New` erzeugt einen neuen.
3. **Am PC**:
   ```bash
   python -m nanoc_client.cli --host 127.0.0.1 --port 41100 --token <TOKEN>
   ```
   Kommandos: `state`, `attach`, `bp <line>`, `step`, `cont`, `vars`, `key`,
   `help`.

Die Bridge lauscht standardmäßig nur auf localhost. Nie ohne Tunnel/TLS ins
Internet öffnen – der Token ist der einzige Schutz.

## Persistenz

Der Zustand (Variablen, Programmzähler, …) wird beim **sauberen Beenden** des
Servers gespeichert und beim nächsten Start wiederhergestellt. `Save+Compile`
startet ein geändertes Programm bewusst von vorn. Bei einem Server-Absturz geht
der Zwischenstand verloren.
