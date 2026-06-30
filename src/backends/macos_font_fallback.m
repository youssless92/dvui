#import <CoreFoundation/CoreFoundation.h>
#import <CoreText/CoreText.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H


// static int dvui_copy_font_path_if_usable(CTFontRef font, char *out, size_t out_len) {
//     if (!font || !out || out_len == 0) return 0;
static int dvui_copy_cfstring_utf8(CFStringRef str, char *out, size_t out_len) {
    if (!str || !out || out_len == 0) return 0;
    out[0] = 0;
    return CFStringGetCString(str, out, out_len, kCFStringEncodingUTF8) ? 1 : 0;
}

    // CFURLRef url = CTFontCopyAttribute(font, kCTFontURLAttribute);
    // if (!url) return 0;

static int dvui_font_face_index_for_postscript_name(
    const char *path,
    const char *postscript_name,
    uint32_t *out_face_index
) {
    if (!path || !out_face_index) return 0;

    *out_face_index = 0;

    FT_Library lib = NULL;
    FT_Face face = NULL;

    if (FT_Init_FreeType(&lib) != 0) return 0;

    if (FT_New_Face(lib, path, -1, &face) != 0) {
        FT_Done_FreeType(lib);
        return 0;
    }

    const FT_Long num_faces = face->num_faces;
    FT_Done_Face(face);
    face = NULL;

    if (num_faces <= 1) {
        FT_Done_FreeType(lib);
        *out_face_index = 0;
        return 1;
    }

    if (!postscript_name || postscript_name[0] == '\0') {
        FT_Done_FreeType(lib);
        return 0;
    }

    for (FT_Long i = 0; i < num_faces; ++i) {
        if (FT_New_Face(lib, path, i, &face) != 0) {
            continue;
        }

        const char *candidate = FT_Get_Postscript_Name(face);
        if (candidate && strcmp(candidate, postscript_name) == 0) {
            *out_face_index = (uint32_t)i;
            FT_Done_Face(face);
            FT_Done_FreeType(lib);
            return 1;
        }

        FT_Done_Face(face);
        face = NULL;
    }

    FT_Done_FreeType(lib);
    return 0;
}

static int dvui_copy_font_identity_if_usable(CTFontRef font, char *out_path, size_t out_path_len, uint32_t *out_face_index) {
    if (!font || !out_path || out_path_len == 0 || !out_face_index) return 0;
    out_path[0] = 0;
    *out_face_index = 0;

    CFURLRef url = (CFURLRef)CTFontCopyAttribute(font, kCTFontURLAttribute);
    if (!url) return 0;

    char path[4096];
    Boolean ok = CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof(path));
    CFRelease(url);
    if (!ok) return 0;
    printf("font path: %s\n", path);
    // if (strcmp(path, "/System/Library/Fonts/Apple Color Emoji.ttc") == 0) {
    //     return 0;
    // }

    if (strncmp(
            path,
            "/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/",
            strlen("/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/")
        ) == 0) {
        return 0;
    }
    char postscript_name[512];
    postscript_name[0] = 0;

    CFStringRef ps_name = (CFStringRef)CTFontCopyAttribute(font, kCTFontNameAttribute);
    if (ps_name) {
        (void)dvui_copy_cfstring_utf8(ps_name, postscript_name, sizeof(postscript_name));
        CFRelease(ps_name);
    }

    uint32_t face_index = 0;
    if (!dvui_font_face_index_for_postscript_name(path, postscript_name, &face_index)) return 0;

    size_t len = strlen(path);
    // if (len + 1 > out_len) return 0;
    // memcpy(out, path, len + 1);
    if (len + 1 > out_path_len) return 0;
    memcpy(out_path, path, len + 1);
    *out_face_index = face_index;
    return 1;
}

static CTFontRef dvui_font_with_family(const char *family, double size) {
    CFStringRef family_name = CFStringCreateWithCString(kCFAllocatorDefault, family, kCFStringEncodingUTF8);
    if (!family_name) return NULL;
    CTFontRef font = CTFontCreateWithName(family_name, size, NULL);
    CFRelease(family_name);
    return font;
}

