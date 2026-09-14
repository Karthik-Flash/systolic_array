# systolic_array

A systolic array accelerator project (processing element → array → control → top-level integration),
built and verified in Verilog, targeted at Vivado for synthesis/implementation, with a Python golden
model for verification and (eventually) MNIST inference.

## Layout

```
rtl/          Verilog source: pe.v, array.v, controller.v, loader.v,
              uart_rx.v, uart_tx.v, top.v
tb/           Testbenches: tb_pe.v, tb_array.v, tb_ctrl_array.v,
              tb_uart_loop.v, tb_system.v
sim/          Test vectors (per-case dirs under sim/vectors/)
python/       Golden model, vector generator, and diff_trace.py debug tool
constraints/  XDC pin/timing constraints for the ZedBoard top-level
vivado/       Vivado project (auto-generated, gitignored)
docs/         Notes, block diagrams, screenshots for the report
```

## Build / simulate

- RTL and testbenches live under `rtl/` and `tb/`; test vectors consumed by the testbenches live under `sim/vectors/`.
- The Python golden model under `python/` generates the vectors in `sim/vectors/` and `diff_trace.py` can
  localize the first cycle/PE where an RTL sim trace diverges from the golden one.
- The Vivado project under `vivado/` is regenerated locally (not tracked in git) — open/create it there,
  point it at `rtl/`, `tb/`, and `constraints/top.xdc`, for synthesis, implementation, and waveform viewing.

## Status

**T0 complete** — full datapath (PE → array → controller) plus UART rx/tx, loader, saturating readout,
and top-level integration are in place, with `constraints/top.xdc` targeting the ZedBoard
(xc7z020clg484-1). End-to-end simulation (`tb_system.v`) passes bytes-in → correct-bytes-out on the
counting/random/extremes vector cases, overflow LED included. Tagged `t0-datapath` and `t0-system`.
