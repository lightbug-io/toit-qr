# qr

Pure Toit QR code generation for constrained devices.

This package provides:

- `QrCode` — encodes data into a QR matrix (`0`/`1` modules).
- `QrBitmap` — converts that matrix to a 1-bit bitmap (MSB-first, byte-aligned rows), suitable for e-ink drawing APIs.

The encoder supports:

- **QR Version 3** (`29x29` modules)
- **ECC Level L**
- **Byte mode**
- Maximum payload: **42 bytes**

If input exceeds capacity, encoding throws an error.

## Install

Add the package to your Toit project dependencies and import it:

```toit
import qr show QrCode QrBitmap
```

## Basic usage

```toit
import qr show QrCode QrBitmap

main:
  qr := QrCode.encode "https://example.com"

  // Matrix (29x29), values: 0 = white, 1 = black
  matrix := qr.matrix
  size := qr.size

  // Convert matrix to 1-bit bitmap
  bmp := QrBitmap.from-matrix matrix --scale=3 --quiet=2

  print "QR modules: $size x $size"
  print "Bitmap: $(bmp.width)x$(bmp.height), bytes=$(bmp.data.size)"
```

## Examples

### Console

See `examples/console.toit`

```
[jaguar] INFO: program cbc4abf0-903f-4efc-fe52-7cb7357d9816 started


    ██████████████      ██      ██      ██      ██████████████
    ██          ██    ██      ██      ██        ██          ██
    ██  ██████  ██  ██    ██      ██      ██    ██  ██████  ██
    ██  ██████  ██    ██    ████    ████    ██  ██  ██████  ██
    ██  ██████  ██    ██    ████    ████    ██  ██  ██████  ██
    ██          ██      ██████  ██████  ██████  ██          ██
    ██████████████  ██  ██  ██  ██  ██  ██  ██  ██████████████
                    ██    ██      ██      ██
    ██████  ██████████      ██      ██      ██████      ██
      ████  ██    ██████  ██████  ██████  ████  ██    ██    ██
    ██    ██  ██████    ██████  ██████  ██████  ██████  ██████
    ██      ████  ██  ████  ██████  ██████  ████    ██    ██
    ██    ██    ██████  ████    ████    ██████████    ██  ████
    ██  ██          ██  ████    ████    ████  ████    ██    ██
                ████  ██      ██      ██      ██  ██████  ████
    ██  ████████    ██  ████      ██      ██████  ██  ██  ██
    ██      ██████          ██      ██    ████████    ██  ████
      ████            ██  ██████  ██████    ██████    ████  ██
    ██  ██████████      ██████  ██████  ██    ████  ██    ████
      ████████        ████  ██████  ██████  ██    ██████  ██
    ██  ████  ██████    ████    ████    ██████████████
                    ████████    ████    ██████      ██  ██████
    ██████████████  ██        ██      ██  ████  ██  ████  ████
    ██          ██  ██  ████      ██        ██      ████    ██
    ██  ██████  ██  ████    ██      ██      ██████████      ██
    ██  ██████  ██    ██  ██████  ██████    ████    ██  ██
    ██  ██████  ██  ████  ████  ██████  ██  ██    ██████    ██
    ██          ██  ██████  ██████  ██████████  ██        ██
    ██████████████  ████  ██    ████    ██████    ████    ████


[jaguar] INFO: program cbc4abf0-903f-4efc-fe52-7cb7357d9816 stopped
```

### Lightbug e-ink screen

See `examples/lightbug.toit`

Example QR rendered on an e-ink screen:

![QR on e-ink screen](https://upload.r2.lb.chasm.cloud/2026/03/6B6dJERWtt.jpg)
