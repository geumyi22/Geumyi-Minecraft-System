package main

import (
	"errors"
	"fmt"
	"html"
	"strings"
)

// qrV6LModules builds a standards-compliant QR Code Model 2, version 6-L
// (41x41, byte mode, 134-byte payload capacity). The pairing URI is intentionally
// short enough for this fixed version, which keeps the implementation dependency-free.
func qrV6LModules(text string) ([][]bool, error) {
	data := []byte(text)
	if len(data) > 134 {
		return nil, fmt.Errorf("QR payload too long: %d bytes (max 134)", len(data))
	}

	const (
		dim           = 41
		dataCodewords = 136 // version 6-L: 2 blocks * 68 data codewords
		ecPerBlock    = 18
	)

	// Encode byte-mode payload into the 136 data codewords.
	bits := make([]bool, 0, dataCodewords*8)
	putBits := func(v, n int) {
		for i := n - 1; i >= 0; i-- {
			bits = append(bits, ((v>>i)&1) != 0)
		}
	}
	putBits(0x4, 4)       // byte mode
	putBits(len(data), 8) // version 1..9 byte-mode character count
	for _, b := range data {
		putBits(int(b), 8)
	}
	capBits := dataCodewords * 8
	terminator := 4
	if capBits-len(bits) < terminator {
		terminator = capBits - len(bits)
	}
	for i := 0; i < terminator; i++ {
		bits = append(bits, false)
	}
	for len(bits)%8 != 0 {
		bits = append(bits, false)
	}
	codeData := make([]byte, 0, dataCodewords)
	for i := 0; i < len(bits); i += 8 {
		var b byte
		for j := 0; j < 8; j++ {
			b <<= 1
			if bits[i+j] {
				b |= 1
			}
		}
		codeData = append(codeData, b)
	}
	pads := []byte{0xEC, 0x11}
	for i := 0; len(codeData) < dataCodewords; i++ {
		codeData = append(codeData, pads[i&1])
	}

	// Version 6-L uses 2 equal RS blocks, each 68 data + 18 EC codewords.
	block0 := append([]byte(nil), codeData[:68]...)
	block1 := append([]byte(nil), codeData[68:136]...)
	ec0 := qrRSParity(block0, ecPerBlock)
	ec1 := qrRSParity(block1, ecPerBlock)
	interleaved := make([]byte, 0, 172)
	for i := 0; i < 68; i++ {
		interleaved = append(interleaved, block0[i], block1[i])
	}
	for i := 0; i < ecPerBlock; i++ {
		interleaved = append(interleaved, ec0[i], ec1[i])
	}

	// -1 = unset, 0 = light, 1 = dark.
	modules := make([][]int8, dim)
	for r := range modules {
		modules[r] = make([]int8, dim)
		for c := range modules[r] {
			modules[r][c] = -1
		}
	}

	placeFinder := func(row, col int) {
		for dr := -1; dr <= 7; dr++ {
			rr := row + dr
			if rr < 0 || rr >= dim {
				continue
			}
			for dc := -1; dc <= 7; dc++ {
				cc := col + dc
				if cc < 0 || cc >= dim {
					continue
				}
				dark := (dr >= 0 && dr <= 6 && (dc == 0 || dc == 6)) ||
					(dc >= 0 && dc <= 6 && (dr == 0 || dr == 6)) ||
					(dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4)
				if dark {
					modules[rr][cc] = 1
				} else {
					modules[rr][cc] = 0
				}
			}
		}
	}
	placeFinder(0, 0)
	placeFinder(dim-7, 0)
	placeFinder(0, dim-7)

	// Version 6 alignment pattern positions: 6,34.
	for _, row := range []int{6, 34} {
		for _, col := range []int{6, 34} {
			if modules[row][col] != -1 {
				continue
			}
			for dr := -2; dr <= 2; dr++ {
				for dc := -2; dc <= 2; dc++ {
					dark := dr == -2 || dr == 2 || dc == -2 || dc == 2 || (dr == 0 && dc == 0)
					if dark {
						modules[row+dr][col+dc] = 1
					} else {
						modules[row+dr][col+dc] = 0
					}
				}
			}
		}
	}

	for r := 8; r < dim-8; r++ {
		if modules[r][6] == -1 {
			if r%2 == 0 {
				modules[r][6] = 1
			} else {
				modules[r][6] = 0
			}
		}
	}
	for c := 8; c < dim-8; c++ {
		if modules[6][c] == -1 {
			if c%2 == 0 {
				modules[6][c] = 1
			} else {
				modules[6][c] = 0
			}
		}
	}

	// Error correction L (01), mask pattern 0.
	format := qrFormatBits(0)
	for i := 0; i < 15; i++ {
		bit := int8((format >> i) & 1)
		if i < 6 {
			modules[i][8] = bit
		} else if i < 8 {
			modules[i+1][8] = bit
		} else {
			modules[dim-15+i][8] = bit
		}
	}
	for i := 0; i < 15; i++ {
		bit := int8((format >> i) & 1)
		if i < 8 {
			modules[8][dim-i-1] = bit
		} else if i < 9 {
			modules[8][15-i] = bit
		} else {
			modules[8][14-i] = bit
		}
	}
	modules[dim-8][8] = 1 // fixed dark module

	// Map data in the standard 2-column zig-zag, applying mask 0.
	row, inc := dim-1, -1
	byteIndex, bitIndex := 0, 7
	for col := dim - 1; col > 0; col -= 2 {
		if col == 6 {
			col--
		}
		for {
			for off := 0; off < 2; off++ {
				c := col - off
				if modules[row][c] != -1 {
					continue
				}
				bit := int8(0)
				if byteIndex < len(interleaved) && ((interleaved[byteIndex]>>bitIndex)&1) != 0 {
					bit = 1
				}
				if (row+c)%2 == 0 { // mask 0
					bit ^= 1
				}
				modules[row][c] = bit
				bitIndex--
				if bitIndex < 0 {
					byteIndex++
					bitIndex = 7
				}
			}
			row += inc
			if row < 0 || row >= dim {
				row -= inc
				inc = -inc
				break
			}
		}
	}

	out := make([][]bool, dim)
	for r := 0; r < dim; r++ {
		out[r] = make([]bool, dim)
		for c := 0; c < dim; c++ {
			if modules[r][c] < 0 {
				return nil, errors.New("QR matrix has unset module")
			}
			out[r][c] = modules[r][c] == 1
		}
	}
	return out, nil
}

