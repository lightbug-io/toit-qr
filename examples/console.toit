// Copyright (C) 2026 onwave.com & lightbug.io.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import qr show QrCode

/**
Console QR code example.

Encodes text as a QR code and prints it to the console using block
  characters. This is useful for quick local verification without display
  hardware.
*/

main:
  print-qr "https://example.com"

/**
Prints the QR code for $text to the console.

Surrounds the QR code with a quiet zone of $quiet modules and renders each
  module as two characters to improve the terminal aspect ratio.
*/
print-qr text/string --quiet/int=2:
  qr := QrCode.encode text
  matrix := qr.matrix
  size := qr.size

  // Unicode full block for dark modules and spaces for light modules.
  black := "██"
  white := "  "

  total := size + quiet * 2
  total.repeat: | row |
    line := ""
    total.repeat: | col |
      m-row := row - quiet
      m-col := col - quiet

      is-black := false
      if m-row >= 0 and m-row < size and m-col >= 0 and m-col < size:
        is-black = matrix[m-row][m-col] == 1

      if is-black:
        line = "$line$black"
      else:
        line = "$line$white"
    print line