// int dvui_macos_font_path_for_codepoint(
int dvui_macos_font_identity_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    // char *out,
    // size_t out_len
    char *out_path,
    size_t out_path_len,
    uint32_t *out_face_index
) {
    // if (!out || out_len == 0) return 0;
    // out[0] = 0;
    if (!out_path || out_path_len == 0 || !out_face_index) return 0;
    out_path[0] = 0;
    *out_face_index = 0;
 
    UniChar chars[2];
    CFIndex len = 1;

    if (codepoint <= 0xFFFF) {
        chars[0] = (UniChar)codepoint;
    } else if (codepoint <= 0x10FFFF) {
        codepoint -= 0x10000;
        chars[0] = (UniChar)(0xD800 + (codepoint >> 10));
        chars[1] = (UniChar)(0xDC00 + (codepoint & 0x3FF));
        len = 2;
    } else {
        return 0;
    }

    CFStringRef sample = CFStringCreateWithCharacters(kCFAllocatorDefault, chars, len);
    if (!sample) return 0;

    CFStringRef family_name = NULL;
    CTFontRef base = NULL;

    if (family && family_len > 0) {
        family_name = CFStringCreateWithBytes(
            kCFAllocatorDefault,
            (const UInt8 *)family,
            family_len,
            kCFStringEncodingUTF8,
            false
        );
    }

    if (family_name) {
        base = CTFontCreateWithName(family_name, 12.0, NULL);
        CFRelease(family_name);
    }

    if (!base) {
        base = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 12.0, NULL);
    }

    if (!base) {
        CFRelease(sample);
        return 0;
    }

    CTFontSymbolicTraits traits = 0;
    if (bold) traits |= kCTFontBoldTrait;
    if (italic) traits |= kCTFontItalicTrait;

    CTFontRef styled = NULL;
    if (traits != 0) {
        styled = CTFontCreateCopyWithSymbolicTraits(base, 12.0, NULL, traits, traits);
    }

    CTFontRef lookup = styled ? styled : base;
    // CTFontRef fallback = CTFontCreateForString(lookup, sample, CFRangeMake(0, CFStringGetLength(sample)));
    const CFIndex sample_len = CFStringGetLength(sample);
    CTFontRef fallback = CTFontCreateForString(lookup, sample, CFRangeMake(0, sample_len));


    // CFRelease(sample);
    if (styled) CFRelease(styled);
    CFRelease(base);

    if (!fallback) return 0;

    // CFURLRef url = CTFontCopyAttribute(fallback, kCTFontURLAttribute);
    // if (dvui_copy_font_path_if_usable(fallback, out, out_len)) {
    if (dvui_copy_font_identity_if_usable(fallback, out_path, out_path_len, out_face_index)) {
        CFRelease(fallback);
        CFRelease(sample);
        return 1;
    }
    CFRelease(fallback);

    // if (!url) return 0;
    const char *cjk_families[] = {
        "PingFang SC",
        "PingFang TC",
        "Hiragino Sans",
        "Hiragino Kaku Gothic ProN",
        "Songti SC",
        "Heiti SC",
    };

    for (size_t i = 0; i < sizeof(cjk_families) / sizeof(cjk_families[0]); ++i) {
        CTFontRef probe = dvui_font_with_family(cjk_families[i], 12.0);
        if (!probe) continue;
 

    // // Boolean ok = CFURLGetFileSystemRepresentation(url, true, (UInt8 *)out, out_len);
    // // CFRelease(url);

    // // CTFontRef alt = CTFontCreateForString(probe, sample, CFRangeMake(0, CFStringGetLength(sample)));
    // CTFontRef alt = CTFontCreateForString(probe, sample, CFRangeMake(0, sample_len));

    // CFRelease(probe);
    // if (!alt) continue;

    // if (dvui_copy_font_path_if_usable(alt, out, out_len)) {
    //     CFRelease(alt);
    //     CFRelease(sample);
    //     return 1;
       CTFontRef alt = CTFontCreateForString(probe, sample, CFRangeMake(0, sample_len));
       CFRelease(probe);
       if (!alt) continue;
       if (dvui_copy_font_identity_if_usable(alt, out_path, out_path_len, out_face_index)) {
           CFRelease(alt);
           CFRelease(sample);
           return 1;
    }

    CFRelease(alt);
    }

    const char *generic_families[] = {
        "Arial Unicode MS",
        "Apple Symbols",
    };

    for (size_t i = 0; i < sizeof(generic_families) / sizeof(generic_families[0]); ++i) {
        CTFontRef probe = dvui_font_with_family(generic_families[i], 12.0);
        if (!probe) continue;
        // if (dvui_copy_font_path_if_usable(probe, out, out_len)) {
        if (dvui_copy_font_identity_if_usable(probe, out_path, out_path_len, out_face_index)) {
            CFRelease(probe);
            CFRelease(sample);
            return 1;
        }
        CFRelease(probe);
    }

        // return ok ? 1 : 0;
        CFRelease(sample);
        return 0;
}