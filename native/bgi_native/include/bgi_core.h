#ifndef BGI_CORE_H
#define BGI_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t hash;
    int32_t archive_idx;
    uint32_t offset;
    uint32_t size;
    char *name;
    char *lower_name;
} BgiEntry;

typedef struct {
    char *path;
    uint8_t is_v2;
} BgiArchive;

typedef struct {
    BgiArchive *archives;
    uint32_t archive_count;
    BgiArchive *archive_cap_ptr;
    uint32_t archive_cap;

    BgiEntry *entries;
    uint32_t entry_count;
    uint32_t entry_cap;

    int32_t *buckets;
    uint32_t bucket_cap;
} BgiVfsState;

typedef struct {
    uint8_t *rgba;
    uint32_t width;
    uint32_t height;
} BgiImageRgba;

typedef struct {
    uint8_t *ogg;
    uint32_t ogg_size;
    uint32_t sample_rate;
    uint32_t channels;
    uint32_t loop_flag;
} BgiAudioOgg;

void bgi_vfs_init(BgiVfsState *vfs);
void bgi_vfs_free(BgiVfsState *vfs);

/* 挂载游戏目录（支持 uncensored_mode 控制 data02150.arc(.bak) 优先级），返回挂载条目数或负错误码 */
int32_t bgi_vfs_mount(BgiVfsState *vfs, const char *dir_utf8, int uncensored_mode);

int bgi_vfs_has_entry(const BgiVfsState *vfs, const char *name_utf8);
const BgiEntry *bgi_vfs_find_entry(const BgiVfsState *vfs, const char *name_utf8);

/* 读取原始条目字节；strip_containers!=0 时自动剥离 DSC 1.00 / SDC 1.00 */
int bgi_vfs_extract_raw(
    const BgiVfsState *vfs,
    const char *name_utf8,
    int strip_containers,
    uint8_t **out_buf,
    uint32_t *out_len
);

/* 统一解码 CBG v1 与 DSC 内嵌 BMP 为 Top-Down RGBA8 */
int bgi_vfs_decode_image_rgba(
    const BgiVfsState *vfs,
    const char *name_utf8,
    BgiImageRgba *out_img
);

/* 提取 bw  音频流（自动剥离外层可能存在的 DSC 1.00） */
int bgi_vfs_extract_audio_ogg(
    const BgiVfsState *vfs,
    const char *name_utf8,
    BgiAudioOgg *out_audio
);

void bgi_free_buffer(void *p);

#ifdef __cplusplus
}
#endif

#endif /* BGI_CORE_H */
