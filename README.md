# systolic_array

A systolic array accelerator project (processing element → array → control → top-level integration),
built and verified in Verilog, targeted at Vivado for synthesis/implementation, with a Python golden
model for verification and (eventually) MNIST inference.

## Layout

```
rtl/       Verilog source (pe.v, array.v, control.v, top.v)
tb/        Testbenches (tb_pe.v, tb_array.v)
sim/       Test vectors (inputs.hex, expected.hex)
python/    Golden model, vector generator, later MNIST integration
vivado/    Vivado project (auto-generated, gitignored)
docs/      Notes, block diagrams, screenshots for the report
```

## Build / simulate

- RTL and testbenches live under `rtl/` and `tb/`; test vectors consumed by the testbenches live under `sim/`.
- The Python golden model under `python/` generates the vectors in `sim/` and can independently check
  results against the RTL simulation output.
- The Vivado project under `vivado/` is regenerated locally (not tracked in git) — open/create it there
  and point it at the `rtl/` and `tb/` sources for synthesis, implementation, and waveform viewing.

## Status

Project scaffolding in progress.
