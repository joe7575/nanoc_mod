# NanoC examples

Small, self-contained NanoC programs. Node numbers in the examples are
placeholders or an example plant layout — replace them with the numbers of your
own blocks. Techage blocks show their number in the infotext when you look at
them, or use `nanoc scan`.

Upload an example with the external NanoC client (VS Code upload/F5, or
`nanoc exec`). The in-game controller form provides only Run/Stop/Reset; code
and terminal are external:

```bash
nanoc exec world_data.nanoc --token <TOKEN>
```

See the [NanoC manual](https://github.com/joe7575/nanoc_mod/blob/main/doc/manual.md),
the MCP resources `nanoc://manual`, `nanoc://cookbook` and `nanoc://topics`,
and the MCP overview `nanoc://examples`.

| Example | What it demonstrates | Needs |
|---|---|---|
| [`blinds_demo.nanoc`](blinds_demo.nanoc) | One window with two TA3 door controllers: light-dependent opening/closing, `hold()`/`release()` wave, display output, startup state repair | 2× `techage:ta3_doorcontroller2`, light detector, TA4 display |
| [`world_data.nanoc`](world_data.nanoc) | Server data on a TA4 Display II XXL: `time()`, `daytime()`, `daytime$()`, `millis()`, change detection and `pad2()` | TA4 Display II XXL, NanoC controller |
| [`signal_tower.nanoc`](signal_tower.nanoc) | Cycle a TA4 signal tower through green/amber/red and show the colour on a fixed terminal row | TA4 signal tower, termlib terminal |
| [`techage_monitor.nanoc`](techage_monitor.nanoc) | Monitor input/output chests and an autocrafter; raise terminal alarms for empty, full, blocked and fault states | 2 input chests, output chest, pushers, TA4 autocrafter, terminal |
| [`factory_control.nanoc`](factory_control.nanoc) | Menu-driven TA4 factory: recipe block, ingredient checks, pushers, autocrafter, intermediates and a status tower | TA4 factory layout, recipe block, terminal |
| [`fab_control.nanoc`](fab_control.nanoc) | Menu-driven electronic fab with direct fab recipe topics, ingredient/sub-craft checks and output/return pushers | TA4 electronic fab, chests, pushers, terminal |
| [`oven_control.nanoc`](oven_control.nanoc) | Menu-driven furnace with a TA4 recipe adapter, ingredient checks, output and return pushers | TA4 furnace, recipe adapter, chests, pushers, terminal |
| [`termlib_demo.nanoc`](termlib_demo.nanoc) | termlib terminal features: colours, escape sequences, cursor rows, keyboard input and function keys | NanoC controller, termlib terminal |
| [`test.nanoc`](test.nanoc) | Minimal counter and `printf` demo | NanoC controller, terminal |

The examples are intentionally small. They show the pattern, not a complete
production control system; adapt node numbers, thresholds, item names and
timings to your plant.
