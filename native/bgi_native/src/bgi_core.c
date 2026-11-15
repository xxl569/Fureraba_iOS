/*
 * BGI/Ethornell 原生协议解码核心 (ARC v1/v2, DSC 1.00, SDC 1.00, CBG v1, BMP, bw+Ogg)
 * 纯 C11 零外部依赖实现，同时支持 Windows x86_64 DLL 与 iOS arm64 静态库。
 */

#include "bgi_core.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dirent.h>
#endif

static inline uint16_t read_u16_le(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static inline uint32_t read_u32_le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline int32_t read_i32_le(const uint8_t *p) {
    return (int32_t)read_u32_le(p);
}

static inline uint8_t bgi_key_step(uint32_t *key) {
    uint32_t k = *key;
    uint32_t v0 = 20021u * (k & 0xFFFFu);
    uint32_t v1 = 20021u * (k >> 16) + 346u * (k & 0xFFFFu) + (v0 >> 16);
    *key = (((v1 & 0xFFFFu) << 16) + (v0 & 0xFFFFu) + 1u);
    return (uint8_t)(v1 & 0xFFu);
}

static char *dup_lower_ascii(const char *s, size_t *out_len) {
    size_t n = strlen(s);
    char *dst = (char *)malloc(n + 1);
    if (!dst) return NULL;
    for (size_t i = 0; i < n; i++) {
        dst[i] = (char)tolower((unsigned char)s[i]);
    }
    dst[n] = '\0';
    if (out_len) *out_len = n;
    return dst;
}

static char *dup_str(const char *s) {
    size_t n = strlen(s);
    char *dst = (char *)malloc(n + 1);
    if (!dst) return NULL;
    memcpy(dst, s, n + 1);
    return dst;
}

static uint32_t fnv1a_lower(const char *s) {
    uint32_t h = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        h ^= (uint32_t)tolower(*p);
        h *= 16777619u;
    }
    return h;
}

static int ci_strcasecmp(const char *a, const char *b) {
    for (;;) {
        int ca = tolower((unsigned char)*a);
        int cb = tolower((unsigned char)*b);
        if (ca != cb) return ca - cb;
        if (ca == 0) return 0;
        a++;
        b++;
    }
}

static FILE *open_rb_utf8(const char *path_utf8) {
#ifdef _WIN32
    int wlen = MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, NULL, 0);
    if (wlen <= 0) return NULL;
    wchar_t *wpath = (wchar_t *)malloc((size_t)wlen * sizeof(wchar_t));
    if (!wpath) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, wlen);
    FILE *fp = _wfopen(wpath, L"rb");
    free(wpath);
    return fp;
#else
    return fopen(path_utf8, "rb");
#endif
}

static int file_exists_utf8(const char *path_utf8) {
    FILE *fp = open_rb_utf8(path_utf8);
    if (fp) {
        fclose(fp);
        return 1;
    }
    return 0;
}

/* ==================== VFS 初始化与归档挂载 ==================== */

void bgi_vfs_init(BgiVfsState *vfs) {
    memset(vfs, 0, sizeof(*vfs));
}

void bgi_vfs_free(BgiVfsState *vfs) {
    if (!vfs) return;
    for (uint32_t i = 0; i < vfs->archive_count; i++) {
        free(vfs->archives[i].path);
    }
    free(vfs->archives);
    for (uint32_t i = 0; i < vfs->entry_count; i++) {
        free(vfs->entries[i].name);
        free(vfs->entries[i].lower_name);
    }
    free(vfs->entries);
    free(vfs->buckets);
    memset(vfs, 0, sizeof(*vfs));
}

void bgi_free_buffer(void *p) {
    free(p);
}

static int rehash_buckets(BgiVfsState *vfs, uint32_t new_cap) {
    int32_t *nb = (int32_t *)malloc((size_t)new_cap * sizeof(int32_t));
    if (!nb) return -1;
    for (uint32_t i = 0; i < new_cap; i++) nb[i] = -1;
    uint32_t mask = new_cap - 1u;
    for (uint32_t i = 0; i < vfs->entry_count; i++) {
        uint32_t slot = vfs->entries[i].hash & mask;
        while (nb[slot] != -1) {
            slot = (slot + 1u) & mask;
        }
        nb[slot] = (int32_t)i;
    }
    free(vfs->buckets);
    vfs->buckets = nb;
    vfs->bucket_cap = new_cap;
    return 0;
}

