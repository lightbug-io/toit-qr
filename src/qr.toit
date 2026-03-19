/**
 * Pure QR Code encoder.
 *
 * Currently supports Version 3 (29x29), ECC Level L, Byte mode.
 * Produces a matrix (List of Lists of 0/1) that can be rendered
 * to any display format.
 *
 * Usage:
 *   qr := QrCode.encode "https://example.com/foo"
 *   matrix := qr.matrix  // List of List of int (0/1)
 *   size := qr.size       // 29
 *
 * To convert to a 1-bit-per-pixel bitmap (e.g. for e-ink):
 *   bmp := QrBitmap.from-matrix qr.matrix --scale=3 --quiet=2
 *   bmp.data    // ByteArray (MSB-first, rows byte-aligned)
 *   bmp.width   // pixel width
 *   bmp.height  // pixel height
 */

// ============================================================================
// GF(256) Arithmetic (private)
// ============================================================================

/**
 * GF(256) arithmetic for Reed-Solomon error correction.
 * Uses generator polynomial 0x11D (x^8 + x^4 + x^3 + x^2 + 1).
 * Tables are initialized lazily on first use.
 */
class Gf256_:
  static exp_/ByteArray? := null
  static log_/ByteArray? := null

  static ensure-init_:
    if exp_ != null: return
    exp_ = ByteArray 512
    log_ = ByteArray 256
    val := 1
    255.repeat: | i |
      exp_[i] = val
      log_[val] = i
      val = val << 1
      if val >= 256:
        val = val ^ 0x11D
    // Double the exp table for easy modular lookup
    255.repeat: | i |
      exp_[255 + i] = exp_[i]

  static multiply a/int b/int -> int:
    if a == 0 or b == 0: return 0
    ensure-init_
    return exp_[log_[a] + log_[b]]

  static exp-at index/int -> int:
    ensure-init_
    return exp_[index]

// ============================================================================
// QR Code Encoder
// ============================================================================

/**
 * QR Code encoder for Version 3 (29x29), ECC Level L, Byte mode.
 *
 * Create a QR code from a string or ByteArray:
 *   qr := QrCode.encode "Hello"
 *   qr := QrCode.encode-bytes my-byte-array
 *
 * Access the result:
 *   qr.matrix   // List of List of int, 29x29, values 0 (white) or 1 (black)
 *   qr.size     // 29
 */
