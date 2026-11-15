/*
 * Godot 4.3 纯 C GDExtension 绑定层：向 GDScript 暴露 BgiNative 类。
 */

#include "gdextension_interface.h"
#include "bgi_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define GDE_EXPORT __declspec(dllexport)
#else
#define GDE_EXPORT __attribute__((visibility("default")))
#endif

typedef struct { uint64_t opaque[4]; } GdVariant;
typedef struct { uint64_t opaque[2]; } GdOpaque;

typedef struct {
    GDExtensionClassLibraryPtr library;
    GDExtensionInterfaceMemAlloc mem_alloc;
    GDExtensionInterfaceMemFree mem_free;
    GDExtensionInterfaceClassdbRegisterExtensionClass3 register_class3;
    GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
    GDExtensionInterfaceClassdbConstructObject construct_object;
    GDExtensionInterfaceObjectSetInstance object_set_instance;
    GDExtensionInterfaceObjectSetInstanceBinding object_set_instance_binding;

    GDExtensionInterfaceStringNewWithUtf8Chars string_new_utf8;
    GDExtensionInterfaceStringToUtf8Chars string_to_utf8;
    GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new_latin1;

    GDExtensionInterfaceVariantNewNil variant_new_nil;
    GDExtensionInterfaceVariantDestroy variant_destroy;
    GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
    GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;

    GDExtensionInterfaceVariantGetPtrConstructor get_ptr_ctor;
    GDExtensionInterfaceVariantGetPtrDestructor get_ptr_dtor;
    GDExtensionInterfaceVariantGetPtrBuiltinMethod get_ptr_builtin_method;

    GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
    GDExtensionInterfacePackedStringArrayOperatorIndex psa_index;
    GDExtensionInterfaceDictionaryOperatorIndex dict_index;
    GDExtensionInterfaceArrayOperatorIndex array_index;

    GDExtensionVariantFromTypeConstructorFunc from_type[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
    GDExtensionTypeFromVariantConstructorFunc to_type[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
    GDExtensionPtrConstructor ctor_default[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
    GDExtensionPtrDestructor dtor[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];

    GDExtensionPtrBuiltInMethod pba_resize;
    GDExtensionPtrBuiltInMethod psa_resize;
    GDExtensionPtrBuiltInMethod array_resize;
} BgiApi;

static BgiApi g_api;
static const GDExtensionInstanceBindingCallbacks g_binding_callbacks = {NULL, NULL, NULL};

typedef struct {
    GDExtensionObjectPtr godot_obj;
    BgiVfsState vfs;
} BgiNativeInstance;

/* ==================== Variant 辅助函数 ==================== */

static void var_set_bool(GDExtensionVariantPtr dst, GDExtensionBool v) {
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_BOOL](dst, &v);
}

static void var_set_int(GDExtensionVariantPtr dst, int64_t v) {
    GDExtensionInt gv = (GDExtensionInt)v;
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_INT](dst, &gv);
}

static void var_set_string(GDExtensionVariantPtr dst, const char *utf8) {
    GdOpaque s = {0};
    g_api.string_new_utf8(&s, utf8 ? utf8 : "");
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_STRING](dst, &s);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](&s);
}

static char *var_to_cstr(GDExtensionConstVariantPtr v) {
    GdOpaque s = {0};
    g_api.to_type[GDEXTENSION_VARIANT_TYPE_STRING](&s, (GDExtensionVariantPtr)v);
    GDExtensionInt len = g_api.string_to_utf8(&s, NULL, 0);
    if (len < 0) len = 0;
    char *buf = (char *)malloc((size_t)len + 1);
    if (buf) {
        if (len > 0) g_api.string_to_utf8(&s, buf, len);
        buf[len] = '\0';
    }
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](&s);
    return buf;
}

static int64_t var_to_int(GDExtensionConstVariantPtr v) {
    GDExtensionInt gv = 0;
    g_api.to_type[GDEXTENSION_VARIANT_TYPE_INT](&gv, (GDExtensionVariantPtr)v);
    return (int64_t)gv;
}

static int var_to_bool(GDExtensionConstVariantPtr v) {
    GDExtensionBool bv = 0;
    g_api.to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&bv, (GDExtensionVariantPtr)v);
    return bv ? 1 : 0;
}