static int add_vfs_entry(BgiVfsState *vfs, const char *name, int32_t archive_idx, uint32_t offset, uint32_t size) {
    if (vfs->entry_count * 2u >= vfs->bucket_cap) {
        uint32_t next_cap = vfs->bucket_cap ? vfs->bucket_cap * 2u : 1024u;
        if (rehash_buckets(vfs, next_cap) != 0) return -1;
    }
    char *lower = dup_lower_ascii(name, NULL);
    if (!lower) return -1;
    uint32_t h = fnv1a_lower(lower);
    uint32_t mask = vfs->bucket_cap - 1u;
    uint32_t slot = h & mask;
    while (vfs->buckets[slot] != -1) {
        int32_t idx = vfs->buckets[slot];
        if (vfs->entries[idx].hash == h && strcmp(vfs->entries[idx].lower_name, lower) == 0) {
            /* 已挂载同名高优先级条目，保留首次命中 */
            free(lower);
            return 0;
        }
        slot = (slot + 1u) & mask;
    }
    if (vfs->entry_count == vfs->entry_cap) {
        uint32_t ncap = vfs->entry_cap ? vfs->entry_cap * 2u : 512u;
        BgiEntry *ne = (BgiEntry *)realloc(vfs->entries, (size_t)ncap * sizeof(BgiEntry));
        if (!ne) {
            free(lower);
            return -1;
        }
        vfs->entries = ne;
        vfs->entry_cap = ncap;
    }
    char *orig = dup_str(name);
    if (!orig) {
        free(lower);
        return -1;
    }
    uint32_t new_idx = vfs->entry_count++;
    vfs->entries[new_idx].hash = h;
    vfs->entries[new_idx].archive_idx = archive_idx;
    vfs->entries[new_idx].offset = offset;
    vfs->entries[new_idx].size = size;
    vfs->entries[new_idx].name = orig;
    vfs->entries[new_idx].lower_name = lower;
    vfs->buckets[slot] = (int32_t)new_idx;
    return 0;
}

static int mount_single_arc(BgiVfsState *vfs, const char *arc_path) {
    FILE *fp = open_rb_utf8(arc_path);
    if (!fp) return -1;

    uint8_t hdr[16];
    if (fread(hdr, 1, 16, fp) != 16) {
        fclose(fp);
        return -1;
    }

    int is_v2 = 0;
    if (memcmp(hdr, "PackFile    ", 12) == 0) {
        is_v2 = 0;
    } else if (memcmp(hdr, "BURIKO ARC20", 12) == 0) {
        is_v2 = 1;
    } else {
        fclose(fp);
        return -2;
    }

    uint32_t count = read_u32_le(hdr + 12);
    uint32_t rec_size = is_v2 ? 128u : 32u;
    uint32_t name_len = is_v2 ? 96u : 16u;
    uint64_t data_base = 16ull + (uint64_t)count * (uint64_t)rec_size;

    if (vfs->archive_count == vfs->archive_cap) {
        uint32_t acap = vfs->archive_cap ? vfs->archive_cap * 2u : 64u;
        BgiArchive *na = (BgiArchive *)realloc(vfs->archives, (size_t)acap * sizeof(BgiArchive));
        if (!na) {
            fclose(fp);
            return -3;
        }
        vfs->archives = na;
        vfs->archive_cap = acap;
    }
    int32_t arc_idx = (int32_t)vfs->archive_count++;
    vfs->archives[arc_idx].path = dup_str(arc_path);
    vfs->archives[arc_idx].is_v2 = (uint8_t)is_v2;

    uint8_t *table = (uint8_t *)malloc((size_t)count * rec_size);
    if (!table && count > 0) {
        fclose(fp);
        return -3;
    }
    if (count > 0 && fread(table, rec_size, count, fp) != count) {
        free(table);
        fclose(fp);
        return -4;
    }
    fclose(fp);

    char name_buf[128];
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *rec = table + (size_t)i * rec_size;
        size_t slen = 0;
        while (slen < name_len && rec[slen] != 0) {
            name_buf[slen] = (char)rec[slen];
            slen++;
        }
        name_buf[slen] = '\0';
        uint32_t rel_off = read_u32_le(rec + name_len);
        uint32_t sz = read_u32_le(rec + name_len + 4);
        if (add_vfs_entry(vfs, name_buf, arc_idx, (uint32_t)(data_base + rel_off), sz) != 0) {
            free(table);
            return -5;
        }
    }
    free(table);
    return 0;
}

typedef struct {
    char **items;
    uint32_t count;
    uint32_t cap;
} StrList;

static void strlist_push(StrList *lst, const char *s) {
    if (lst->count == lst->cap) {
        uint32_t nc = lst->cap ? lst->cap * 2u : 64u;
        char **ni = (char **)realloc(lst->items, (size_t)nc * sizeof(char *));
        if (!ni) return;
        lst->items = ni;
        lst->cap = nc;
    }
    lst->items[lst->count++] = dup_str(s);
}

static void strlist_free(StrList *lst) {
    for (uint32_t i = 0; i < lst->count; i++) free(lst->items[i]);
    free(lst->items);
}

static int cmp_str_ci(const void *a, const void *b) {
    const char *sa = *(const char *const *)a;
    const char *sb = *(const char *const *)b;
    return ci_strcasecmp(sa, sb);
}

static void scan_archive_dir(const char *arch_dir, StrList *out_names) {
#ifdef _WIN32
    size_t len = strlen(arch_dir);
    char *pat = (char *)malloc(len + 8);
    if (!pat) return;
    snprintf(pat, len + 8, "%s\\*", arch_dir);
    int wlen = MultiByteToWideChar(CP_UTF8, 0, pat, -1, NULL, 0);
    wchar_t *wpat = (wchar_t *)malloc((size_t)wlen * sizeof(wchar_t));
    if (wpat) {
        MultiByteToWideChar(CP_UTF8, 0, pat, -1, wpat, wlen);
        WIN32_FIND_DATAW fd;
        HANDLE h = FindFirstFileW(wpat, &fd);
        if (h != INVALID_HANDLE_VALUE) {
            do {
                if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
                int ulen = WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, NULL, 0, NULL, NULL);
                if (ulen > 0) {
                    char *uname = (char *)malloc((size_t)ulen);
                    if (uname) {
                        WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, uname, ulen, NULL, NULL);
                        strlist_push(out_names, uname);
                        free(uname);
                    }
                }
            } while (FindNextFileW(h, &fd));
            FindClose(h);
        }
        free(wpat);
    }
    free(pat);