func qrFormatBits(mask int) int {
	const g15 = 0x537
	data := (1 << 3) | (mask & 7) // L = 01
	d := data << 10
	degree := func(v int) int {
		n := 0
		for v != 0 {
			n++
			v >>= 1
		}
		return n
	}
	for degree(d)-degree(g15) >= 0 {
		d ^= g15 << (degree(d) - degree(g15))
	}
	return ((data << 10) | d) ^ 0x5412
}

var qrGFExp, qrGFLog = func() ([]int, []int) {
	exp := make([]int, 512)
	log := make([]int, 256)
	x := 1
	for i := 0; i < 255; i++ {
		exp[i] = x
		log[x] = i
		x <<= 1
		if x&0x100 != 0 {
			x ^= 0x11D
		}
	}
	for i := 255; i < 512; i++ {
		exp[i] = exp[i-255]
	}
	return exp, log
}()

func qrGFMul(a, b int) int {
	if a == 0 || b == 0 {
		return 0
	}
	return qrGFExp[qrGFLog[a]+qrGFLog[b]]
}

func qrPolyMul(a, b []int) []int {
	out := make([]int, len(a)+len(b)-1)
	for i, x := range a {
		for j, y := range b {
			out[i+j] ^= qrGFMul(x, y)
		}
	}
	return out
}

func qrRSParity(data []byte, degree int) []byte {
	gen := []int{1}
	for i := 0; i < degree; i++ {
		gen = qrPolyMul(gen, []int{1, qrGFExp[i]})
	}
	msg := make([]int, len(data)+degree)
	for i, b := range data {
		msg[i] = int(b)
	}
	for i := 0; i < len(data); i++ {
		coef := msg[i]
		if coef == 0 {
			continue
		}
		for j, g := range gen {
			msg[i+j] ^= qrGFMul(g, coef)
		}
	}
	out := make([]byte, degree)
	for i := 0; i < degree; i++ {
		out[i] = byte(msg[len(data)+i])
	}
	return out
}

func qrV6LSVG(text string) (string, error) {
	modules, err := qrV6LModules(text)
	if err != nil {
		return "", err
	}
	const border = 4
	dim := len(modules)
	size := dim + border*2
	var b strings.Builder
	b.Grow(12000)
	fmt.Fprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" role="img" aria-label="GSCM pairing QR"><rect width="100%%" height="100%%" fill="#fff"/><path fill="#000" d="`, size, size)
	for r := 0; r < dim; r++ {
		for c := 0; c < dim; c++ {
			if modules[r][c] {
				fmt.Fprintf(&b, "M%d %dh1v1h-1z", c+border, r+border)
			}
		}
	}
	b.WriteString(`"/><title>`)
	b.WriteString(html.EscapeString(text))
	b.WriteString(`</title></svg>`)
	return b.String(), nil
}