static void var_set_pba(GDExtensionVariantPtr dst, const uint8_t *bytes, uint32_t len) {
    GdOpaque pba = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&pba, NULL);
    if (len > 0 && bytes) {
        GDExtensionInt n = (GDExtensionInt)len;
        const GDExtensionConstTypePtr args[1] = {&n};
        GDExtensionInt rc = 0;
        g_api.pba_resize(&pba, args, &rc, 0);
        uint8_t *ptr = g_api.pba_index(&pba, 0);
        if (ptr) memcpy(ptr, bytes, len);
    }
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](dst, &pba);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&pba);
}

static void dict_set_int(GdOpaque *dict, const char *key, int64_t val) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_int(slot, val);
    g_api.variant_destroy(&k);
}

static void dict_set_bool(GdOpaque *dict, const char *key, int val) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_bool(slot, val ? 1 : 0);
    g_api.variant_destroy(&k);
}

static void dict_set_pba(GdOpaque *dict, const char *key, const uint8_t *bytes, uint32_t len) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_pba(slot, bytes, len);
    g_api.variant_destroy(&k);
}

/* ==================== 类实例生命周期 ==================== */

static GDExtensionObjectPtr bgi_native_create_instance(void *p_userdata) {
    (void)p_userdata;
    GdOpaque parent_sn = {0};
    GdOpaque self_sn = {0};
    g_api.string_name_new_latin1(&parent_sn, "RefCounted", 0);
    g_api.string_name_new_latin1(&self_sn, "BgiNative", 0);

    GDExtensionObjectPtr obj = g_api.construct_object(&parent_sn);
    BgiNativeInstance *inst = (BgiNativeInstance *)g_api.mem_alloc(sizeof(BgiNativeInstance));
    memset(inst, 0, sizeof(*inst));
    inst->godot_obj = obj;
    bgi_vfs_init(&inst->vfs);

    g_api.object_set_instance(obj, &self_sn, inst);
    g_api.object_set_instance_binding(obj, g_api.library, inst, &g_binding_callbacks);

    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&parent_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&self_sn);
    return obj;
}

static void bgi_native_free_instance(void *p_userdata, GDExtensionClassInstancePtr p_instance) {
    (void)p_userdata;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;
    if (inst) {
        bgi_vfs_free(&inst->vfs);
        g_api.mem_free(inst);
    }
}

/* ==================== 暴露给 GDScript 的方法实现 ==================== */

static void m_mount_game_dir(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;
    if (!inst || p_arg_count < 1) {
        var_set_int(r_ret, -1);
        return;
    }
    char *dir = var_to_cstr(p_args[0]);
    int uncensored = (p_arg_count >= 2) ? var_to_bool(p_args[1]) : 0;
    int32_t rc = bgi_vfs_mount(&inst->vfs, dir ? dir : "", uncensored);
    free(dir);
    var_set_int(r_ret, rc);
}

static void m_has_entry(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;
    if (!inst || p_arg_count < 1) {
        var_set_bool(r_ret, 0);
        return;
    }
    char *name = var_to_cstr(p_args[0]);
    int ok = name ? bgi_vfs_has_entry(&inst->vfs, name) : 0;
    free(name);
    var_set_bool(r_ret, ok ? 1 : 0);
}

static void m_get_entry_count(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_args; (void)p_arg_count;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;
    var_set_int(r_ret, inst ? (int64_t)inst->vfs.entry_count : 0);
}

static void m_list_entries(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;
    char *prefix = (p_arg_count >= 1) ? var_to_cstr(p_args[0]) : NULL;
    size_t plen = prefix ? strlen(prefix) : 0;
    for (size_t i = 0; i < plen; i++) {
        if (prefix[i] >= 'A' && prefix[i] <= 'Z') prefix[i] = (char)(prefix[i] - 'A' + 'a');
    }

    uint32_t match_cnt = 0;
    if (inst) {
        for (uint32_t i = 0; i < inst->vfs.entry_count; i++) {
            if (plen == 0 || strncmp(inst->vfs.entries[i].lower_name, prefix, plen) == 0) {
                match_cnt++;
            }
        }
    }

    GdOpaque psa = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](&psa, NULL);
    if (match_cnt > 0) {
        GDExtensionInt n = (GDExtensionInt)match_cnt;
        const GDExtensionConstTypePtr args[1] = {&n};
        GDExtensionInt rc = 0;
        g_api.psa_resize(&psa, args, &rc, 0);
        uint32_t wi = 0;
        for (uint32_t i = 0; i < inst->vfs.entry_count; i++) {
            if (plen == 0 || strncmp(inst->vfs.entries[i].lower_name, prefix, plen) == 0) {
                GDExtensionStringPtr sp = g_api.psa_index(&psa, (GDExtensionInt)wi++);
                g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](sp);
                g_api.string_new_utf8(sp, inst->vfs.entries[i].name);
            }
        }
    }
    free(prefix);
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](r_ret, &psa);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](&psa);
}

