import serial
import struct
import numpy as np

# ---- CONFIG: change these two for your lab machine ----
PORT = "COM3"          # Windows: check Device Manager -> Ports. Linux: /dev/ttyUSB0
BAUD = 115200          # MUST match CLKS_PER_BIT in top.v (868 = 100MHz/115200)

N = 4                  # 4x4 matrices
IN_BYTES  = 2 * N * N * 2   # 2 matrices * 16 elems * 2 bytes  = 64
OUT_BYTES = N * N * 4       # 16 results * 4 bytes (32-bit)    = 64

def pack_matrix(M):
    """Flatten a 4x4 int16 matrix to bytes, row-major, big-endian per element."""
    out = bytearray()
    for i in range(N):
        for j in range(N):
            v = int(M[i][j]) & 0xFFFF          # 16-bit two's complement
            out.append((v >> 8) & 0xFF)        # high byte first
            out.append(v & 0xFF)               # then low byte
    return bytes(out)

# ---- your two input matrices (edit these) ----
A = np.array([[ 1, 2, 3, 4],
              [ 5, 6, 7, 8],
              [ 9,10,11,12],
              [13,14,15,16]], dtype=np.int64)
B = A.T.copy()                                 # B = A-transpose (the "counting" test)

stream = pack_matrix(A) + pack_matrix(B)
assert len(stream) == IN_BYTES, f"stream is {len(stream)} bytes, expected {IN_BYTES}"

# ---- open port, send, receive ----
ser = serial.Serial(PORT, baudrate=BAUD, timeout=5)
print(f"Sending {len(stream)} bytes (A then B)...")
ser.write(stream)

print(f"Waiting for {OUT_BYTES} bytes back...")
raw = ser.read(OUT_BYTES)
ser.close()

if len(raw) != OUT_BYTES:
    print(f"ERROR: got {len(raw)} bytes, expected {OUT_BYTES}. "
          f"Check baud rate, port, and that the FPGA is programmed.")
else:
    # 16 results, 32-bit signed, big-endian ('>i')
    results = struct.unpack('>' + 'i' * (N*N), raw)
    C_hw = np.array(results).reshape(N, N)
    print("Result from FPGA:")
    print(C_hw)
    # check against the laptop's own calculation
    C_ref = (A @ B)
    if np.array_equal(C_hw, C_ref):
        print("MATCH — hardware agrees with NumPy.")
    else:
        print("MISMATCH:\nexpected:\n", C_ref)