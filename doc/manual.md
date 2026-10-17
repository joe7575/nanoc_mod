# NanoC – Manual

NanoC is a small computer for Luanti/Minetest. Programs are written in a
C-like language and are executed on the server. It can control
Techage/TechPack machines directly (by node number).

## Components

| Node | Purpose |
|---|---|
| `nanoc:controller` | The computer (program editor + execution) |
| `nanoc:terminal` | Live display of the controller's terminal output |

Optionally, a `termlib:terminal1` (from the `termlib` mod) can serve as the
display **and** keyboard instead of `nanoc:terminal` (connect it as usual:
wield, left-click the controller, place, `@connect`). Typed commands arrive in
the program via `key()`. The controller's output is passed to termlib, so
control characters (`\a \b \t \n \r`) and escape sequences (`\27…`, e.g.
`\27\1` clear, `\27\2<row>`, `\27\3<font>`, `\27\4<cmd>\n`, `\27\5<1|2>`,
`\27\6<pos><row>`, `\27\7`) work directly – see
`examples/termlib_demo.nanoc`.

## Usage

1. Place a **controller** and right-click it.
2. Write the program in the upper field, press **Save+Compile**, then **Run**.
3. Place a **`nanoc:terminal`** nearby and right-click it – it shows the
   output continuously (no key press needed).

Buttons: `Save+Compile`, `Run`, `Stop`, `Reset`, `Clear`.

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
| `ta_send_cmd(number, topic, a, b, c)` | Command to a Techage node → status (0 = ok) |
| `ta_send_cmd_s(number, topic, "text")` | String command (e.g. displays) → status |
| `ta_signal(number, 0\|1)` | On/off signal (shortcut) |
| `ta_req_data(number, topic, a, b, c)` | Synchronous request → numeric result |
| `ta_req_data_s(number, topic, a, b, c)` | Synchronous request → string result |
| `ta_recv()` | 1 if a command arrived (else 0) |
| `ta_port()`, `ta_topic()`, `ta_payload(i)` | read the received command |
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

## CPU budget (server owners)

NanoC does not enforce a hard command/RAM limit and never penalises the owner.
Instead each controller measures how long a tick really takes and adapts its VM
instruction budget to stay near a **time target** (`nanoc_cpu_tick_ms`, default
8 ms). A tick that finishes early gets a larger budget next time; a slow tick
gets a smaller one. An idle server thus gives more compute, a busy one less.
On top of that, a techage-heavy loop (`ta_req_data`/`ta_send_cmd`) that runs longer than
the budget simply **yields and continues in the next tick** - no error, no
damage. When the budget throttles a program, an info message is written to the
debug terminal (channel 4), at most once per second per controller.

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

## Techage / TechPack

The controller is itself a Techage node (its number is shown in the formspec)
and addresses other nodes by their **number directly** — no I/O module/port
mapping is needed (NanoC has 32-bit variables).

```
int32 chest = 5                             // a techage node number

int32 state = ta_req_data(chest, 131, 0, 0, 0)   // synchronous request -> number
str8  name$ = ta_req_data_s(chest, 128, 0, 0, 0) // synchronous request -> string

int32 sts = ta_send_cmd(chest, 1, 1, 0, 0)       // command (topic < 128) -> status
ta_send_cmd_s(chest, 67, "text")                 // string command (displays)
```

`ta_req_data`/`ta_req_data_s` return the answer directly (synchronous, like
techage's `basic_terminal`), so no `sleep`+`ta_recv` polling is needed for
requests. `ta_send_cmd`/`ta_send_cmd_s` return the status (`0` = ok, like
Beduino/NanoBasic).

For asynchronous replies/commands you may still read them via:
```
ta_recv()                          // 1 if a reply/command arrived
int32 num = ta_port()              // the node number involved
int32 topic = ta_topic()
int32 val = ta_payload(0)
```

Incoming commands from other nodes are delivered to the program. Topic `1`
(run/stop) is reserved for the controller itself.

See `examples/techage_monitor.nanoc`.

## External terminal / debugger (Python client)

A controller can be reached from a PC via TCP:

1. **Server**: enable the bridge (`nanoc_bridge_enable = true` in
   `minetest.conf`). It binds to `127.0.0.1:41100` by default
   (`nanoc_bridge_bind` / `nanoc_bridge_port`). No extra dependency – the
   sockets are built into `nanoclib`.
2. **In-game**: open the controller and press **Token** — only the owner (or a
   player with `protection_bypass`) can do this; the token appears in a small
   window with a selectable text field (select the text, then Ctrl+C). Share it
   only with people you trust (e.g. a moderator).
3. **On the PC**:
   ```bash
   python -m nanoc_client.cli --host 127.0.0.1 --port 41100 --token <TOKEN>
   ```
   Commands: `state`, `attach`, `bp <line>`, `step`, `cont`, `vars`, `key`,
   `help`.

The token is the only key: without it a client cannot connect, and different
players cannot attach to another player's controller. The bridge binds to
`127.0.0.1` by default. Limits (see `settingtypes.txt`): `nanoc_bridge_max_clients`,
`nanoc_bridge_handshake_timeout`, `nanoc_bridge_cmd_rate`, `nanoc_bridge_idle_timeout`.
The controller itself is a techage node (its number is shown in the formspec):
techage can switch it on/off (`topic 1`) and read its state (`topic 129`).

See `examples/techage_monitor.nanoc` for a full monitoring example (input
chests empty, output chest full, autocrafter blocked/fault).

### Test phase: access from the LAN

To use the terminal/debugger from a second PC while the game server runs on
e.g. `192.168.178.246`, set in `minetest.conf`:

```
nanoc_bridge_enable = true
nanoc_bridge_bind = 0.0.0.0
nanoc_bridge_port = 41100
```

then connect with `--host 192.168.178.246 --port 41100 --token <TOKEN>`. Only do
this in a **trusted LAN**: `0.0.0.0` makes the port reachable by every device in
your network, and the link is **plaintext** (TLS is not implemented yet). The
token is the only protection, and it can upload/download programs. Do **not**
forward this port on the router and do not run it on a public/VPS server — add
TLS first. Keep the default `127.0.0.1` when the client runs on the same machine
as the server.

Never expose the bridge to the internet without a tunnel/TLS.

## Persistence

The state (variables, program counter, …) is saved on a **clean server
shutdown** and restored on the next start. `Save+Compile` deliberately starts a
changed program from the beginning. After a server crash the intermediate state
is lost.
