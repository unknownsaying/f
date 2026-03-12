{.passC: "-O3 -march=native".}  # Pass optimization flags to C compiler
{.passL: "-pthread".}  # Link with pthreads

# SIMD optimization for image processing
proc processScreenData*(data: var openarray[byte]) {.inline.} =
  ## Process screen capture data with SIMD optimization
  when defined(avx2):
    # Use AVX2 instructions when available
    {.emit: """
    __m256i* vec = (__m256i*)(void*)data->data;
    for (int i = 0; i < data->len / 32; i++) {
      vec[i] = _mm256_add_epi8(vec[i], _mm256_set1_epi8(128));
    }
    """.}
  else:
    # Fallback to portable code
    for i in 0..<data.len:
      data[i] = data[i] + 128

# Zero-copy network buffers
type
  PacketBuffer = object
    data: array[65536, byte]
    len: int
    
  PacketView = object
    buffer: ptr PacketBuffer
    offset: int
    length: int

# Hardware-accelerated crypto for secure communication
proc encryptPacket*(buffer: var PacketBuffer) {.importc: "aes_encrypt", cdecl.}

# Direct hardware access when needed
when defined(linux):
  proc setRealtimePriority*() =
    ## Set real-time scheduler priority
    {.emit: """
    #include <sched.h>
    struct sched_param param;
    param.sched_priority = 99;
    sched_setscheduler(0, SCHED_FIFO, &param);
    """.}

# Cache-friendly data structures
type
  HandSlot = object
    id: uint32
    state: uint8
    padding: array[3, uint8]  # Explicit padding for cache alignment
    position: array[2, float]
    lastUpdate: int64

# Compile-time computation
const MAX_HANDS = 100
const SESSION_TIMEOUT = 30000'i64  # Milliseconds

# Inline assembly for critical sections
proc atomicIncrement*(counter: ptr int32) {.inline.} =
  ## Thread-safe atomic increment
  when defined(cpu64):
    {.emit: "lock incq `counter`;".}
  else:
    {.emit: "lock incl `counter`;".}