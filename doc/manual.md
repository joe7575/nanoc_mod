# NanoC – Manual

NanoC is a small computer for Luanti/Minetest. Programs are written in a
C-like language and are executed on the server. Through an I/O module it can
control Techage/TechPack machines.

## Components

| Node | Purpose |
|---|---|
| `nanoc:controller` | The computer (program editor + execution) |
| `nanoc:terminal` | Live display of the controller's terminal output |
| `nanoc:io_module` | Bridge to Techage/TechPack machines (ports ↔ node numbers) |

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
| `ta_send(port, topic, a, b, c)` | Send a command to Techage (`topic < 128`) |
| `ta_send_s(port, topic, "text")` | Send a string command (e.g. for displays) |
| `ta_signal(port, 0\|1)` | Send an on/off signal |
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

1. Place a `nanoc:io_module` within 3 blocks of the controller.
2. Right-click the I/O module: enter the base port and the Techage numbers,
   then save.
3. On the controller press **Stop**, then **Run** – this registers the port
   mapping.

Each port stands for a Techage/TechPack node number. `ta_send` with
`topic < 128` sends a command, `topic >= 128` requests data (the reply lands in
the receive queue and can be fetched with `ta_recv()`).

## External terminal / debugger (Python client)

A controller can be reached from a PC via TCP:

1. **Server**: enable the bridge (`nanoc_bridge_enable = true` in
   `minetest.conf`). It binds to `127.0.0.1:41100` by default
   (`nanoc_bridge_bind` / `nanoc_bridge_port`). No extra dependency – the
   sockets are built into `nanoclib`.
2. **In-game**: open the controller; the "External token" is shown. The
   `New` button regenerates it.
3. **On the PC**:
   ```bash
   python -m nanoc_client.cli --host 127.0.0.1 --port 41100 --token <TOKEN>
   ```
   Commands: `state`, `attach`, `bp <line>`, `step`, `cont`, `vars`, `key`,
   `help`.

The bridge only listens on localhost by default. Never expose it to the
internet without a tunnel/TLS – the token is the only protection.

## Persistence

The state (variables, program counter, …) is saved on a **clean server
shutdown** and restored on the next start. `Save+Compile` deliberately starts a
changed program from the beginning. After a server crash the intermediate state
is lost.