static void m_extract_raw(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;
    if (!inst || p_arg_count < 1) {
        var_set_pba(r_ret, NULL, 0);
        return;
    }
    char *name = var_to_cstr(p_args[0]);
    uint8_t *buf = NULL;
    uint32_t len = 0;
    int rc = name ? bgi_vfs_extract_raw(&inst->vfs, name, 1, &buf, &len) : -1;
    free(name);
    if (rc == 0 && buf) {
        var_set_pba(r_ret, buf, len);
        bgi_free_buffer(buf);
    } else {
        var_set_pba(r_ret, NULL, 0);
    }
}

static void m_decode_image_info(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;

    GdOpaque dict = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict, NULL);
    if (!inst || p_arg_count < 1) {
        dict_set_bool(&dict, "ok", 0);
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
        return;
    }
    char *name = var_to_cstr(p_args[0]);
    BgiImageRgba img = {0};
    int rc = name ? bgi_vfs_decode_image_rgba(&inst->vfs, name, &img) : -1;
    free(name);
    if (rc == 0 && img.rgba) {
        dict_set_bool(&dict, "ok", 1);
        dict_set_int(&dict, "width", (int64_t)img.width);
        dict_set_int(&dict, "height", (int64_t)img.height);
        dict_set_pba(&dict, "data", img.rgba, img.width * img.height * 4u);
        bgi_free_buffer(img.rgba);
    } else {
        dict_set_bool(&dict, "ok", 0);
        dict_set_int(&dict, "error", rc);
    }
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
}

static void m_decode_image_slices(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;

    GdOpaque arr = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_ARRAY](&arr, NULL);
    if (!inst || p_arg_count < 1) {
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_ARRAY](r_ret, &arr);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_ARRAY](&arr);
        return;
    }
    char *name = var_to_cstr(p_args[0]);
    int64_t max_h = (p_arg_count >= 2) ? var_to_int(p_args[1]) : 4096;
    if (max_h <= 0) max_h = 4096;

    BgiImageRgba img = {0};
    int rc = name ? bgi_vfs_decode_image_rgba(&inst->vfs, name, &img) : -1;
    free(name);
    if (rc == 0 && img.rgba && img.height > 0) {
        uint32_t slice_max = (uint32_t)max_h;
        uint32_t slice_cnt = (img.height + slice_max - 1u) / slice_max;
        GDExtensionInt n = (GDExtensionInt)slice_cnt;
        const GDExtensionConstTypePtr args[1] = {&n};
        GDExtensionInt r_res = 0;
        g_api.array_resize(&arr, args, &r_res, 0);

        uint32_t row_bytes = img.width * 4u;
        for (uint32_t i = 0; i < slice_cnt; i++) {
            uint32_t y0 = i * slice_max;
            uint32_t sh = img.height - y0;
            if (sh > slice_max) sh = slice_max;

            GdOpaque sd = {0};
            g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&sd, NULL);
            dict_set_int(&sd, "width", (int64_t)img.width);
            dict_set_int(&sd, "height", (int64_t)sh);
            dict_set_int(&sd, "y_offset", (int64_t)y0);
            dict_set_int(&sd, "total_height", (int64_t)img.height);
            dict_set_pba(&sd, "data", img.rgba + (size_t)y0 * row_bytes, sh * row_bytes);

            GDExtensionVariantPtr slot = g_api.array_index(&arr, (GDExtensionInt)i);
            if (slot) g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](slot, &sd);
            g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&sd);
        }
        bgi_free_buffer(img.rgba);
    }
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_ARRAY](r_ret, &arr);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_ARRAY](&arr);
}

static void m_extract_audio_info(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    BgiNativeInstance *inst = (BgiNativeInstance *)p_instance;

    GdOpaque dict = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict, NULL);
    if (!inst || p_arg_count < 1) {
        dict_set_bool(&dict, "ok", 0);
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
        return;
    }
    char *name = var_to_cstr(p_args[0]);
    BgiAudioOgg aud = {0};
    int rc = name ? bgi_vfs_extract_audio_ogg(&inst->vfs, name, &aud) : -1;
    free(name);
    if (rc == 0 && aud.ogg) {
        dict_set_bool(&dict, "ok", 1);
        dict_set_int(&dict, "sample_rate", (int64_t)aud.sample_rate);
        dict_set_int(&dict, "channels", (int64_t)aud.channels);
        dict_set_int(&dict, "loop_flag", (int64_t)aud.loop_flag);
        dict_set_pba(&dict, "ogg", aud.ogg, aud.ogg_size);
        bgi_free_buffer(aud.ogg);
    } else {
        dict_set_bool(&dict, "ok", 0);
        dict_set_int(&dict, "error", rc);
    }
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
}