#else
    DIR *d = opendir(arch_dir);
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        strlist_push(out_names, ent->d_name);
    }
    closedir(d);
#endif
}

static int ends_with_ci(const char *s, const char *suf) {
    size_t ls = strlen(s), lf = strlen(suf);
    if (ls < lf) return 0;
    return ci_strcasecmp(s + ls - lf, suf) == 0;
}

int32_t bgi_vfs_mount(BgiVfsState *vfs, const char *dir_utf8, int uncensored_mode) {
    bgi_vfs_free(vfs);
    bgi_vfs_init(vfs);
    if (!dir_utf8 || !*dir_utf8) return -1;

    size_t dlen = strlen(dir_utf8);
    char *clean_dir = dup_str(dir_utf8);
    if (!clean_dir) return -2;
    while (dlen > 0 && (clean_dir[dlen - 1] == '/' || clean_dir[dlen - 1] == '\\')) {
        clean_dir[--dlen] = '\0';
    }

    char path_buf[2048];
    const char *root_arcs[] = {"sysprg2.arc", "sysprg.arc", "system.arc", "sysgrp.arc"};
    for (size_t i = 0; i < 4; i++) {
        snprintf(path_buf, sizeof(path_buf), "%s/%s", clean_dir, root_arcs[i]);
        if (file_exists_utf8(path_buf)) {
            mount_single_arc(vfs, path_buf);
        }
    }

    /* 探测 Archive 或 archive 目录 */
    char arch_dir[2048];
    snprintf(arch_dir, sizeof(arch_dir), "%s/Archive", clean_dir);
    StrList files = {0};
    scan_archive_dir(arch_dir, &files);
    if (files.count == 0) {
        snprintf(arch_dir, sizeof(arch_dir), "%s/archive", clean_dir);
        scan_archive_dir(arch_dir, &files);
    }

    if (files.count > 0) {
        /* 筛选 data*.arc 与可选 data02150.arc.bak */
        StrList arcs = {0};
        int has_2150_arc = 0;
        for (uint32_t i = 0; i < files.count; i++) {
            if (ci_strcasecmp(files.items[i], "data02150.arc") == 0) {
                has_2150_arc = 1;
            }
        }
        for (uint32_t i = 0; i < files.count; i++) {
            const char *fn = files.items[i];
            if (ends_with_ci(fn, ".arc")) {
                if (!uncensored_mode && ci_strcasecmp(fn, "data02150.arc") == 0) {
                    continue;
                }
                strlist_push(&arcs, fn);
            } else if (uncensored_mode && !has_2150_arc && ci_strcasecmp(fn, "data02150.arc.bak") == 0) {
                strlist_push(&arcs, fn);
            }
        }
        if (arcs.count > 1) {
            qsort(arcs.items, arcs.count, sizeof(char *), cmp_str_ci);
        }
        for (uint32_t i = 0; i < arcs.count; i++) {
            snprintf(path_buf, sizeof(path_buf), "%s/%s", arch_dir, arcs.items[i]);
            mount_single_arc(vfs, path_buf);
        }
        strlist_free(&arcs);
    }
    strlist_free(&files);
    free(clean_dir);
    return (int32_t)vfs->entry_count;
}

const BgiEntry *bgi_vfs_find_entry(const BgiVfsState *vfs, const char *name_utf8) {
    if (!vfs || !vfs->buckets || !name_utf8) return NULL;
    char *lower = dup_lower_ascii(name_utf8, NULL);
    if (!lower) return NULL;
    uint32_t h = fnv1a_lower(lower);
    uint32_t mask = vfs->bucket_cap - 1u;
    uint32_t slot = h & mask;
    while (vfs->buckets[slot] != -1) {
        int32_t idx = vfs->buckets[slot];
        if (vfs->entries[idx].hash == h && strcmp(vfs->entries[idx].lower_name, lower) == 0) {
            free(lower);
            return &vfs->entries[idx];
        }
        slot = (slot + 1u) & mask;
    }
    free(lower);
    return NULL;
}

int bgi_vfs_has_entry(const BgiVfsState *vfs, const char *name_utf8) {
    return bgi_vfs_find_entry(vfs, name_utf8) != NULL;
}

/* ==================== DSC / SDC / CBG / BMP / bw 解码 ==================== */

