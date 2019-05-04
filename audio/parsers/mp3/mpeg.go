package mp3

// bitrateLUT is indexed by [versionID][layer][bitrateIdx]
var bitrateLUT [4][4][16]int = [4][4][16]int{
	{
		// versionID = 0 (MPEG 2.5)
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},                       // Reserved
		{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},      // L3
		{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},      // L2
		{0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0}, // L1
	},
	{
		// versionID = 1 (reserved)
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, // Reserved
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, // Reserved
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, // Reserved
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, // Reserved
	},
	{
		// versionID = 2 (MPEG 2)
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},                    // Reserved
		{8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},      // L3
		{8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},      // L2
		{32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0}, // L1
	},
	{
		// versionID = 3 (MPEG 1)
		{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},                       // Reserved
		{0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320},     // L3
		{0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384},    // L2
		{0, 32, 64, 96, 128, 160, 192, 224, 256, 228, 320, 352, 384, 416, 448}, // L1
	},
}

// samplingRateLUT indexed by [versionID][sampleIdx]
var samplingRateLUT [4][4]int = [4][4]int{
	{11025, 12000, 8000, 0},  // MPEG 2.5
	{0, 0, 0, 0},             // Reserved
	{22050, 24000, 16000, 0}, // MPEG 2
	{44100, 48000, 32000, 0}, // MPEG 1
}

// coefficientLUT indexed by [versionID][layer]
var coefficientLUT [4][4]int = [4][4]int{
	{0, 72, 144, 12},  // MPEG 2.5
	{0, 0, 0, 0},      // Reserved
	{0, 72, 144, 12},  // MPEG 2
	{0, 144, 144, 12}, // MPEG 1
}

// indexed by layer
var paddingLUT [4]int = [4]int{0, 1, 1, 4}

type MPEGHeader struct {
	Raw []byte
}

func (h *MPEGHeader) Bitrate() int {
	return bitrateLUT[h.version()][h.layer()][h.bitrateIndex()]
}

func (h *MPEGHeader) SamplingRate() int {
	return samplingRateLUT[h.version()][h.sampleIndex()]
}

func (h *MPEGHeader) NumSamples() int {
	return coefficientLUT[h.version()][h.layer()] * 8
}

func (h *MPEGHeader) version() int {
	return int((h.Raw[1] & 0x18) >> 3)
}

func (h *MPEGHeader) layer() int {
	return int((h.Raw[1] & 0x06) >> 1)
}

func (h *MPEGHeader) bitrateIndex() int {
	return int((h.Raw[2] & 0xF0) >> 4)
}

func (h *MPEGHeader) sampleIndex() int {
	return int((h.Raw[2] & 0x0C) >> 2)
}

func (h *MPEGHeader) hasPadding() bool {
	return h.Raw[2]&0x01 == 1
}

func (h *MPEGHeader) isValid() bool {
	valid := h.Raw[0] == 0xFF &&
		h.Raw[1]&0xE0 == 0xE0 &&
		h.version() != 1 &&
		h.layer() != 0 &&
		h.Bitrate() != 0 &&
		h.SamplingRate() != 0

	return valid
}

func (h *MPEGHeader) frameSize() int {
	version := h.version()
	layer := h.layer()

	br := h.Bitrate()
	sr := h.SamplingRate()
	coeff := coefficientLUT[version][layer]
	pad := 0
	if h.hasPadding() {
		pad = paddingLUT[layer]
	}

	return ((coeff * br * 1000) / sr) + pad
}

type MPEGFrame struct {
	Header  MPEGHeader
	Payload []byte
}

func IsMPEGHeader(buf []byte) bool {
	if len(buf) < 3 {
		return false
	}

	h := MPEGHeader{Raw: buf}
	return h.isValid()
}
