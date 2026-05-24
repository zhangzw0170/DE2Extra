#!/usr/bin/env python3
"""ntt_verify.py — Verify NTT/INTT correctness for ntt_sdf.vhd

Usage: python3 ntt_verify.py

Algorithm: DIF Cooley-Tukey with unified butterfly (A+B, (A-B)*w).
  Forward: stages 7→0, produces bit-reversed output.
  Inverse: stages 7→0, inverse twiddles, N^{-1} scaling, bit-reversed output.
  Bit-reversal is done in software (not hardware).

Constants: q=3329, N=256, g=17, Barrett=5039, N^{-1}=3316.
"""

q = 3329; N = 256; BARRETT = 5039

tw = [pow(17, k, q) for k in range(128)]

def barrett(x):
    qe = (x * BARRETT) >> 24; r = x - qe * q
    if r >= q: r -= q
    return r

def bit_rev(x, bits):
    r = 0
    for _ in range(bits): r = (r << 1) | (x & 1); x >>= 1
    return r

def ntt_hw(data, inverse=False):
    """Matches ntt_sdf.vhd engine exactly (no bit-reversal)."""
    buf = list(data)
    for s in range(7, -1, -1):
        half = 1 << s
        for b in range(128):
            grp = b // half; idx = b % half
            top = grp * 2 * half + idx; bot = top + half
            tw_idx = idx * (128 // half)
            tw_val = tw[tw_idx]
            if inverse and tw_idx > 0: tw_val = q - tw[128 - tw_idx]
            a, bv = buf[top], buf[bot]
            sv = a + bv
            if sv >= q: sv -= q
            dv = a - bv + q
            if dv >= q: dv -= q
            buf[top] = sv; buf[bot] = barrett(dv * tw_val)
    if inverse:
        for i in range(256): buf[i] = barrett(buf[i] * 3316)
    return buf

def ntt(data, inverse=False):
    """HW engine + bit-reversal for natural-order input/output."""
    buf = ntt_hw(data, inverse)
    out = [0] * N
    for i in range(N): out[bit_rev(i, 8)] = buf[i]
    return out

if __name__ == '__main__':
    import random; random.seed(42)
    print(f"q={q} N={N} g=17 Barrett={BARRETT} N^-1={pow(256,-1,q)}")
    print(f"g^128 mod q = {pow(17,128,q)} (expect {q-1})\n")

    ok = True

    # Test 1: round-trip
    data = [random.randint(0, q-1) for _ in range(N)]
    back = ntt(ntt(data), inverse=True)
    e = max(abs(back[i]-data[i]) for i in range(N))
    print(f"1. Round-trip:  {'PASS' if e==0 else 'FAIL'} (err={e})"); ok &= (e==0)

    # Test 2: delta → all ones
    delta = [0]*N; delta[0] = 1
    r = ntt(delta)
    e = max(abs(r[i]-1) for i in range(N))
    print(f"2. Delta NTT:   {'PASS' if e==0 else 'FAIL'} (err={e})"); ok &= (e==0)

    # Test 3: convolution
    a = [random.randint(0, q-1) for _ in range(N)]
    b = [random.randint(0, q-1) for _ in range(N)]
    c = ntt([barrett(ntt(a)[i]*ntt(b)[i]) for i in range(N)], inverse=True)
    c_ref = [0]*N
    for i in range(N):
        for j in range(N): c_ref[(i+j)%N] = (c_ref[(i+j)%N]+a[i]*b[j])%q
    e = max(abs(c[i]-c_ref[i]) for i in range(N))
    print(f"3. Convolution: {'PASS' if e==0 else 'FAIL'} (err={e})"); ok &= (e==0)

    # Test 4: vs naive DFT
    small = list(range(N))
    fwd = ntt(small)
    ref = [sum(small[j]*pow(17,(j*k)%256,q)%q for j in range(N))%q for k in range(N)]
    e = max(abs(fwd[i]-ref[i]) for i in range(N))
    print(f"4. Vs naive:    {'PASS' if e==0 else 'FAIL'} (err={e})"); ok &= (e==0)

    print(f"\n{'All tests PASSED' if ok else 'Some tests FAILED'}")
