# nanoc_mod/src — planned modules

Pure-Lua glue only; the VM is in `nanoclib`.

```
src/
  controller.lua        -- CPU node, one VM per node, on_timer cycle budget
  terminal.lua          -- in-game screen/terminal for nanoclib.tty_*
  files.lua             -- program storage (node meta / mod_storage)
  tech/
    wrapper.lua         -- techage OR tubelib2 shim (model: beduino/yauc2)
    io_module.lua       -- port <-> techage node number bridge
    commands.lua        -- command name registry
```

The tech layer is an adaptation of the proven beduino / yauc2 "Beduino API"
pattern and stays synchronous (cycle budget per server step), not threaded.
