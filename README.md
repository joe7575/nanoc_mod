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
