-- /prismarine/lib/sha256.lua
-- Pure Lua SHA-256, the same code the installer uses. Yields now and then so
-- long files do not hit the timeout. Returns function(msg, tick) -> hex string.

local SHA_K = { 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 }
local SHA_H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local function hex32(n)
    local out = ""
    for _ = 1, 8 do
        local d = n % 16
        out = string.sub("0123456789abcdef", d + 1, d + 1) .. out
        n = (n - d) / 16
    end
    return out
end

-- SHA-256. Yields now and then so long files do not hit the timeout.
local function sha256(msg, tick)
    local band, bxor, bnot, bor = bit32.band, bit32.bxor, bit32.bnot, bit32.bor
    local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate
    local M = 4294967296

    local len = #msg
    local bits = len * 8
    local function u32(n)
        return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255),
                           band(rshift(n, 8), 255), band(n, 255))
    end
    msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
        .. u32(math.floor(bits / M)) .. u32(bits % M)

    local h = {}
    for n = 1, 8 do h[n] = SHA_H0[n] end
    local w = {}
    local blocks = 0

    for i = 1, #msg, 64 do
        local bytes = { string.byte(msg, i, i + 63) }
        for j = 1, 16 do
            local o = (j - 1) * 4
            w[j] = bor(lshift(bytes[o + 1], 24), lshift(bytes[o + 2], 16),
                       lshift(bytes[o + 3], 8), bytes[o + 4])
        end
        for j = 17, 64 do
            local v15, v2 = w[j - 15], w[j - 2]
            local s0 = bxor(rrotate(v15, 7), rrotate(v15, 18), rshift(v15, 3))
            local s1 = bxor(rrotate(v2, 17), rrotate(v2, 19), rshift(v2, 10))
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % M
        end

        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for j = 1, 64 do
            local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = (hh + S1 + ch + SHA_K[j] + w[j]) % M
            local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = (S0 + maj) % M
            hh = g
            g = f
            f = e
            e = (d + t1) % M
            d = c
            c = b
            b = a
            a = (t1 + t2) % M
        end
        h[1] = (h[1] + a) % M
        h[2] = (h[2] + b) % M
        h[3] = (h[3] + c) % M
        h[4] = (h[4] + d) % M
        h[5] = (h[5] + e) % M
        h[6] = (h[6] + f) % M
        h[7] = (h[7] + g) % M
        h[8] = (h[8] + hh) % M

        blocks = blocks + 1
        if blocks % 8 == 0 then
            os.queueEvent("simpleos_yield")
            os.pullEventRaw("simpleos_yield")
            if tick then tick() end
        end
    end

    local out = {}
    for n = 1, 8 do out[n] = hex32(h[n]) end
    return table.concat(out)
end

return sha256