/* ==================== 方法注册与初始化 ==================== */

static void reg_method(
    const char *cls_name,
    const char *method_name,
    GDExtensionClassMethodCall call_fn,
    GDExtensionVariantType ret_type,
    uint32_t arg_count,
    const GDExtensionVariantType *arg_types,
    uint32_t default_count,
    GDExtensionVariantPtr *default_vals
) {
    GdOpaque cls_sn = {0}, m_sn = {0};
    g_api.string_name_new_latin1(&cls_sn, cls_name, 0);
    g_api.string_name_new_latin1(&m_sn, method_name, 0);

    GdOpaque empty_sn = {0};
    g_api.string_name_new_latin1(&empty_sn, "", 0);
    GdOpaque empty_str = {0};
    g_api.string_new_utf8(&empty_str, "");

    GDExtensionPropertyInfo ret_info = {0};
    ret_info.type = ret_type;
    ret_info.name = &empty_sn;
    ret_info.class_name = &empty_sn;
    ret_info.hint_string = &empty_str;

    GDExtensionPropertyInfo args_info[4];
    GDExtensionClassMethodArgumentMetadata args_meta[4];
    memset(args_info, 0, sizeof(args_info));
    memset(args_meta, 0, sizeof(args_meta));
    for (uint32_t i = 0; i < arg_count; i++) {
        args_info[i].type = arg_types[i];
        args_info[i].name = &empty_sn;
        args_info[i].class_name = &empty_sn;
        args_info[i].hint_string = &empty_str;
    }

    GDExtensionClassMethodInfo mi = {0};
    mi.name = &m_sn;
    mi.call_func = call_fn;
    mi.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT;
    mi.has_return_value = (ret_type != GDEXTENSION_VARIANT_TYPE_NIL) ? 1 : 0;
    mi.return_value_info = &ret_info;
    mi.argument_count = arg_count;
    mi.arguments_info = arg_count ? args_info : NULL;
    mi.arguments_metadata = arg_count ? args_meta : NULL;
    mi.default_argument_count = default_count;
    mi.default_arguments = default_vals;

    g_api.register_method(g_api.library, &cls_sn, &mi);

    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](&empty_str);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&empty_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&m_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&cls_sn);
}

static void initialize_bgi_module(void *userdata, GDExtensionInitializationLevel p_level) {
    (void)userdata;
    if (p_level != GDEXTENSION_INITIALIZATION_SCENE) return;

    GdOpaque cls_sn = {0}, parent_sn = {0};
    g_api.string_name_new_latin1(&cls_sn, "BgiNative", 0);
    g_api.string_name_new_latin1(&parent_sn, "RefCounted", 0);

    GDExtensionClassCreationInfo3 ci = {0};
    ci.is_exposed = 1;
    ci.create_instance_func = bgi_native_create_instance;
    ci.free_instance_func = bgi_native_free_instance;
    g_api.register_class3(g_api.library, &cls_sn, &parent_sn, &ci);

    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&parent_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&cls_sn);

    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_BOOL};
        GdVariant def_unc = {0};
        var_set_bool(&def_unc, 0);
        GDExtensionVariantPtr defs[] = {&def_unc};
        reg_method("BgiNative", "mount_game_dir", m_mount_game_dir, GDEXTENSION_VARIANT_TYPE_INT, 2, args, 1, defs);
        g_api.variant_destroy(&def_unc);
    }
    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING};
        reg_method("BgiNative", "has_entry", m_has_entry, GDEXTENSION_VARIANT_TYPE_BOOL, 1, args, 0, NULL);
    }
    reg_method("BgiNative", "get_entry_count", m_get_entry_count, GDEXTENSION_VARIANT_TYPE_INT, 0, NULL, 0, NULL);
    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING};
        GdVariant def_p = {0};
        var_set_string(&def_p, "");
        GDExtensionVariantPtr defs[] = {&def_p};
        reg_method("BgiNative", "list_entries", m_list_entries, GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY, 1, args, 1, defs);
        g_api.variant_destroy(&def_p);
    }
    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING};
        reg_method("BgiNative", "extract_raw", m_extract_raw, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 1, args, 0, NULL);
        reg_method("BgiNative", "decode_image_info", m_decode_image_info, GDEXTENSION_VARIANT_TYPE_DICTIONARY, 1, args, 0, NULL);
        reg_method("BgiNative", "extract_audio_info", m_extract_audio_info, GDEXTENSION_VARIANT_TYPE_DICTIONARY, 1, args, 0, NULL);
    }
    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_INT};
        GdVariant def_h = {0};
        var_set_int(&def_h, 4096);
        GDExtensionVariantPtr defs[] = {&def_h};
        reg_method("BgiNative", "decode_image_slices", m_decode_image_slices, GDEXTENSION_VARIANT_TYPE_ARRAY, 2, args, 1, defs);
        g_api.variant_destroy(&def_h);
    }
}