static int decode_dsc_buf(const uint8_t *data, uint32_t data_len, uint8_t **out_buf, uint32_t *out_len) {
    static const uint8_t MAGIC[16] = "DSC FORMAT 1.00\x00";
    if (!data || data_len < 544 || memcmp(data, MAGIC, 16) != 0) return -1;

    uint32_t key = read_u32_le(data + 16);
    uint32_t uncomp_size = read_u32_le(data + 20);
    uint32_t dec_count = read_u32_le(data + 24);
    if (uncomp_size == 0 || dec_count == 0) {
        *out_buf = (uint8_t *)malloc(1);
        *out_len = 0;
        return 0;
    }
    if (dec_count > uncomp_size) return -2;

    typedef struct { uint16_t depth; uint16_t sym; } SymLen;
    SymLen list[512];
    int list_n = 0;
    uint32_t k = key;
    for (int sym = 0; sym < 512; sym++) {
        uint8_t kb = bgi_key_step(&k);
        uint8_t d = (uint8_t)(data[32 + sym] - kb);
        if (d > 0) {
            list[list_n].depth = d;
            list[list_n].sym = (uint16_t)sym;
            list_n++;
        }
    }
    if (list_n == 0) return -3;

    /* 按 (depth, sym) 插入排序 */
    for (int i = 1; i < list_n; i++) {
        SymLen tmp = list[i];
        int j = i - 1;
        while (j >= 0 && (list[j].depth > tmp.depth || (list[j].depth == tmp.depth && list[j].sym > tmp.sym))) {
            list[j + 1] = list[j];
            j--;
        }
        list[j + 1] = tmp;
    }

    int max_depth = list[list_n - 1].depth;
    if (max_depth > 31) return -3;
    int table_bits = max_depth < 12 ? max_depth : 12;
    uint32_t table_size = 1u << table_bits;

    int32_t lut_sym[4096];
    uint8_t lut_len[4096];
    for (uint32_t i = 0; i < table_size; i++) {
        lut_sym[i] = -1;
        lut_len[i] = 0;
    }

    typedef struct { int32_t left; int32_t right; int32_t sym; } TrieNode;
    TrieNode *trie = (TrieNode *)malloc(4096 * sizeof(TrieNode));
    if (!trie) return -4;
    int trie_cap = 4096;
    int trie_n = 1;
    trie[0].left = -1;
    trie[0].right = -1;
    trie[0].sym = -1;

    uint32_t code = 0;
    int prev_d = 0;
    for (int i = 0; i < list_n; i++) {
        int d = list[i].depth;
        uint16_t sym = list[i].sym;
        code <<= (d - prev_d);
        prev_d = d;
        if (code >= (1u << d)) {
            free(trie);
            return -3;
        }
        if (d <= table_bits) {
            int shift = table_bits - d;
            uint32_t base = code << shift;
            uint32_t fill = 1u << shift;
            for (uint32_t j = 0; j < fill; j++) {
                lut_sym[base + j] = (int32_t)sym;
                lut_len[base + j] = (uint8_t)d;
            }
        } else {
            int cur = 0;
            for (int bpos = d - 1; bpos >= 0; bpos--) {
                int bit = (int)((code >> bpos) & 1u);
                int *next_ptr = bit ? &trie[cur].right : &trie[cur].left;
                if (*next_ptr == -1) {
                    if (trie_n == trie_cap) {
                        trie_cap *= 2;
                        TrieNode *nt = (TrieNode *)realloc(trie, (size_t)trie_cap * sizeof(TrieNode));
                        if (!nt) { free(trie); return -4; }
                        trie = nt;
                        next_ptr = bit ? &trie[cur].right : &trie[cur].left;
                    }
                    int nid = trie_n++;
                    trie[nid].left = -1;
                    trie[nid].right = -1;
                    trie[nid].sym = -1;
                    *next_ptr = nid;
                }
                cur = *next_ptr;
                if (bpos == 0) {
                    trie[cur].sym = (int32_t)sym;
                }
            }
        }
        code++;
    }

    uint8_t *out = (uint8_t *)malloc(uncomp_size);
    if (!out) {
        free(trie);
        return -4;
    }

    uint32_t pos = 544;
    uint32_t bit_buf = 0;
    int bits_left = 0;
    uint32_t mask_table = table_size - 1u;
    uint32_t out_pos = 0;

    for (uint32_t step = 0; step < dec_count; step++) {
        while (bits_left < table_bits && pos < data_len) {
            bit_buf = (bit_buf << 8) | data[pos++];
            bits_left += 8;
        }
        if (bits_left == 0) {
            free(out);
            free(trie);
            return -5;
        }
        uint32_t idx;
        if (bits_left >= table_bits) {
            idx = (bit_buf >> (bits_left - table_bits)) & mask_table;
        } else {
            idx = (bit_buf << (table_bits - bits_left)) & mask_table;
        }

        int32_t sym = lut_sym[idx];
        int used = lut_len[idx];
        if (sym >= 0) {
            if (used > bits_left) {
                free(out);
                free(trie);
                return -5;
            }
            bits_left -= used;
            bit_buf &= bits_left ? ((1u << bits_left) - 1u) : 0u;
        } else {
            int cur = 0;
            int found = -1;
            for (int depth = 0; depth < 32; depth++) {
                if (bits_left == 0) {
                    if (pos >= data_len) {
                        free(out);
                        free(trie);
                        return -5;
                    }
                    bit_buf = data[pos++];
                    bits_left = 8;
                }
                bits_left--;
                int bit = (int)((bit_buf >> bits_left) & 1u);
                bit_buf &= bits_left ? ((1u << bits_left) - 1u) : 0u;
                cur = bit ? trie[cur].right : trie[cur].left;
                if (cur < 0) {
                    free(out);
                    free(trie);
                    return -5;
                }
                if (trie[cur].sym >= 0) {
                    found = trie[cur].sym;
                    break;
                }
            }
            if (found < 0) {
                free(out);
                free(trie);
                return -5;
            }
            sym = found;
        }

        if (sym < 256) {
            if (out_pos >= uncomp_size) {
                free(out);
                free(trie);
                return -6;
            }
            out[out_pos++] = (uint8_t)sym;
        } else {
            uint32_t copy_len = (uint32_t)(sym - 256 + 2);
            while (bits_left < 12) {
                if (pos >= data_len) {
                    free(out);
                    free(trie);
                    return -5;
                }
                bit_buf = (bit_buf << 8) | data[pos++];
                bits_left += 8;
            }
            bits_left -= 12;
            uint32_t dist = ((bit_buf >> bits_left) & 0xFFFu) + 2u;
            bit_buf &= bits_left ? ((1u << bits_left) - 1u) : 0u;

            if (dist > out_pos || out_pos + copy_len > uncomp_size) {
                free(out);
                free(trie);
                return -6;
            }
            uint32_t src_pos = out_pos - dist;
            for (uint32_t j = 0; j < copy_len; j++) {
                out[out_pos++] = out[src_pos + j];
            }
        }
    }

    free(trie);
    if (out_pos != uncomp_size) {
        free(out);
        return -6;
    }
    *out_buf = out;
    *out_len = uncomp_size;
    return 0;
}

