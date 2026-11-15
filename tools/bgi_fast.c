/*
 * BGI/Ethornell 阶段一资产高速校验与解码库 (CBG v1 像素解码 + Ogg Vorbis 全页 CRC32 校验)
 * 编译命令 (Windows MinGW/Clang):
 *   gcc -O3 -shared -Wall -Wextra -o bgi_fast.dll bgi_fast.c
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define BGI_API __declspec(dllexport)
#else
#define BGI_API
#endif

static inline uint8_t bgi_key_step(uint32_t *key) {
    uint32_t k = *key;
    uint32_t v0 = 20021u * (k & 0xFFFFu);
    uint32_t v1 = 20021u * (k >> 16) + 346u * (k & 0xFFFFu) + (v0 >> 16);
    *key = (((v1 & 0xFFFFu) << 16) + (v0 & 0xFFFFu) + 1u);
    return (uint8_t)(v1 & 0xFFu);
}

static inline uint32_t read_u16_le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8);
}

static inline uint32_t read_u32_le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline int64_t read_i64_le(const uint8_t *p) {
    uint64_t v = (uint64_t)read_u32_le(p) | ((uint64_t)read_u32_le(p + 4) << 32);
    return (int64_t)v;
}

static int read_varint(const uint8_t *buf, uint32_t len, uint32_t *pos, uint32_t *out_val) {
    uint32_t val = 0;
    uint32_t shift = 0;
    while (*pos < len) {
        uint8_t b = buf[(*pos)++];
        if (shift >= 32) {
            return -1;
        }
        val |= (uint32_t)(b & 0x7Fu) << shift;
        if ((b & 0x80u) == 0) {
            *out_val = val;
            return 0;
        }
        shift += 7;
    }
    return -1;
}

typedef struct {
    uint64_t weight;
    int32_t left;
    int32_t right;
    uint8_t valid;
} CbgNode;

#define LUT_BITS 12
#define LUT_SIZE (1 << LUT_BITS)

static void fill_lut(const CbgNode *nodes, int32_t node_idx, uint32_t prefix, int depth,
                     int32_t *lut_val, uint8_t *lut_len) {
    if (node_idx < 256) {
        if (depth == 0) {
            for (int i = 0; i < LUT_SIZE; i++) {
                lut_val[i] = node_idx;
                lut_len[i] = 0;
            }
            return;
        }
        int shift = LUT_BITS - depth;
        uint32_t base = prefix << shift;
        uint32_t fill = 1u << shift;
        for (uint32_t i = base; i < base + fill; i++) {
            lut_val[i] = node_idx;
            lut_len[i] = (uint8_t)depth;
        }
        return;
    }
    if (depth == LUT_BITS) {
        lut_val[prefix] = -(node_idx + 1);
        lut_len[prefix] = LUT_BITS;
        return;
    }
    fill_lut(nodes, nodes[node_idx].left, prefix << 1, depth + 1, lut_val, lut_len);
    fill_lut(nodes, nodes[node_idx].right, (prefix << 1) | 1u, depth + 1, lut_val, lut_len);
}

/*
 * 解码 CBG v1 图像到调用方提供的 out_buf。
 * 返回值:
 *   0  = 成功
 *  -1  = 头部或魔数非法
 *  -2  = 版本/色深不支持
 *  -3  = 频率表越界或校验和失败
 *  -4  = 频率表 varint 或总和异常
 *  -5  = 内存不足或输出缓冲太小
 *  -6  = RLE 解码越界或像素总字节数不匹配
 */