static void deinitialize_bgi_module(void *userdata, GDExtensionInitializationLevel p_level) {
    (void)userdata;
    (void)p_level;
}

GDExtensionBool GDE_EXPORT bgi_native_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization
) {
    memset(&g_api, 0, sizeof(g_api));
    g_api.library = p_library;

    #define LOAD_PROC(field, type, name) g_api.field = (type)(void *)p_get_proc_address(name)
    LOAD_PROC(mem_alloc, GDExtensionInterfaceMemAlloc, "mem_alloc");
    LOAD_PROC(mem_free, GDExtensionInterfaceMemFree, "mem_free");
    LOAD_PROC(register_class3, GDExtensionInterfaceClassdbRegisterExtensionClass3, "classdb_register_extension_class3");
    LOAD_PROC(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD_PROC(construct_object, GDExtensionInterfaceClassdbConstructObject, "classdb_construct_object");
    LOAD_PROC(object_set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD_PROC(object_set_instance_binding, GDExtensionInterfaceObjectSetInstanceBinding, "object_set_instance_binding");

    LOAD_PROC(string_new_utf8, GDExtensionInterfaceStringNewWithUtf8Chars, "string_new_with_utf8_chars");
    LOAD_PROC(string_to_utf8, GDExtensionInterfaceStringToUtf8Chars, "string_to_utf8_chars");
    LOAD_PROC(string_name_new_latin1, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");

    LOAD_PROC(variant_new_nil, GDExtensionInterfaceVariantNewNil, "variant_new_nil");
    LOAD_PROC(variant_destroy, GDExtensionInterfaceVariantDestroy, "variant_destroy");
    LOAD_PROC(get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD_PROC(get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");

    LOAD_PROC(get_ptr_ctor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
    LOAD_PROC(get_ptr_dtor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD_PROC(get_ptr_builtin_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");

    LOAD_PROC(pba_index, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
    LOAD_PROC(psa_index, GDExtensionInterfacePackedStringArrayOperatorIndex, "packed_string_array_operator_index");
    LOAD_PROC(dict_index, GDExtensionInterfaceDictionaryOperatorIndex, "dictionary_operator_index");
    LOAD_PROC(array_index, GDExtensionInterfaceArrayOperatorIndex, "array_operator_index");
    #undef LOAD_PROC

    for (int t = 1; t < GDEXTENSION_VARIANT_TYPE_VARIANT_MAX; t++) {
        g_api.from_type[t] = g_api.get_from_type((GDExtensionVariantType)t);
        g_api.to_type[t] = g_api.get_to_type((GDExtensionVariantType)t);
        g_api.ctor_default[t] = g_api.get_ptr_ctor((GDExtensionVariantType)t, 0);
        g_api.dtor[t] = g_api.get_ptr_dtor((GDExtensionVariantType)t);
    }

    GdOpaque sn_resize = {0};
    g_api.string_name_new_latin1(&sn_resize, "resize", 0);
    g_api.pba_resize = g_api.get_ptr_builtin_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &sn_resize, 848867239);
    g_api.psa_resize = g_api.get_ptr_builtin_method(GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY, &sn_resize, 848867239);
    g_api.array_resize = g_api.get_ptr_builtin_method(GDEXTENSION_VARIANT_TYPE_ARRAY, &sn_resize, 848867239);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&sn_resize);

    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    r_initialization->initialize = initialize_bgi_module;
    r_initialization->deinitialize = deinitialize_bgi_module;
    return 1;
}
