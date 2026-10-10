# nanoc_mod

Luanti/Minetest mod for the **NanoC** computer: a small C-like language and
virtual machine with a source-level debugger.

The VM itself lives in the external Lua C module `nanoclib` from the repo
[`nanoc_lib`](../nanoc_lib); this mod is pure Lua and only wires the VM to
nodes, formspecs and (optionally) techage/tubelib2 I/O.

## Dependencies

- `nanoclib` via LuaRocks:
  ```bash
  luarocks make --lua-version 5.1   # in nanoc_lib
  ```
- `secure.trusted_mods` must contain `nanoc`.
- Optional: `techage` or `tubelib2` for machine I/O.

## Player manual

See [`doc/manual_DE.md`](doc/manual_DE.md) (German) or
[`doc/manual_EN.md`](doc/manual_EN.md) (English) for usage, the language,
the built-in functions and the timing behaviour of `sleep()`/`millis()`.

## Install (development)

The authoritative git repo lives outside the Luanti tree. Symlink it into the
mods directory:

```bash
ln -s ~/Projekte/nanoc_mod ~/luanti-5.11.0/mods/nanoc
```

## Contract

The mod validates `nanoclib.protocol()` and `nanoclib.version()` at start-up.
See [`doc/protocol.md`](../nanoc_lib/doc/protocol.md) in `nanoc_lib`.

## Roadmap (phase 1)

1. Controller node with a VM instance per node.
2. In-game terminal (text / `screen[]`) driven by `nanoclib.tty_*`.
3. Techage/tubelib2 adapter reusing the beduino/yauc2 "Beduino API"
   (`on_beduino_receive_cmnd`, `beduino_send_cmnd`, `beduino_request_data`).
4. Optional external debugger/terminal via the `nanoc_client` (TCP/TLS).

## License

AGPLv3 or later. See [`LICENSE.txt`](LICENSE.txt).