BGI_API int bgi_cbg_decode_v1(
    const uint8_t *data,
    uint32_t data_len,
    uint8_t *out_buf,
    uint32_t out_cap,
    uint32_t *out_w,
    uint32_t *out_h,
    uint32_t *out_bpp
) {
    static const uint8_t MAGIC[16] = "CompressedBG___\x00";
    if (!data || data_len < 48 || memcmp(data, MAGIC, 16) != 0) {
        return -1;
    }

    uint32_t w = read_u16_le(data + 16);
    uint32_t h = read_u16_le(data + 18);
    uint32_t bpp = read_u32_le(data + 20);
    uint32_t rle_size = read_u32_le(data + 32);
    uint32_t key = read_u32_le(data + 36);
    uint32_t enc_len = read_u32_le(data + 40);
    uint8_t sum_check = data[44];
    uint8_t xor_check = data[45];
    uint32_t version = read_u16_le(data + 46);

    if (out_w) *out_w = w;
    if (out_h) *out_h = h;
    if (out_bpp) *out_bpp = bpp;

    if (version != 1 || (bpp != 8 && bpp != 24 && bpp != 32)) {
        return -2;
    }
    if ((uint64_t)48 + enc_len > data_len || enc_len == 0) {
        return -3;
    }

    uint64_t bpp_bytes = bpp / 8;
    uint64_t raw_len64 = (uint64_t)w * (uint64_t)h * bpp_bytes;
    if (!out_buf || raw_len64 > out_cap) {
        return -5;
    }
    uint32_t raw_len = (uint32_t)raw_len64;

    /* 1. 解密频率表并校验和 */
    uint8_t *dec_freq = (uint8_t *)malloc(enc_len);
    if (!dec_freq) {
        return -5;
    }
    uint32_t k = key;
    uint8_t s_acc = 0;
    uint8_t x_acc = 0;
    for (uint32_t i = 0; i < enc_len; i++) {
        uint8_t kb = bgi_key_step(&k);
        uint8_t b = (uint8_t)(data[48 + i] - kb);
        dec_freq[i] = b;
        s_acc = (uint8_t)(s_acc + b);
        x_acc ^= b;
    }
    if (s_acc != sum_check || x_acc != xor_check) {
        free(dec_freq);
        return -3;
    }

    /* 2. 解析 256 个符号频率 */
    CbgNode nodes[512];
    memset(nodes, 0, sizeof(nodes));
    uint32_t fpos = 0;
    uint64_t total_freq = 0;
    for (int i = 0; i < 256; i++) {
        uint32_t freq = 0;
        if (read_varint(dec_freq, enc_len, &fpos, &freq) != 0) {
            free(dec_freq);
            return -4;
        }
        nodes[i].weight = freq;
        nodes[i].valid = (freq > 0) ? 1 : 0;
        nodes[i].left = -1;
        nodes[i].right = -1;
        total_freq += freq;
    }
    free(dec_freq);

    if (total_freq == 0 || fpos != enc_len) {
        return -4;
    }

    /* 3. 构建 BGI 霍夫曼树 */
    int32_t node_count = 256;
    int32_t root = 0;
    for (;;) {
        int32_t min1_idx = -1, min2_idx = -1;
        uint64_t min1_w = UINT64_MAX, min2_w = UINT64_MAX;
        for (int32_t idx = 0; idx < node_count; idx++) {
            if (!nodes[idx].valid) continue;
            uint64_t wn = nodes[idx].weight;
            if (wn < min1_w) {
                min2_idx = min1_idx;
                min2_w = min1_w;
                min1_idx = idx;
                min1_w = wn;
            } else if (wn < min2_w) {
                min2_idx = idx;
                min2_w = wn;
            }
        }
        if (min2_idx == -1) {
            root = min1_idx;
            break;
        }
        nodes[min1_idx].valid = 0;
        nodes[min2_idx].valid = 0;
        int32_t new_idx = node_count++;
        nodes[new_idx].weight = min1_w + min2_w;
        nodes[new_idx].valid = 1;
        nodes[new_idx].left = min1_idx;
        nodes[new_idx].right = min2_idx;
        if (nodes[new_idx].weight == total_freq) {
            root = new_idx;
            break;
        }
    }

    /* 4. 填充 12-bit 霍夫曼前缀查找表 */
    int32_t lut_val[LUT_SIZE];
    uint8_t lut_len[LUT_SIZE];
    fill_lut(nodes, root, 0, 0, lut_val, lut_len);

    /* 5. 解码霍夫曼比特流 -> rle_buf */
    uint8_t *rle_buf = (uint8_t *)malloc(rle_size ? rle_size : 1);
    if (!rle_buf) {
        return -5;
    }
    uint32_t bs_pos = 48 + enc_len;
    uint32_t bit_buf = 0;
    int bits_left = 0;
    const uint32_t mask_table = LUT_SIZE - 1;

    for (uint32_t i = 0; i < rle_size; i++) {
        while (bits_left < LUT_BITS && bs_pos < data_len) {
            bit_buf = (bit_buf << 8) | data[bs_pos++];
            bits_left += 8;
        }
        uint32_t idx;
        if (bits_left >= LUT_BITS) {
            idx = (bit_buf >> (bits_left - LUT_BITS)) & mask_table;
        } else {
            idx = (bit_buf << (LUT_BITS - bits_left)) & mask_table;
        }
        int32_t val = lut_val[idx];
        if (val >= 0) {
            int need_bits = lut_len[idx];
            if (bits_left < need_bits) {
                free(rle_buf);
                return -6;
            }
            bits_left -= need_bits;
            if (bits_left > 0) {
                bit_buf &= (1u << bits_left) - 1u;
            } else {
                bit_buf = 0;
            }
            rle_buf[i] = (uint8_t)val;
        } else {
            if (bits_left < LUT_BITS) {
                free(rle_buf);
                return -6;
            }
            int32_t cur = (-val) - 1;
            bits_left -= LUT_BITS;
            if (bits_left > 0) {
                bit_buf &= (1u << bits_left) - 1u;
            } else {
                bit_buf = 0;
            }
            while (cur >= 256) {
                if (bits_left == 0) {
                    if (bs_pos >= data_len) {
                        free(rle_buf);
                        return -6;
                    }
                    bit_buf = data[bs_pos++];
                    bits_left = 8;
                }
                bits_left -= 1;
                uint32_t bit = (bit_buf >> bits_left) & 1u;
                if (bits_left > 0) {
                    bit_buf &= (1u << bits_left) - 1u;
                } else {
                    bit_buf = 0;
                }
                cur = bit ? nodes[cur].right : nodes[cur].left;
            }
            rle_buf[i] = (uint8_t)cur;
        }
    }

    /* 6. 零游程 RLE 解码 */
    memset(out_buf, 0, raw_len);
    uint32_t src_i = 0;
    uint32_t dst_i = 0;
    int zero_flag = 0;
    while (src_i < rle_size && dst_i < raw_len) {
        uint32_t cnt = 0;
        if (read_varint(rle_buf, rle_size, &src_i, &cnt) != 0) {
            free(rle_buf);
            return -6;
        }
        if (dst_i + cnt > raw_len) {
            cnt = raw_len - dst_i;
        }
        if (!zero_flag) {
            if ((uint64_t)src_i + cnt > rle_size) {
                free(rle_buf);
                return -6;
            }
            memcpy(out_buf + dst_i, rle_buf + src_i, cnt);
            src_i += cnt;
        }
        dst_i += cnt;
        zero_flag = !zero_flag;
    }
    free(rle_buf);

    if (dst_i != raw_len) {
        return -6;
    }

    /* 7. 逆向空间差分预测滤波 */
    uint32_t stride = w * (uint32_t)bpp_bytes;
    uint32_t bb = (uint32_t)bpp_bytes;
    if (h > 0 && stride > 0) {
        for (uint32_t x = bb; x < stride; x++) {
            out_buf[x] = (uint8_t)(out_buf[x] + out_buf[x - bb]);
        }
        for (uint32_t y = 1; y < h; y++) {
            uint8_t *row = out_buf + (size_t)y * stride;
            const uint8_t *prev = row - stride;
            for (uint32_t c = 0; c < bb; c++) {
                row[c] = (uint8_t)(row[c] + prev[c]);
            }
            for (uint32_t x = bb; x < stride; x++) {
                uint32_t avg = ((uint32_t)row[x - bb] + (uint32_t)prev[x]) >> 1;
                row[x] = (uint8_t)(row[x] + avg);
            }
        }
    }

    return 0;
}

