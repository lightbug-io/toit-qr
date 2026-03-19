/**
 * E-ink QR code display helper.
 *
 * Encodes text as a QR code and draws it on the lightbug e-ink screen,
 * handling bitmap conversion and strip-based sending automatically.
 *
 * Usage:
 *   import lightbug.modules.eink.qrcode show draw-qr
 *
 *   draw-qr device
 *       --page-id=22
 *       --text="https://example.com"
 */

import ...messages as messages
import ...devices as devices
import .qrcode show QrCode QrBitmap

/** Default e-ink screen dimensions. */
SCREEN-WIDTH_  ::= 250
SCREEN-HEIGHT_ ::= 122

/** Maximum bitmap bytes per I2C message. */
MAX-BYTES-PER-MSG_ ::= 255

/**
 * Encode text as a QR code and draw it on the e-ink screen.
 *
 * The QR code is automatically centered on the 250x122 screen unless
 * --x and --y are provided. The bitmap is sent in strips to stay within
 * the 255-byte I2C message limit.
 *
 * Parameters:
 *   --page-id: The e-ink page ID to draw on.
 *   --text: The text to encode in the QR code (max 42 bytes UTF-8).
 *   --scale: Pixels per QR module (default 3).
 *   --quiet: Quiet zone width in modules (default 2).
 *   --x, --y: Top-left position. Defaults to centered.
 *   --status-bar-enable: Whether to show status bar (default false).
 */
draw-qr device/devices.Device
    --page-id/int
    --text/string
    --scale/int=3
    --quiet/int=2
    --x/int?=null
    --y/int?=null
    --status-bar-enable/bool=false:
  qr := QrCode.encode text
  bmp := QrBitmap.from-matrix qr.matrix --scale=scale --quiet=quiet

  draw-x := x
  if draw-x == null:
    draw-x = (SCREEN-WIDTH_ - bmp.width) / 2
  draw-y := y
  if draw-y == null:
    draw-y = (SCREEN-HEIGHT_ - bmp.height) / 2

  // Send bitmap in strips (255-byte I2C message limit)
  bytes-per-row := (bmp.width + 7) / 8
  max-rows-per-strip := MAX-BYTES-PER-MSG_ / bytes-per-row
  total-rows := bmp.height
  strip-y := draw-y
  rows-sent := 0

  while rows-sent < total-rows:
    rows-this-strip := total-rows - rows-sent
    if rows-this-strip > max-rows-per-strip:
      rows-this-strip = max-rows-per-strip

    strip-size := rows-this-strip * bytes-per-row
    strip := ByteArray strip-size
    strip-size.repeat: | i |
      strip[i] = bmp.data[rows-sent * bytes-per-row + i]

    is-last := (rows-sent + rows-this-strip) >= total-rows
    redraw-type := messages.DrawElement.REDRAW-TYPE_BUFFERONLY
    if is-last: redraw-type = messages.DrawElement.REDRAW-TYPE_FULLREDRAWWITHOUTCLEAR

    device.eink.draw-bitmap
        --page-id=page-id
        --status-bar-enable=status-bar-enable
        --redraw-type=redraw-type
        --x=draw-x
        --y=strip-y
        --width=bmp.width
        --height=rows-this-strip
        --bitmap=strip

    strip-y += rows-this-strip
    rows-sent += rows-this-strip