static int decode_sdc_buf(const uint8_t *data, uint32_t data_len, uint8_t **out_buf, uint32_t *out_len) {
    static const uint8_t MAGIC[16] = "SDC FORMAT 1.00\x00";
    if (!data || data_len < 32 || memcmp(data, MAGIC, 16) != 0) return -1;

    uint32_t k = read_u32_le(data + 16);
    uint32_t comp_size = read_u32_le(data + 20);
    uint32_t uncomp_size = read_u32_le(data + 24);
    if (32ull + comp_size > data_len) return -2;

    uint8_t *dec = (uint8_t *)malloc(comp_size ? comp_size : 1);
    if (!dec) return -3;
    for (uint32_t i = 0; i < comp_size; i++) {
        uint8_t kb = bgi_key_step(&k);
        dec[i] = (uint8_t)(data[32 + i] - kb);
    }

    uint8_t *out = (uint8_t *)malloc(uncomp_size ? uncomp_size : 1);
    if (!out) {
        free(dec);
        return -3;
    }

    uint32_t pos = 0;
    uint32_t out_pos = 0;
    while (pos < comp_size) {
        uint8_t b0 = dec[pos++];
        if ((b0 & 0x80u) == 0) {
            uint32_t lit_len = (uint32_t)b0 + 1u;
            if (pos + lit_len > comp_size || out_pos + lit_len > uncomp_size) {
                free(dec);
                free(out);
                return -4;
            }
            memcpy(out + out_pos, dec + pos, lit_len);
            pos += lit_len;
            out_pos += lit_len;
        } else {
            if (pos >= comp_size) {
                free(dec);
                free(out);
                return -4;
            }
            uint8_t b1 = dec[pos++];
            uint32_t copy_len = (uint32_t)((b0 >> 3) & 0x0Fu) + 2u;
            uint32_t dist = (uint32_t)(((b0 & 0x07u) << 8) | b1) + 2u;
            if (dist > out_pos || out_pos + copy_len > uncomp_size) {
                free(dec);
                free(out);
                return -4;
            }
            uint32_t src_pos = out_pos - dist;
            for (uint32_t j = 0; j < copy_len; j++) {
                out[out_pos++] = out[src_pos + j];
            }
        }
    }
    free(dec);
    if (out_pos != uncomp_size) {
        free(out);
        return -4;
    }
    *out_buf = out;
    *out_len = uncomp_size;
    return 0;
}

/* ==================== CBG v1 解码 (输出 RGBA8) ==================== */

typedef struct {
    uint64_t weight;
    int32_t left;
    int32_t right;
    uint8_t valid;
} CbgNode;

static int read_varint(const uint8_t *buf, uint32_t len, uint32_t *pos, uint32_t *out_val) {
    uint32_t val = 0, shift = 0;
    while (*pos < len) {
        uint8_t b = buf[(*pos)++];
        if (shift >= 32) return -1;
        val |= (uint32_t)(b & 0x7Fu) << shift;
        if ((b & 0x80u) == 0) {
            *out_val = val;
            return 0;
        }
        shift += 7;
    }
    return -1;
}

