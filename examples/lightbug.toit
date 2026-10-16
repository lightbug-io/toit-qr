// Copyright (C) 2026 onwave.com & lightbug.io.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import lightbug.messages as messages
import lightbug.devices as devices
import qr show QrCode QrBitmap

/**
E-ink QR code display on a Lightbug device.

Encodes text as a QR code and draws it on the Lightbug e-ink screen, handling
  bitmap conversion and strip-based sending automatically.
*/

/** The width of the e-ink screen in pixels. */
SCREEN-WIDTH_  ::= 250
/** The height of the e-ink screen in pixels. */
SCREEN-HEIGHT_ ::= 122

/** The maximum number of bitmap bytes per I2C message. */
MAX-BYTES-PER-MSG_ ::= 255

main:
  device := devices.I2C --background=false
  draw-qr device
      --page-id=22
      --text="https://example.com"

/**
Encodes $text as a QR code and draws it on the e-ink screen.

Draws on the e-ink page identified by $page-id. The $text must fit in version
  3 byte mode (at most $QrCode.MAX-DATA-BYTES bytes of UTF-8).

Renders each QR module as a $scale by $scale block of pixels, surrounded by a
  quiet zone of $quiet modules.

Centers the QR code on the 250x122 screen unless $x and $y are given, in which
  case they are used as the top-left position. Shows the status bar if
  $status-bar-enable is set.

The bitmap is sent in strips to stay within the 255-byte I2C message limit.
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

  // Send the bitmap in strips (255-byte I2C message limit).
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
