# NanoC – Manual

NanoC is a small computer for Luanti/Minetest. Programs are written in a
C-like language and are executed on the server. It can control
Techage/TechPack machines directly (by node number).

## Components

| Node | Purpose |
|---|---|
| `nanoc:controller` | The computer (VM execution + log panel) |

The terminal is a **`termlib:terminal1`** (from the required `termlib` mod):
it serves as the display **and** keyboard. Connect it as usual: wield the
terminal, left-click the controller, place it, open it and type `@connect`.
Typed commands arrive in the program via `key()`. The controller's output is
passed to termlib, so control characters (`\a \b \t \n \r`) and escape
sequences (`\27…`, e.g. `\27\1` clear, `\27\2<row>`, `\27\3<font>`,
`\27\4<cmd>\n`, `\27\5<1|2>`, `\27\6<pos><row>`, `\27\7`) work directly – see
`examples/termlib_demo.nanoc`.

## Usage

1. Place a **controller** and a **`termlib:terminal1`**; connect the terminal
   (wield, left-click the controller, place, open, `@connect`).
2. Code is edited/debugged externally (VS Code debugger or `nanoc-tui`) and
   uploaded from there; the terminal shows the `printf` output and accepts
   keyboard input.
3. Right-click the controller to open its **log** panel. It shows only the
   `log()` messages; buttons: **Run**, **Stop**, **Reset**, **Clear** (log),
   **Token**.
4. Give the controller a **name** with the Techage Info Tool: sneak + place on
   the controller. The name and node number appear in the infotext
   (`NanoC Controller "<name>" <number>`), which helps match controllers to
   VS Code projects.

## Language (examples)

```
int32 count = 0

while (1) {
    count = count + 1
    printf("count=%d\n", count)
    sleep(1000)
}
```

Supported are, among others: `int32`, `str8`, `while`, `if/else`, functions
(`func`), arrays, and `printf` (formats `%d`, `%u`, `%h`, `%s`, `%%`).

Functions use typed parameters and an optional return type **before** the name
(omitted = `void`):

```
func int32 add(int32 a, int32 b) {
    return a + b
}

int32 x = add(3, 4)
```

Full language reference:
<https://github.com/joe7575/nanoc/blob/main/docs/nanoc_reference.md>

### Types, variables, constants

`int32` (32-bit integer), `str8` (string; the name ends with `$`), arrays
`int32 buf[10]`. `const NAME = value` defines a compile-time constant.
Variables are auto-created on assignment; statements end at the newline or `;`.

```
int32 count = 0
str8 name$ = "Hello"
int32 buf[10]
const MAX = 100
count = count + 1
buf[0] = count
```

Operators: `+ - * / % mod`, `& | ^ << >>`, `== != < <= > >=`, `and or not`,
`++ --`. Strings can be concatenated with `+` and compared with `== < >`.

### Strings and escape sequences

String literals support escape sequences (decoded at compile time):

| Escape | Meaning |
| ------ | ------- |
| `\n` | newline |
| `\t` | tab |
| `\r` | carriage return |
| `\a` | BEL (0x07) |
| `\b` | backspace |
| `\f` | form feed |
| `\v` | vertical tab |
| `\e` | ESC (0x1B) |
| `\\` | literal backslash |
| `\"` `\'` | quote |
| `\xHH` | hex byte, e.g. `\x1b` |
| `\ddd` | decimal byte, e.g. `\27` |

There are **no** C-style octal escapes: `\ddd` is decimal, like in Lua.

### Control flow

```
if (x > 0) { ... } else { ... }
while (i < 10) { i++ }
for i = 1 to 10 { printf("%d\n", i) }
for i = 10 to 0 step -1 { ... }
break            // leave the innermost for/while loop (C-style)
breakpoint()     // debugger breakpoint (the former 'break')
dispatch(expr) { func0, func1, func2 }   // call by 0-based index
end      // terminate the program
reti     // return from an interrupt handler
```

### Functions and arrays

Parameters are typed; the optional return type comes **before** the name
(omitted = `void`). Array parameters are passed by reference with `int32[]`.

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

### Standard functions

- numeric: `rnd(n)`, `abs(n)`
- strings: `len(s$)`, `left$(s$,n)`, `right$(s$,n)`, `mid$(s$,start,len)`,
  `str$(n)`, `hex$(n)`, `instr(start,s$,find$)`, `string$(n,char$)`
  (the trailing `$` is optional: `str8 name`, `left(...)`, `hex(...)`, …)
- string <-> array: `str2arr(arr,offs,"text")` copies a string incl. `\0` into
  a byte array; `arr2str$(arr,offs)` / `arr2str(...)` reads it back
- byte / memory: `u8(arr,offs[,val])`, `u16(...)`, `u32(...)`,
  `copy(src,soff,dst,doff,len)`, `free()`

(Plus the NanoC-computer functions in the table below.)

## Built-in functions