static void fill_cbg_lut(const CbgNode *nodes, int32_t node_idx, uint32_t prefix, int depth,
                         int32_t *lut_val, uint8_t *lut_len) {
    if (node_idx < 256) {
        if (depth == 0) {
            for (int i = 0; i < 4096; i++) {
                lut_val[i] = node_idx;
                lut_len[i] = 0;
            }
            return;
        }
        int shift = 12 - depth;
        uint32_t base = prefix << shift;
        uint32_t fill = 1u << shift;
        for (uint32_t i = base; i < base + fill; i++) {
            lut_val[i] = node_idx;
            lut_len[i] = (uint8_t)depth;
        }
        return;
    }
    if (depth == 12) {
        lut_val[prefix] = -(node_idx + 1);
        lut_len[prefix] = 12;
        return;
    }
    fill_cbg_lut(nodes, nodes[node_idx].left, prefix << 1, depth + 1, lut_val, lut_len);
    fill_cbg_lut(nodes, nodes[node_idx].right, (prefix << 1) | 1u, depth + 1, lut_val, lut_len);
}

static int decode_cbg_to_rgba(const uint8_t *data, uint32_t data_len, BgiImageRgba *out_img) {
    static const uint8_t MAGIC[16] = "CompressedBG___\x00";
    if (!data || data_len < 48 || memcmp(data, MAGIC, 16) != 0) return -1;

    uint32_t w = read_u16_le(data + 16);
    uint32_t h = read_u16_le(data + 18);
    uint32_t bpp = read_u32_le(data + 20);
    uint32_t rle_size = read_u32_le(data + 32);
    uint32_t key = read_u32_le(data + 36);
    uint32_t enc_len = read_u32_le(data + 40);
    uint8_t sum_check = data[44];
    uint8_t xor_check = data[45];
    uint32_t version = read_u16_le(data + 46);

    if (version != 1 || (bpp != 8 && bpp != 24 && bpp != 32)) return -2;
    if ((uint64_t)48 + enc_len > data_len || enc_len == 0) return -3;

    uint32_t bpp_bytes = bpp / 8u;
    uint64_t raw_len64 = (uint64_t)w * (uint64_t)h * bpp_bytes;
    if (raw_len64 == 0 || raw_len64 > 0x7FFFFFFFull) return -5;
    uint32_t raw_len = (uint32_t)raw_len64;

    uint8_t *dec_freq = (uint8_t *)malloc(enc_len);
    if (!dec_freq) return -5;
    uint32_t k = key;
    uint8_t s_acc = 0, x_acc = 0;
    for (uint32_t i = 0; i < enc_len; i++) {
        uint8_t b = (uint8_t)(data[48 + i] - bgi_key_step(&k));
        dec_freq[i] = b;
        s_acc = (uint8_t)(s_acc + b);
        x_acc ^= b;
    }
    if (s_acc != sum_check || x_acc != xor_check) {
        free(dec_freq);
        return -3;
    }

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
    if (total_freq == 0 || fpos != enc_len) return -4;

    int32_t node_count = 256;
    int32_t root = 0;
    for (;;) {
        int32_t m1 = -1, m2 = -1;
        uint64_t w1 = UINT64_MAX, w2 = UINT64_MAX;
        for (int32_t idx = 0; idx < node_count; idx++) {
            if (!nodes[idx].valid) continue;
            uint64_t wn = nodes[idx].weight;
            if (wn < w1) {
                m2 = m1; w2 = w1;
                m1 = idx; w1 = wn;
            } else if (wn < w2) {
                m2 = idx; w2 = wn;
            }
        }
        if (m2 == -1) {
            root = m1;
            break;
        }
        nodes[m1].valid = 0;
        nodes[m2].valid = 0;
        int32_t nid = node_count++;
        nodes[nid].weight = w1 + w2;
        nodes[nid].valid = 1;
        nodes[nid].left = m1;
        nodes[nid].right = m2;
        if (nodes[nid].weight == total_freq) {
            root = nid;
            break;
        }
    }

    int32_t lut_val[4096];
    uint8_t lut_len[4096];
    fill_cbg_lut(nodes, root, 0, 0, lut_val, lut_len);

    uint8_t *rle_buf = (uint8_t *)malloc(rle_size ? rle_size : 1);
    if (!rle_buf) return -5;

    uint32_t bs_pos = 48 + enc_len;
    uint32_t bit_buf = 0;
    int bits_left = 0;
    for (uint32_t i = 0; i < rle_size; i++) {
        while (bits_left < 12 && bs_pos < data_len) {
            bit_buf = (bit_buf << 8) | data[bs_pos++];
            bits_left += 8;
        }
        if (bits_left == 0) {
            free(rle_buf);
            return -6;
        }
        uint32_t idx = (bits_left >= 12)
            ? ((bit_buf >> (bits_left - 12)) & 4095u)
            : ((bit_buf << (12 - bits_left)) & 4095u);
        int32_t val = lut_val[idx];
        if (val >= 0) {
            int used = lut_len[idx];
            if (used > bits_left) {
                free(rle_buf);
                return -6;
            }
            bits_left -= used;
            bit_buf &= bits_left ? ((1u << bits_left) - 1u) : 0u;
            rle_buf[i] = (uint8_t)val;
        } else {
            bits_left -= 12;
            bit_buf &= bits_left ? ((1u << bits_left) - 1u) : 0u;
            int32_t node = -(val + 1);
            while (node >= 256) {
                if (bits_left == 0) {
                    if (bs_pos >= data_len) {
                        free(rle_buf);
                        return -6;
                    }
                    bit_buf = data[bs_pos++];
                    bits_left = 8;
                }
                bits_left--;
                uint32_t bit = (bit_buf >> bits_left) & 1u;
                bit_buf &= bits_left ? ((1u << bits_left) - 1u) : 0u;
                node = bit ? nodes[node].right : nodes[node].left;
            }
            rle_buf[i] = (uint8_t)node;
        }
    }

    uint8_t *raw = (uint8_t *)malloc(raw_len);
    if (!raw) {
        free(rle_buf);
        return -5;
    }
    uint32_t src_i = 0, dst_i = 0;
    int zero_flag = 0;
    while (src_i < rle_size && dst_i < raw_len) {
        uint32_t cnt = 0;
        if (read_varint(rle_buf, rle_size, &src_i, &cnt) != 0) {
            free(raw);
            free(rle_buf);
            return -6;
        }
        if (dst_i + cnt > raw_len) {
            free(raw);
            free(rle_buf);
            return -6;
        }
        if (zero_flag) {
            memset(raw + dst_i, 0, cnt);
        } else {
            if (src_i + cnt > rle_size) {
                free(raw);
                free(rle_buf);
                return -6;
            }
            memcpy(raw + dst_i, rle_buf + src_i, cnt);
            src_i += cnt;
        }
        dst_i += cnt;
        zero_flag ^= 1;
    }
    free(rle_buf);
    if (dst_i != raw_len) {
        free(raw);
        return -6;
    }

    /* 二维空间差分逆还原 */
    uint32_t row_bytes = w * bpp_bytes;
    for (uint32_t c = bpp_bytes; c < row_bytes; c++) {
        raw[c] = (uint8_t)(raw[c] + raw[c - bpp_bytes]);
    }
    for (uint32_t y = 1; y < h; y++) {
        uint8_t *cur = raw + (size_t)y * row_bytes;
        uint8_t *up = cur - row_bytes;
        for (uint32_t c = 0; c < bpp_bytes; c++) {
            cur[c] = (uint8_t)(cur[c] + up[c]);
        }
        for (uint32_t c = bpp_bytes; c < row_bytes; c++) {
            uint32_t avg = ((uint32_t)cur[c - bpp_bytes] + (uint32_t)up[c]) >> 1;
            cur[c] = (uint8_t)(cur[c] + avg);
        }
    }

    /* 统一转换为 Top-Down RGBA8 */
    uint64_t rgba_len = (uint64_t)w * (uint64_t)h * 4ull;
    uint8_t *rgba = (uint8_t *)malloc((size_t)rgba_len);
    if (!rgba) {
        free(raw);
        return -5;
    }
    uint32_t npix = w * h;
    if (bpp == 32) {
        for (uint32_t i = 0; i < npix; i++) {
            rgba[i * 4 + 0] = raw[i * 4 + 2];
            rgba[i * 4 + 1] = raw[i * 4 + 1];
            rgba[i * 4 + 2] = raw[i * 4 + 0];
            rgba[i * 4 + 3] = raw[i * 4 + 3];
        }
    } else if (bpp == 24) {
        for (uint32_t i = 0; i < npix; i++) {
            rgba[i * 4 + 0] = raw[i * 3 + 2];
            rgba[i * 4 + 1] = raw[i * 3 + 1];
            rgba[i * 4 + 2] = raw[i * 3 + 0];
            rgba[i * 4 + 3] = 255;
        }
    } else {
        for (uint32_t i = 0; i < npix; i++) {
            uint8_t v = raw[i];
            rgba[i * 4 + 0] = v;
            rgba[i * 4 + 1] = v;
            rgba[i * 4 + 2] = v;
            rgba[i * 4 + 3] = 255;
        }
    }
    free(raw);
    out_img->rgba = rgba;
    out_img->width = w;
    out_img->height = h;
    return 0;
}

