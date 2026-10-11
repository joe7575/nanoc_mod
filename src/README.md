# nanoc_mod/src — modules

Pure-Lua glue only; the VM is in `nanoclib`.

```
src/
  controller.lua        -- CPU node, one VM per node, on_timer cycle budget,
                           techage interface (direct node numbers)
  terminal.lua          -- live in-game terminal for the controller output
  capabilities.lua      -- Beduino topic catalog for TA4/TA5 nodes
  inspect.lua           -- nanoc.inspect / SCAN (TA4 graph for AI clients)
  bridge.lua            -- external TCP bridge (protocol v1) + focus + limits
  tech/
    wrapper.lua         -- techage OR tubelib2 shim (model: beduino/yauc2)
```

The tech layer is an adaptation of the beduino / yauc2 "Beduino API" pattern
and stays synchronous (cycle budget per server step), not threaded.

NanoC programs address techage **node numbers directly** (32-bit variables);
an I/O-module/port bridge (as in beduino/vm16/yauc2) is not required.
