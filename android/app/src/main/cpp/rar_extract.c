// Native RAR/CBR extractor backed by libarchive (RAR4 + RAR5).
//
// Exposes one JNI entry point used by com.rekindle.app.core.download.RarExtractor:
// it opens a .cbr/.rar file, writes every image entry to the given output
// directory as `rNNNNN.<ext>`, and returns an interleaved String[] of
// [originalEntryPath, writtenFileName, …] so the Kotlin side can order pages by
// their original archive path (mirroring the CBZ path's lexicographic sort).

#include <jni.h>
#include <archive.h>
#include <archive_entry.h>
#include <android/log.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LOG_TAG "RekindleRar"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Lower-cases the extension of `name` into `out` (max 7 chars). Returns 1 if the
// extension is a supported image type.
static int image_ext(const char *name, char *out) {
    const char *dot = strrchr(name, '.');
    out[0] = '\0';
    if (!dot) return 0;
    int i = 0;
    for (const char *p = dot + 1; *p && i < 7; ++p) {
        out[i++] = (char) tolower((unsigned char) *p);
    }
    out[i] = '\0';
    return strcmp(out, "jpg") == 0 || strcmp(out, "jpeg") == 0 ||
           strcmp(out, "png") == 0 || strcmp(out, "webp") == 0 ||
           strcmp(out, "gif") == 0 || strcmp(out, "bmp") == 0;
}

// Streams the current entry's data to `path`. Returns 0 on success.
static int write_entry(struct archive *a, const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    const void *buff;
    size_t size;
    la_int64_t offset;
    for (;;) {
        int r = archive_read_data_block(a, &buff, &size, &offset);
        if (r == ARCHIVE_EOF) { fclose(f); return 0; }
        // ARCHIVE_WARN is a recoverable success (data still valid); only ARCHIVE_FAILED/FATAL abort.
        if (r < ARCHIVE_WARN) { fclose(f); return -1; }
        if (fwrite(buff, 1, size, f) != size) { fclose(f); return -1; }
    }
}

JNIEXPORT jobjectArray JNICALL
Java_com_rekindle_app_core_download_RarExtractor_nativeExtract(
        JNIEnv *env, jobject thiz, jstring jArchivePath, jstring jOutDir) {
    (void) thiz;
    const char *archivePath = (*env)->GetStringUTFChars(env, jArchivePath, NULL);
    const char *outDir = (*env)->GetStringUTFChars(env, jOutDir, NULL);
    if (archivePath == NULL || outDir == NULL) {
        if (archivePath) (*env)->ReleaseStringUTFChars(env, jArchivePath, archivePath);
        if (outDir) (*env)->ReleaseStringUTFChars(env, jOutDir, outDir);
        return NULL; // OOM obtaining the strings; let the Kotlin caller treat it as "no pages"
    }

    struct archive *a = archive_read_new();
    archive_read_support_format_rar(a);   // RAR4
    archive_read_support_format_rar5(a);  // RAR5

    jobjectArray result = NULL;

    if (archive_read_open_filename(a, archivePath, 10240) == ARCHIVE_OK) {
        size_t cap = 64, n = 0;
        // Flat [entryPath, fileName, …] pairs.
        char **pairs = (char **) malloc(sizeof(char *) * cap * 2);
        struct archive_entry *entry;
        int idx = 0;

        while (pairs != NULL && archive_read_next_header(a, &entry) == ARCHIVE_OK) {
            const char *ename = archive_entry_pathname(entry);
            char ext[8];
            if (ename == NULL ||
                archive_entry_filetype(entry) == AE_IFDIR ||
                !image_ext(ename, ext)) {
                archive_read_data_skip(a);
                continue;
            }

            char fileName[32];
            snprintf(fileName, sizeof(fileName), "r%05d.%s", idx, ext);
            char fullPath[4096];
            snprintf(fullPath, sizeof(fullPath), "%s/%s", outDir, fileName);

            if (write_entry(a, fullPath) != 0) {
                LOGE("write failed for %s", ename);
                remove(fullPath); // drop the half-written page
                // Partial extraction: abort the whole archive so the Kotlin caller falls back
                // (retry / server stream) instead of caching a silently-truncated page set.
                for (size_t k = 0; k < n * 2; k++) free(pairs[k]);
                free(pairs);
                pairs = NULL;
                break;
            }

            if (n >= cap) {
                cap *= 2;
                char **grown = (char **) realloc(pairs, sizeof(char *) * cap * 2);
                if (grown == NULL) break;
                pairs = grown;
            }
            pairs[n * 2] = strdup(ename);
            pairs[n * 2 + 1] = strdup(fileName);
            n++;
            idx++;
        }

        // pairs == NULL means the loop aborted on a write failure (result stays NULL -> caller retries).
        if (pairs != NULL) {
            jclass strCls = (*env)->FindClass(env, "java/lang/String");
            result = (*env)->NewObjectArray(env, (jsize) (n * 2), strCls, NULL);
            for (size_t i = 0; i < n * 2; i++) {
                if (pairs[i] != NULL) {
                    jstring s = (*env)->NewStringUTF(env, pairs[i]);
                    (*env)->SetObjectArrayElement(env, result, (jsize) i, s);
                    (*env)->DeleteLocalRef(env, s);
                    free(pairs[i]);
                }
            }
            free(pairs);
        }
    } else {
        LOGE("open failed: %s", archive_error_string(a));
    }

    archive_read_free(a);
    (*env)->ReleaseStringUTFChars(env, jArchivePath, archivePath);
    (*env)->ReleaseStringUTFChars(env, jOutDir, outDir);
    return result;
}