/* ---------------- Ogg Vorbis 全页 CRC32 & 头包校验 ---------------- */

static uint32_t ogg_crc_table[256];
static int ogg_crc_ready = 0;

static void init_ogg_crc_table(void) {
    if (ogg_crc_ready) return;
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t r = i << 24;
        for (int j = 0; j < 8; j++) {
            if (r & 0x80000000u) {
                r = (r << 1) ^ 0x04C11DB7u;
            } else {
                r <<= 1;
            }
        }
        ogg_crc_table[i] = r;
    }
    ogg_crc_ready = 1;
}

static uint32_t ogg_page_crc32(const uint8_t *page, uint32_t page_len) {
    init_ogg_crc_table();
    uint32_t crc = 0;
    for (uint32_t i = 0; i < page_len; i++) {
        uint8_t b = (i >= 22 && i < 26) ? 0u : page[i];
        crc = (crc << 8) ^ ogg_crc_table[((crc >> 24) & 0xFFu) ^ b];
    }
    return crc;
}

/*
 * 校验完整 Ogg Vorbis 流的每页 OggS 魔数、CRC32、Vorbis 三头包及 EOS 标志。
 * 返回值:
 *   0 = 全部校验通过
 *  -1 = 输入为空或起始非 OggS
 *  -2 = 页头/segment 越界或页同步丢失
 *  -3 = Ogg Page CRC32 校验失败
 *  -4 = 缺少 Vorbis 头包 (\x01/\x03/\x05 vorbis) 或 version != 0
 *  -5 = 末尾未对齐或缺少 EOS (0x04)
 */
