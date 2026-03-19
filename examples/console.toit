/**
 * Console QR code example.
 *
 * Encodes text as a QR code and prints it to the console using block
 * characters. This is useful for quick local verification without display
 * hardware.
 */

import qr show QrCode

main:
  print-qr "https://example.com"

/**
 * Print a QR code to the console.
 *
 * Uses a quiet zone around the QR and renders each module using 2
 * characters to improve terminal aspect ratio.
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