| Function | Meaning |
|---|---|
| `ta_send_cmd(number, topic, payload)` | Command → status (0 = ok); payload = `int32[]` or string (topic ≥ 64) |
| `ta_signal(number, 0\|1)` | On/off signal (shortcut) |
| `ta_req_data(number, topic, payload)` | Request → number; payload = `int32[]` or string (topic ≥ 192) |
| `ta_req_data_s(number, topic, payload)` | Request → string |
| `ta_recv(cmd[])` | read a command into `cmd` = `[number, topic, p0, p1, …]`; 1 if one arrived |
| `ta_recv_sig()`, `ta_sig_port()`, `ta_sig_val()` | read the received signal |
| `key()` | next key as a number, or -1 |
| `log("text")` | debug/log message to the external debugger (VS Code Debug Console); no-op in-game |
| `sleep(ms)` | pause the program for `ms` milliseconds |
| `millis()` | milliseconds since program start |

## Timing – important

- **`sleep(ms)` is in real milliseconds**, but the *wake-up time* depends on
  the server tick: Luanti processes node timers only once per server step
  (default `dedicated_server_step` = **0.09 s**). There is also a 50 ms floor.
  In practice the resolution is therefore **about 0.1 seconds**.
- The program never wakes up **too early**, but may be up to one server step
  **late**.
- **`millis()`** returns real milliseconds and is independent of the server
  step. It can be used to measure time without pausing.
- Execution runs in **adaptive cycle budgets**: each timer tick the controller
  executes VM instructions for a short time slice and then yields, so several
  controllers run cooperatively, not truly in parallel.
- To "do something every second", `sleep(1000)` inside a `while (1)` loop is
  the simple way; for finer behaviour without pausing, use `millis()`.

## Techage / TechPack

The controller is itself a Techage node (its number is shown in the formspec)
and addresses other nodes by their **number directly** — no I/O module/port
mapping is needed (NanoC has 32-bit variables).

```
int32 chest = 5                             // a techage node number

int32 p[0]                                  // payload array (1 element)
p[0] = 1

int32 state = ta_req_data(chest, 131, p)    // request -> number
str8  name$ = ta_req_data_s(chest, 128, p)  // request -> string
int32 cnt   = ta_req_data(chest, 192, "techage:lighter") // string payload -> number

int32 sts = ta_send_cmd(chest, 1, p)        // command -> status (p[0] = 1)
ta_send_cmd(chest, 67, "text")              // string payload (topic >= 64)
```

The payload is an `int32[]` array for numeric topics, or a string for the
Beduino string-topic ranges (≥ 192 for requests, ≥ 64 for commands).
`ta_req_data`/`ta_req_data_s` return the answer directly (synchronous, like
techage's `basic_terminal`), so no `sleep`+`ta_recv` polling is needed for
requests. `ta_send_cmd` returns the status (`0` = ok).

Incoming commands are read into an array:
```
int32 cmd[4]
if (ta_recv(cmd) == 1) {
    int32 num = cmd[0]      // sending node number
    int32 topic = cmd[1]
    int32 p0 = cmd[2]       // payload...
}
```

Incoming commands from other nodes are delivered to the program. Topic `1`
(run/stop) is reserved for the controller itself.

See `examples/techage_monitor.nanoc`.

Topic reference (BEP 005):
<https://github.com/joe7575/beduino/blob/main/BEPs/bep-005_ta_cmnd.md>

## External terminal / debugger (Python client)

A controller can be reached from a PC via TCP. The server admin must enable the
bridge (see the mod's `README.md`).

1. **In-game**: open the controller and press **Token** — only the owner (or a
   player with `protection_bypass`) can do this; the token appears in a small
   window with a selectable text field (select the text, then Ctrl+C). Share it
   only with people you trust (e.g. a moderator).
2. **On the PC**:
   ```bash
   python -m nanoc_client.cli --host <server> --port 41100 --token <TOKEN>
   # with TLS: add --tls --cafile cert.pem (or --tls-fingerprint <sha256>)
   ```
   Commands: `state`, `attach`, `bp <line>`, `step`, `cont`, `vars`, `key`,
   `help`.

The token is the only key: without it a client cannot connect, and different
players cannot attach to another player's controller. The controller itself is
a techage node (its number is shown in the formspec): techage can switch it
on/off (`topic 1`) and read its state (`topic 129`).

See `examples/techage_monitor.nanoc` for a full monitoring example (input
chests empty, output chest full, autocrafter blocked/fault).

### Connection problems (external terminal/debugger)

- Copy the token with the **Token** button in the controller form and enter it
  exactly in the client (`--token ...`).
- If the client reports "connection refused", the bridge is not reachable from
  your network. Ask the server admin (admin setup and troubleshooting: see the
  mod's `README.md`).
- The bridge runs on the **server**, not in your game client.
- The controller must be **loaded**: stay near it (or have another player /
  forceload keep the area loaded). If the area is unloaded (you are far away or
  logged out), the client reports `NOT_LOADED`.

## Persistence

The state (variables, program counter, …) is saved on a **clean server
shutdown** and restored on the next start. Uploading a changed program
(external client) starts it from the beginning. After a server crash the
intermediate state is lost.