BGI_API int bgi_ogg_validate_stream(
    const uint8_t *data,
    uint32_t data_len,
    uint32_t *out_pages,
    uint32_t *out_channels,
    uint32_t *out_sample_rate,
    uint32_t *out_has_eos,
    int64_t *out_last_granule
) {
    if (!data || data_len < 27 || memcmp(data, "OggS", 4) != 0) {
        return -1;
    }

    uint32_t pos = 0;
    uint32_t pages = 0;
    uint8_t last_flags = 0;
    int64_t last_granule = 0;
    int has_id = 0, has_comment = 0, has_setup = 0;
    uint32_t ch = 0, sr = 0;

    while (pos + 27 <= data_len) {
        if (memcmp(data + pos, "OggS", 4) != 0) {
            return -2;
        }
        uint8_t flags = data[pos + 5];
        int64_t granule = read_i64_le(data + pos + 6);
        uint32_t expected_crc = read_u32_le(data + pos + 22);
        uint32_t nseg = data[pos + 26];
        if (pos + 27 + nseg > data_len) {
            return -2;
        }
        uint32_t body_len = 0;
        for (uint32_t i = 0; i < nseg; i++) {
            body_len += data[pos + 27 + i];
        }
        uint32_t page_len = 27 + nseg + body_len;
        if (pos + page_len > data_len) {
            return -2;
        }

        uint32_t actual_crc = ogg_page_crc32(data + pos, page_len);
        if (actual_crc != expected_crc) {
            return -3;
        }

        /* 检查前几页中的 Vorbis 3 个头包 */
        if (pages < 8) {
            const uint8_t *body = data + pos + 27 + nseg;
            for (uint32_t j = 0; j + 7 <= body_len; j++) {
                if (memcmp(body + j + 1, "vorbis", 6) == 0) {
                    uint8_t ptype = body[j];
                    if (ptype == 1 && !has_id && j + 16 <= body_len) {
                        uint32_t ver = read_u32_le(body + j + 7);
                        if (ver != 0) {
                            return -4;
                        }
                        ch = body[j + 11];
                        sr = read_u32_le(body + j + 12);
                        has_id = 1;
                    } else if (ptype == 3) {
                        has_comment = 1;
                    } else if (ptype == 5) {
                        has_setup = 1;
                    }
                }
            }
        }

        pages++;
        last_flags = flags;
        if (granule >= 0) {
            last_granule = granule;
        }
        pos += page_len;
    }

    if (pos != data_len || (last_flags & 0x04u) == 0) {
        if (out_pages) *out_pages = pages;
        if (out_has_eos) *out_has_eos = (last_flags & 0x04u) ? 1u : 0u;
        return -5;
    }
    if (!has_id || !has_comment || !has_setup) {
        return -4;
    }

    if (out_pages) *out_pages = pages;
    if (out_channels) *out_channels = ch;
    if (out_sample_rate) *out_sample_rate = sr;
    if (out_has_eos) *out_has_eos = 1u;
    if (out_last_granule) *out_last_granule = last_granule;
    return 0;
}