class QrCode:
  static VERSION  ::= 3
  static SIZE     ::= 29
  /** Maximum number of data bytes that can be encoded (byte mode, ECC-L). */
  static MAX-DATA-BYTES ::= 42
  static DATA-CODEWORDS_  ::= 55
  static EC-CODEWORDS_    ::= 15
  static TOTAL-CODEWORDS_ ::= 70

  /** The QR matrix: a 29x29 List of Lists containing 0 (white) or 1 (black). */
  matrix/List
  /** The side length of the QR code in modules. */
  size/int

  constructor.internal_ .matrix .size:

  /**
   * Encode a UTF-8 string as a QR code.
   * The string must fit in Version 3 byte mode (at most 42 bytes for ECC-L).
   */
  static encode text/string -> QrCode:
    return encode-bytes text.to-byte-array

  /**
   * Encode raw bytes as a QR code.
   * Throws if data exceeds 42 bytes (Version 3 byte mode, ECC-L capacity).
   */
  static encode-bytes data/ByteArray -> QrCode:
    if data.size > MAX-DATA-BYTES:
      throw "QR data too large: $(data.size) bytes, max $MAX-DATA-BYTES"
    data-codewords := encode-data_ data
    ec-codewords := generate-ec_ data-codewords
    matrix := build-matrix_ data-codewords ec-codewords
    return QrCode.internal_ matrix SIZE

  // --------------------------------------------------------------------------
  // Data Encoding
  // --------------------------------------------------------------------------

  /**
   * Encode data bytes into QR code data codewords (byte mode, ECC-L).
   */
  static encode-data_ data/ByteArray -> ByteArray:
    bits := []

    // Mode indicator: Byte mode = 0100
    bits.add 0
    bits.add 1
    bits.add 0
    bits.add 0

    // Character count (8 bits for Version 1-9 in byte mode)
    len := data.size
    8.repeat: | i |
      bits.add ((len >> (7 - i)) & 1)

    // Data
    data.do: | byte |
      8.repeat: | i |
        bits.add ((byte >> (7 - i)) & 1)

    // Terminator (up to 4 zeros)
    total-data-bits := DATA-CODEWORDS_ * 8
    terminator-len := total-data-bits - bits.size
    if terminator-len > 4: terminator-len = 4
    terminator-len.repeat:
      bits.add 0

    // Pad to byte boundary
    while bits.size % 8 != 0:
      bits.add 0

    // Convert bits to codewords
    result := ByteArray DATA-CODEWORDS_
    num-codewords := bits.size / 8
    num-codewords.repeat: | i |
      val := 0
      8.repeat: | j |
        val = (val << 1) | bits[i * 8 + j]
      result[i] = val

    // Pad with alternating 0xEC, 0x11
    pad-idx := 0
    pads := [0xEC, 0x11]
    for i := num-codewords; i < DATA-CODEWORDS_; i++:
      result[i] = pads[pad-idx % 2]
      pad-idx++

    return result

  // --------------------------------------------------------------------------
  // Reed-Solomon Error Correction
  // --------------------------------------------------------------------------

  /**
   * Generate Reed-Solomon error correction codewords.
   */
  static generate-ec_ data/ByteArray -> ByteArray:
    gen := rs-generator-poly_ EC-CODEWORDS_

    // Polynomial division
    msg := ByteArray (data.size + EC-CODEWORDS_)
    data.size.repeat: | i |
      msg[i] = data[i]

    data.size.repeat: | i |
      coef := msg[i]
      if coef != 0:
        gen.size.repeat: | j |
          msg[i + j] = msg[i + j] ^ (Gf256_.multiply coef gen[j])

    // EC codewords are the remainder
    result := ByteArray EC-CODEWORDS_
    EC-CODEWORDS_.repeat: | i |
      result[i] = msg[data.size + i]

    return result

  /**
   * Compute RS generator polynomial coefficients.
   * Returns coefficients in standard order: leading coefficient first.
   */
  static rs-generator-poly_ num-ec/int -> ByteArray:
    gen := ByteArray (num-ec + 1)
    gen[0] = 1

    num-ec.repeat: | i |
      new-gen := ByteArray (num-ec + 1)
      (i + 1).repeat: | j |
        new-gen[j + 1] = new-gen[j + 1] ^ gen[j]
        new-gen[j] = new-gen[j] ^ (Gf256_.multiply gen[j] (Gf256_.exp-at i))
      (num-ec + 1).repeat: | j |
        gen[j] = new-gen[j]

    // Reverse to standard order: leading coefficient (x^n) first,
    // constant term last. The construction above builds coefficients
    // with constant term first; RS division expects leading first.
    half := (num-ec + 1) / 2
    half.repeat: | i |
      j := num-ec - i
      tmp := gen[i]
      gen[i] = gen[j]
      gen[j] = tmp

    return gen

  // --------------------------------------------------------------------------
  // Matrix Construction
  // --------------------------------------------------------------------------

  /**
   * Build the complete QR matrix with patterns, data, mask, and format info.
   */
  static build-matrix_ data-codewords/ByteArray ec-codewords/ByteArray -> List:
    size := SIZE

    matrix := List size: List size: 0
    reserved := List size: List size: false

    // Function patterns
    place-finder-pattern_ matrix reserved 0 0
    place-finder-pattern_ matrix reserved (size - 7) 0
    place-finder-pattern_ matrix reserved 0 (size - 7)
    place-separators_ matrix reserved size
    place-alignment-pattern_ matrix reserved 22 22
    place-timing-patterns_ matrix reserved size

    // Dark module
    matrix[size - 8][8] = 1
    reserved[size - 8][8] = true

    // Reserve format info areas
    reserve-format-info_ matrix reserved size

    // Combine data and EC codewords
    all-codewords := ByteArray TOTAL-CODEWORDS_
    data-codewords.size.repeat: | i |
      all-codewords[i] = data-codewords[i]
    ec-codewords.size.repeat: | i |
      all-codewords[data-codewords.size + i] = ec-codewords[i]

    // Place data bits and apply best mask
    place-data-bits_ matrix reserved all-codewords size
    apply-best-mask_ matrix reserved size

    return matrix

  // --------------------------------------------------------------------------
  // Pattern Placement (private)
  // --------------------------------------------------------------------------

  /** Place a 7x7 finder pattern with top-left corner at (row, col). */
  static place-finder-pattern_ matrix/List reserved/List row/int col/int:
    7.repeat: | r |
      7.repeat: | c |
        val := 0
        if r == 0 or r == 6 or c == 0 or c == 6:
          val = 1
        else if r >= 2 and r <= 4 and c >= 2 and c <= 4:
          val = 1
        matrix[row + r][col + c] = val
        reserved[row + r][col + c] = true

  /** Place white separators around finder patterns. */
  static place-separators_ matrix/List reserved/List size/int:
    8.repeat: | i |
      matrix[7][i] = 0
      reserved[7][i] = true
      matrix[i][7] = 0
      reserved[i][7] = true

    8.repeat: | i |
      matrix[7][size - 8 + i] = 0
      reserved[7][size - 8 + i] = true
      matrix[i][size - 8] = 0
      reserved[i][size - 8] = true

    8.repeat: | i |
      matrix[size - 8][i] = 0
      reserved[size - 8][i] = true
      matrix[size - 8 + i][7] = 0
      reserved[size - 8 + i][7] = true

  /** Place 5x5 alignment pattern centered at (row, col). */
  static place-alignment-pattern_ matrix/List reserved/List center-row/int center-col/int:
    for dr := -2; dr <= 2; dr++:
      for dc := -2; dc <= 2; dc++:
        r := center-row + dr
        c := center-col + dc
        if not reserved[r][c]:
          val := 0
          if dr == -2 or dr == 2 or dc == -2 or dc == 2:
            val = 1
          else if dr == 0 and dc == 0:
            val = 1
          matrix[r][c] = val
          reserved[r][c] = true

  /** Place timing patterns (alternating black/white). */
  static place-timing-patterns_ matrix/List reserved/List size/int:
    for i := 8; i < size - 8; i++:
      val := 0
      if i % 2 == 0: val = 1
      if not reserved[6][i]:
        matrix[6][i] = val
        reserved[6][i] = true
      if not reserved[i][6]:
        matrix[i][6] = val
        reserved[i][6] = true

  /** Reserve format information areas. */
  static reserve-format-info_ matrix/List reserved/List size/int:
    9.repeat: | i |
      if not reserved[8][i]:
        reserved[8][i] = true
      if not reserved[i][8]:
        reserved[i][8] = true

    8.repeat: | i |
      if not reserved[8][size - 1 - i]:
        reserved[8][size - 1 - i] = true

    7.repeat: | i |
      if not reserved[size - 1 - i][8]:
        reserved[size - 1 - i][8] = true

  // --------------------------------------------------------------------------
  // Data Placement
  // --------------------------------------------------------------------------

  /**
   * Place data bits in the matrix following the QR zigzag pattern.
   * Uses Nayuki's algorithm with separate loop counter to correctly
   * skip the timing column (column 6).
   */
  static place-data-bits_ matrix/List reserved/List codewords/ByteArray size/int:
    bit-idx := 0
    total-bits := codewords.size * 8

    // Loop variable always decrements by 2. The actual column shifts
    // left by 1 when <= 6, producing pairs:
    //   ..., 8->(8,7), 6->(5,4), 4->(3,2), 2->(1,0)
    loop-right := size - 1
    while loop-right >= 1:
      right := loop-right
      if right <= 6: right--

      going-up := (right + 1) & 2 == 0

      size.repeat: | vert |
        row := vert
        if going-up: row = size - 1 - vert

        2.repeat: | j |
          col := right - j
          if not reserved[row][col]:
            if bit-idx < total-bits:
              byte-idx := bit-idx / 8
              bit-pos := 7 - (bit-idx % 8)
              bit := (codewords[byte-idx] >> bit-pos) & 1
              matrix[row][col] = bit
              bit-idx++
            else:
              matrix[row][col] = 0

      loop-right -= 2

  // --------------------------------------------------------------------------
  // Masking
  // --------------------------------------------------------------------------

  /** Try all 8 masks, score each, apply the best one. */
  static apply-best-mask_ matrix/List reserved/List size/int -> int:
    best-score := 0x7FFFFFFF
    best-mask := 0

    8.repeat: | mask-idx |
      test := List size: | r |
        List size: | c |
          matrix[r][c]

      apply-mask_ test reserved size mask-idx
      write-format-info_ test size mask-idx

      s := score-matrix_ test size
      if s < best-score:
        best-score = s
        best-mask = mask-idx

    apply-mask_ matrix reserved size best-mask
    write-format-info_ matrix size best-mask
    return best-mask

  /** Apply a mask pattern to data modules. */
  static apply-mask_ matrix/List reserved/List size/int mask-idx/int:
    size.repeat: | row |
      size.repeat: | col |
        if not reserved[row][col]:
          flip := false
          if mask-idx == 0: flip = (row + col) % 2 == 0
          else if mask-idx == 1: flip = row % 2 == 0
          else if mask-idx == 2: flip = col % 3 == 0
          else if mask-idx == 3: flip = (row + col) % 3 == 0
          else if mask-idx == 4: flip = (row / 2 + col / 3) % 2 == 0
          else if mask-idx == 5: flip = ((row * col) % 2) + ((row * col) % 3) == 0
          else if mask-idx == 6: flip = (((row * col) % 2) + ((row * col) % 3)) % 2 == 0
          else if mask-idx == 7: flip = (((row + col) % 2) + ((row * col) % 3)) % 2 == 0
          if flip:
            matrix[row][col] = matrix[row][col] ^ 1

  // --------------------------------------------------------------------------
  // Format Info
  // --------------------------------------------------------------------------

  /**
   * Write format information (ECC level L + mask) into the matrix.
   * BCH(15,5) encoding with generator polynomial 0x537, mask 0x5412.
   */
  static write-format-info_ matrix/List size/int mask-idx/int:
    format-data := (0b01 << 3) | mask-idx

    remainder := format-data
    10.repeat:
      remainder = remainder << 1
    for i := 4; i >= 0; i--:
      if (remainder & (1 << (i + 10))) != 0:
        remainder = remainder ^ (0x537 << i)
    format-bits := (format-data << 10) | remainder
    format-bits = format-bits ^ 0x5412

    // First copy: around top-left finder
    TL-HORIZ-COLS ::= [0, 1, 2, 3, 4, 5, 7, 8]
    TL-VERT-ROWS  ::= [7, 5, 4, 3, 2, 1, 0]

    8.repeat: | i |
      bit := (format-bits >> (14 - i)) & 1
      matrix[8][TL-HORIZ-COLS[i]] = bit

    7.repeat: | i |
      bit := (format-bits >> (6 - i)) & 1
      matrix[TL-VERT-ROWS[i]][8] = bit

    // Second copy: around bottom-left and top-right finders
    7.repeat: | i |
      bit := (format-bits >> (14 - i)) & 1
      matrix[size - 1 - i][8] = bit

    8.repeat: | i |
      bit := (format-bits >> (7 - i)) & 1
      matrix[8][size - 8 + i] = bit

  // --------------------------------------------------------------------------
  // Penalty Scoring
  // --------------------------------------------------------------------------

  /** Score a masked matrix using all 4 QR penalty rules. */
  static score-matrix_ matrix/List size/int -> int:
    score := 0

    // Penalty 1: runs of 5+ same-color modules
    size.repeat: | row |
      count := 1
      size.repeat: | col |
        if col == 0:
          count = 1
        else if matrix[row][col] == matrix[row][col - 1]:
          count++
          if count == 5: score += 3
          else if count > 5: score += 1
        else:
          count = 1

    size.repeat: | col |
      count := 1
      size.repeat: | row |
        if row == 0:
          count = 1
        else if matrix[row][col] == matrix[row - 1][col]:
          count++
          if count == 5: score += 3
          else if count > 5: score += 1
        else:
          count = 1

    // Penalty 2: 2x2 blocks of same color
    (size - 1).repeat: | row |
      (size - 1).repeat: | col |
        v := matrix[row][col]
        if v == matrix[row][col + 1] and v == matrix[row + 1][col] and v == matrix[row + 1][col + 1]:
          score += 3

    // Penalty 3: finder-like patterns
    FINDER-A_ ::= [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
    FINDER-B_ ::= [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
    size.repeat: | row |
      (size - 10).repeat: | col |
        match-a := true
        match-b := true
        11.repeat: | k |
          if matrix[row][col + k] != FINDER-A_[k]: match-a = false
          if matrix[row][col + k] != FINDER-B_[k]: match-b = false
        if match-a or match-b: score += 40
    size.repeat: | col |
      (size - 10).repeat: | row |
        match-a := true
        match-b := true
        11.repeat: | k |
          if matrix[row + k][col] != FINDER-A_[k]: match-a = false
          if matrix[row + k][col] != FINDER-B_[k]: match-b = false
        if match-a or match-b: score += 40

    // Penalty 4: dark/light balance
    dark := 0
    size.repeat: | row |
      size.repeat: | col |
        if matrix[row][col] == 1: dark++
    total := size * size
    pct := dark * 100 / total
    prev5 := (pct / 5) * 5
    next5 := prev5 + 5
    diff-prev := prev5 - 50
    if diff-prev < 0: diff-prev = 0 - diff-prev
    diff-next := next5 - 50
    if diff-next < 0: diff-next = 0 - diff-next
    penalty4 := diff-prev / 5
    if diff-next / 5 < penalty4: penalty4 = diff-next / 5
    score += penalty4 * 10

    return score

// ============================================================================
// QR Bitmap Converter
// ============================================================================

/**
 * Converts a QR matrix to a 1-bit-per-pixel bitmap.
 *
 * The bitmap format is MSB-first, rows packed to byte boundaries.
 * Suitable for the lightbug e-ink display (draw-bitmap).
 *
 * Usage:
 *   qr := QrCode.encode "https://example.com"
 *   bmp := QrBitmap.from-matrix qr.matrix --scale=3 --quiet=2
 *   bmp.data    // ByteArray
 *   bmp.width   // pixel width
 *   bmp.height  // pixel height
 */
class QrBitmap:
  /** The 1-bit-per-pixel bitmap data, MSB-first, rows byte-aligned. */
  data/ByteArray
  /** Bitmap width in pixels. */
  width/int
  /** Bitmap height in pixels. */
  height/int

  constructor.internal_ .data .width .height:

  /**
   * Create a bitmap from a QR matrix.
   * Each QR module is rendered at --scale pixels.
   * A --quiet module white border (quiet zone) is added around all sides.
   */
  static from-matrix matrix/List --scale/int=3 --quiet/int=2 -> QrBitmap:
    qr-size := matrix.size
    total-modules := qr-size + quiet * 2
    pixel-width := total-modules * scale
    pixel-height := total-modules * scale

    bytes-per-row := (pixel-width + 7) / 8
    bitmap := ByteArray (bytes-per-row * pixel-height)

    pixel-height.repeat: | py |
      module-row := py / scale - quiet

      pixel-width.repeat: | px |
        module-col := px / scale - quiet

        is-black := false
        if module-row >= 0 and module-row < qr-size and module-col >= 0 and module-col < qr-size:
          is-black = matrix[module-row][module-col] == 1

        if is-black:
          byte-idx := py * bytes-per-row + (px / 8)
          bit-pos := 7 - (px % 8)
          bitmap[byte-idx] = bitmap[byte-idx] | (1 << bit-pos)

    return QrBitmap.internal_ bitmap pixel-width pixel-height
