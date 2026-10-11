# NanoC – Manual

NanoC is a small computer for Luanti/Minetest. Programs are written in a
C-like language and are executed on the server. It can control
Techage/TechPack machines directly (by node number).

## Components

| Node | Purpose |
|---|---|
| `nanoc:controller` | The computer (program editor + execution) |
| `nanoc:terminal` | Live display of the controller's terminal output |

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

### Control flow

```
if (x > 0) { ... } else { ... }
while (i < 10) { i++ }
for i = 1 to 10 { printf("%d\n", i) }
for i = 10 to 0 step -1 { ... }
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
- byte / memory: `u8(arr,offs[,val])`, `u16(...)`, `u32(...)`,
  `copy(src,soff,dst,doff,len)`, `free()`

(Plus the NanoC-computer functions in the table below.)

## Built-in functions

| Function | Meaning |
|---|---|
| `ta_send(number, topic, a, b, c)` | Command/request to a Techage node number |
| `ta_send_s(number, topic, "text")` | String command (e.g. for displays) |
| `ta_signal(number, 0\|1)` | On/off signal |
| `ta_recv()` | 1 if a command arrived (else 0) |
| `ta_port()`, `ta_topic()`, `ta_payload(i)` | read the received command |
| `ta_recv_sig()`, `ta_sig_port()`, `ta_sig_val()` | read the received signal |
| `key()` | next key as a number, or -1 |
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
- Execution runs in **cycle budgets**: each timer tick the controller executes
  up to 50,000 instructions and then yields. Several controllers therefore run
  one after another (cooperatively), not truly in parallel.
- To "do something every second", `sleep(1000)` inside a `while (1)` loop is
  the simple way; for finer behaviour without pausing, use `millis()`.

## Techage / TechPack

The controller is itself a Techage node (its number is shown in the formspec)
and addresses other nodes by their **number directly** — no I/O module/port
mapping is needed (NanoC has 32-bit variables).

```
int32 chest = 5                    // a techage node number

ta_send(chest, 131, 0, 0, 0)       // request (topic >= 128)
ta_send(chest, 1, 1, 0, 0)         // command (topic < 128)
ta_send_s(chest, 67, "text")       // string command (displays)

ta_recv()                          // 1 if a reply/command arrived
int32 num = ta_port()              // the node number involved
int32 topic = ta_topic()
int32 val = ta_payload(0)
```

`ta_port()` returns the node number you asked (or the sender's number for an
incoming command). Incoming commands from other nodes are delivered to the
program. Topic `1` (run/stop) is reserved for the controller itself.

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

The bridge only listens on localhost by default. Never expose it to the
internet without a tunnel/TLS – the token is the only protection.

## Persistence

The state (variables, program counter, …) is saved on a **clean server
shutdown** and restored on the next start. `Save+Compile` deliberately starts a
changed program from the beginning. After a server crash the intermediate state
is lost.
