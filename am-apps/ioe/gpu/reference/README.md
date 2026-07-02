# GPU Reference Images

These PNGs are the visual references for `am-apps/ioe/gpu`.

Run the test on ysyxSoC/NVBoard and compare each printed `STEP` with the
matching image:

```sh
make -C am-apps/ioe/gpu ARCH=riscv32e-ysyxsoc run
```

- `01-background.png`: full-screen dark fill.
- `02-border.png`: adds an 8-pixel white border.
- `03-gradient.png`: adds the top inner gradient band.
- `04-checker.png`: adds the blue/dark checkerboard area.
- `05-cross.png`: overlays the red center cross.
- `06-final.png`: overlays four corner color blocks.

Regenerate them with:

```sh
python3 am-apps/ioe/gpu/reference/gen_gpu_reference.py
```
