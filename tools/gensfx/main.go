package main

import (
	"encoding/binary"
	"math"
	"math/rand"
	"os"
	"path/filepath"
)

const sampleRate = 44100

func main() {
	outDir := filepath.Join("..", "..", "assets", "sfx")
	if len(os.Args) > 1 {
		outDir = os.Args[1]
	}
	_ = os.MkdirAll(outDir, 0o755)
	mustWrite(filepath.Join(outDir, "shoot.wav"), synthGunBang())
	mustWrite(filepath.Join(outDir, "death.wav"), synthScream())
	mustWrite(filepath.Join(outDir, "walk.wav"), synthWalk())
}

func mustWrite(path string, samples []float64) {
	if err := writeWAV(path, samples); err != nil {
		panic(err)
	}
}

func writeWAV(path string, samples []float64) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	n := len(samples)
	dataBytes := n * 2
	hdr := make([]byte, 44)
	copy(hdr[0:], []byte("RIFF"))
	binary.LittleEndian.PutUint32(hdr[4:], uint32(36+dataBytes))
	copy(hdr[8:], []byte("WAVE"))
	copy(hdr[12:], []byte("fmt "))
	binary.LittleEndian.PutUint32(hdr[16:], 16)
	binary.LittleEndian.PutUint16(hdr[20:], 1)
	binary.LittleEndian.PutUint16(hdr[22:], 1)
	binary.LittleEndian.PutUint32(hdr[24:], sampleRate)
	binary.LittleEndian.PutUint32(hdr[28:], sampleRate*2)
	binary.LittleEndian.PutUint16(hdr[32:], 2)
	binary.LittleEndian.PutUint16(hdr[34:], 16)
	copy(hdr[36:], []byte("data"))
	binary.LittleEndian.PutUint32(hdr[40:], uint32(dataBytes))
	if _, err := f.Write(hdr); err != nil {
		return err
	}
	buf := make([]byte, 2)
	for _, s := range samples {
		if s > 1 {
			s = 1
		} else if s < -1 {
			s = -1
		}
		v := int16(s * 32767)
		binary.LittleEndian.PutUint16(buf, uint16(v))
		if _, err := f.Write(buf); err != nil {
			return err
		}
	}
	return nil
}

// Short sharp rifle BANG — no whoosh / rocket sweep.
func synthGunBang() []float64 {
	rng := rand.New(rand.NewSource(11))
	dur := 0.28
	n := int(float64(sampleRate) * dur)
	out := make([]float64, n)

	// 1) Instant impulse (the "бах")
	impulseN := sampleRate / 500 // ~2ms
	for i := 0; i < impulseN && i < n; i++ {
		t := float64(i) / float64(impulseN)
		out[i] += (1.0 - t) * (rng.Float64()*2 - 1) * 1.2
	}

	// 2) Crack: bright noise, dies in ~60ms
	for i := 0; i < n; i++ {
		t := float64(i) / sampleRate
		env := math.Exp(-t * 55)
		// High-pass-ish: difference of noise with lag
		n0 := rng.Float64()*2 - 1
		out[i] += n0 * env * 0.85
	}

	// 3) Chest punch: fixed low thud, NOT a long descending whoosh
	for i := 0; i < n; i++ {
		t := float64(i) / sampleRate
		env := math.Exp(-t * 22)
		out[i] += math.Sin(2*math.Pi*95*t) * env * 0.9
		out[i] += math.Sin(2*math.Pi*55*t) * env * 0.45
	}

	// 4) Tiny metallic snap (~8ms)
	for i := 0; i < n; i++ {
		t := float64(i) / sampleRate
		if t > 0.012 {
			break
		}
		env := math.Exp(-t * 220)
		out[i] += math.Sin(2*math.Pi*2800*t) * env * 0.4
	}

	// Soft clip + normalize — keep punchy
	return normalize(softClip(out), 0.95)
}

// Pain scream / cry for death.
func synthScream() []float64 {
	rng := rand.New(rand.NewSource(3))
	dur := 0.95
	n := int(float64(sampleRate) * dur)
	out := make([]float64, n)
	phase := 0.0
	for i := 0; i < n; i++ {
		t := float64(i) / sampleRate
		// Pitch glide: scream down
		f0 := 520 * math.Exp(-t*1.8) // ~520 → ~90
		// Amplitude: fast attack, hold, then fade
		amp := 1.0
		if t < 0.04 {
			amp = t / 0.04
		} else if t > 0.55 {
			amp = math.Exp(-(t - 0.55) * 4.5)
		}
		// Vibrato / roughness
		vib := 1.0 + 0.035*math.Sin(2*math.Pi*6.5*t)
		f := f0 * vib
		phase += 2 * math.Pi * f / sampleRate
		// Harmonic stack ≈ voice
		s := math.Sin(phase)*0.55 +
			math.Sin(phase*2)*0.28 +
			math.Sin(phase*3)*0.14 +
			math.Sin(phase*4)*0.08
		// Breath / grit noise modulated by voice
		noise := (rng.Float64()*2 - 1) * 0.22 * (0.4 + 0.6*math.Abs(s))
		// Formant-ish resonance bumps
		s += math.Sin(phase*1.0+0.3) * 0.1
		out[i] = (s + noise) * amp * 0.95
		// Late body fall thud
		if t > 0.45 && t < 0.7 {
			tt := t - 0.45
			out[i] += math.Sin(2*math.Pi*70*tt) * math.Exp(-tt*12) * 0.35
			out[i] += (rng.Float64()*2 - 1) * math.Exp(-tt*10) * 0.12
		}
	}
	return normalize(softClip(out), 0.9)
}

func synthWalk() []float64 {
	rng := rand.New(rand.NewSource(99))
	dur := 0.16
	n := int(float64(sampleRate) * dur)
	out := make([]float64, n)
	for i := 0; i < n; i++ {
		t := float64(i) / sampleRate
		env := math.Exp(-t * 28)
		thud := math.Sin(2*math.Pi*95*t) * env * 0.55
		scrape := (rng.Float64()*2 - 1) * math.Exp(-t*40) * 0.3
		out[i] = thud + scrape
	}
	return normalize(softClip(out), 0.8)
}

func softClip(in []float64) []float64 {
	out := make([]float64, len(in))
	for i, s := range in {
		out[i] = math.Tanh(s * 1.2)
	}
	return out
}

func normalize(in []float64, peak float64) []float64 {
	m := 0.0
	for _, s := range in {
		a := math.Abs(s)
		if a > m {
			m = a
		}
	}
	if m < 1e-9 {
		return in
	}
	scale := peak / m
	out := make([]float64, len(in))
	for i, s := range in {
		out[i] = s * scale
	}
	return out
}