static int decode_bmp_to_rgba(const uint8_t *data, uint32_t data_len, BgiImageRgba *out_img) {
    if (!data || data_len < 54 || data[0] != 'B' || data[1] != 'M') return -1;
    uint32_t pixel_off = read_u32_le(data + 10);
    uint32_t info_size = read_u32_le(data + 14);
    if (info_size < 40 || pixel_off >= data_len) return -2;

    int32_t w = read_i32_le(data + 18);
    int32_t h_raw = read_i32_le(data + 22);
    uint16_t bpp = read_u16_le(data + 28);
    uint32_t comp = read_u32_le(data + 30);
    if (w <= 0 || h_raw == 0 || comp != 0 || (bpp != 24 && bpp != 32)) return -2;

    int bottom_up = (h_raw > 0);
    uint32_t h = (uint32_t)(bottom_up ? h_raw : -h_raw);
    uint32_t uw = (uint32_t)w;
    uint32_t src_stride = ((uw * bpp + 31u) / 32u) * 4u;
    if ((uint64_t)pixel_off + (uint64_t)src_stride * h > data_len) return -3;

    uint8_t *rgba = (uint8_t *)malloc((size_t)uw * h * 4u);
    if (!rgba) return -4;

    for (uint32_t y = 0; y < h; y++) {
        uint32_t sy = bottom_up ? (h - 1u - y) : y;
        const uint8_t *srow = data + pixel_off + (size_t)sy * src_stride;
        uint8_t *drow = rgba + (size_t)y * uw * 4u;
        if (bpp == 32) {
            for (uint32_t x = 0; x < uw; x++) {
                drow[x * 4 + 0] = srow[x * 4 + 2];
                drow[x * 4 + 1] = srow[x * 4 + 1];
                drow[x * 4 + 2] = srow[x * 4 + 0];
                drow[x * 4 + 3] = srow[x * 4 + 3];
            }
        } else {
            for (uint32_t x = 0; x < uw; x++) {
                drow[x * 4 + 0] = srow[x * 3 + 2];
                drow[x * 4 + 1] = srow[x * 3 + 1];
                drow[x * 4 + 2] = srow[x * 3 + 0];
                drow[x * 4 + 3] = 255;
            }
        }
    }
    out_img->rgba = rgba;
    out_img->width = uw;
    out_img->height = h;
    return 0;
}

/* ==================== 对外业务接口 ==================== */

int bgi_vfs_extract_raw(
    const BgiVfsState *vfs,
    const char *name_utf8,
    int strip_containers,
    uint8_t **out_buf,
    uint32_t *out_len
) {
    *out_buf = NULL;
    *out_len = 0;
    const BgiEntry *ent = bgi_vfs_find_entry(vfs, name_utf8);
    if (!ent) return -1;

    const BgiArchive *arc = &vfs->archives[ent->archive_idx];
    FILE *fp = open_rb_utf8(arc->path);
    if (!fp) return -2;

    if (fseek(fp, (long)ent->offset, SEEK_SET) != 0) {
        fclose(fp);
        return -3;
    }
    uint8_t *raw = (uint8_t *)malloc(ent->size ? ent->size : 1);
    if (!raw) {
        fclose(fp);
        return -4;
    }
    if (ent->size > 0 && fread(raw, 1, ent->size, fp) != ent->size) {
        free(raw);
        fclose(fp);
        return -5;
    }
    fclose(fp);

    if (strip_containers && ent->size >= 32) {
        if (ent->size >= 544 && memcmp(raw, "DSC FORMAT 1.00\x00", 16) == 0) {
            uint8_t *dec = NULL;
            uint32_t dec_len = 0;
            int rc = decode_dsc_buf(raw, ent->size, &dec, &dec_len);
            free(raw);
            if (rc != 0) return -10 + rc;
            *out_buf = dec;
            *out_len = dec_len;
            return 0;
        }
        if (memcmp(raw, "SDC FORMAT 1.00\x00", 16) == 0) {
            uint8_t *dec = NULL;
            uint32_t dec_len = 0;
            int rc = decode_sdc_buf(raw, ent->size, &dec, &dec_len);
            free(raw);
            if (rc != 0) return -20 + rc;
            *out_buf = dec;
            *out_len = dec_len;
            return 0;
        }
    }

    *out_buf = raw;
    *out_len = ent->size;
    return 0;
}

int bgi_vfs_decode_image_rgba(
    const BgiVfsState *vfs,
    const char *name_utf8,
    BgiImageRgba *out_img
) {
    memset(out_img, 0, sizeof(*out_img));
    uint8_t *raw = NULL;
    uint32_t raw_len = 0;
    int rc = bgi_vfs_extract_raw(vfs, name_utf8, 1, &raw, &raw_len);
    if (rc != 0) return rc;

    if (raw_len >= 48 && memcmp(raw, "CompressedBG___\x00", 16) == 0) {
        rc = decode_cbg_to_rgba(raw, raw_len, out_img);
    } else if (raw_len >= 54 && raw[0] == 'B' && raw[1] == 'M') {
        rc = decode_bmp_to_rgba(raw, raw_len, out_img);
    } else {
        rc = -30;
    }
    free(raw);
    return rc;
}

int bgi_vfs_extract_audio_ogg(
    const BgiVfsState *vfs,
    const char *name_utf8,
    BgiAudioOgg *out_audio
) {
    memset(out_audio, 0, sizeof(*out_audio));
    uint8_t *raw = NULL;
    uint32_t raw_len = 0;
    int rc = bgi_vfs_extract_raw(vfs, name_utf8, 1, &raw, &raw_len);
    if (rc != 0) return rc;

    if (raw_len < 64 || memcmp(raw + 4, "bw  ", 4) != 0) {
        free(raw);
        return -40;
    }
    uint32_t hdr_size = read_u32_le(raw + 0);
    uint32_t ogg_size = read_u32_le(raw + 8);
    if (hdr_size < 64 || (uint64_t)hdr_size + ogg_size > raw_len) {
        free(raw);
        return -41;
    }
    uint8_t *ogg = (uint8_t *)malloc(ogg_size ? ogg_size : 1);
    if (!ogg) {
        free(raw);
        return -42;
    }
    if (ogg_size > 0) {
        memcpy(ogg, raw + hdr_size, ogg_size);
    }
    out_audio->ogg = ogg;
    out_audio->ogg_size = ogg_size;
    out_audio->sample_rate = read_u32_le(raw + 16);
    out_audio->channels = read_u32_le(raw + 20);
    out_audio->loop_flag = read_u32_le(raw + 24);
    free(raw);
    return 0;
}
