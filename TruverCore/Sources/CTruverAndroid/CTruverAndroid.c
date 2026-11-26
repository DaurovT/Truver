#include "CTruverAndroid.h"
#include <time.h>

int64_t truver_monotonic_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

#ifdef __ANDROID__
#include <android/log.h>

int32_t truver_aaudio_open(int32_t input, int32_t sampleRate, int32_t channelCount, int32_t exclusive,
                           truver_aaudio_data_fn dataCallback, truver_aaudio_error_fn errorCallback,
                           void *context, AAudioStream **stream) {
    AAudioStreamBuilder *builder = NULL;
    aaudio_result_t result = AAudio_createStreamBuilder(&builder);
    if (result != AAUDIO_OK) return result;
    AAudioStreamBuilder_setDirection(builder, input ? AAUDIO_DIRECTION_INPUT : AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(builder, exclusive ? AAUDIO_SHARING_MODE_EXCLUSIVE : AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    if (channelCount > 0) AAudioStreamBuilder_setChannelCount(builder, channelCount);
    if (sampleRate > 0) AAudioStreamBuilder_setSampleRate(builder, sampleRate);
    if (input) {
        if (__builtin_available(android 29, *)) {
            AAudioStreamBuilder_setInputPreset(builder, AAUDIO_INPUT_PRESET_UNPROCESSED);
        } else {
            AAudioStreamBuilder_setInputPreset(builder, AAUDIO_INPUT_PRESET_VOICE_RECOGNITION);
        }
    } else {
        AAudioStreamBuilder_setUsage(builder, AAUDIO_USAGE_MEDIA);
        AAudioStreamBuilder_setContentType(builder, AAUDIO_CONTENT_TYPE_MUSIC);
    }
    AAudioStreamBuilder_setDataCallback(builder, dataCallback, context);
    AAudioStreamBuilder_setErrorCallback(builder, errorCallback, context);
    result = AAudioStreamBuilder_openStream(builder, stream);
    AAudioStreamBuilder_delete(builder);
    return result;
}

int32_t truver_aaudio_start(AAudioStream *stream) {
    int32_t burst = AAudioStream_getFramesPerBurst(stream);
    if (burst > 0) AAudioStream_setBufferSizeInFrames(stream, burst * 2);
    return AAudioStream_requestStart(stream);
}

void truver_aaudio_close(AAudioStream *stream) {
    if (!stream) return;
    AAudioStream_requestStop(stream);
    AAudioStream_close(stream);
}

int32_t truver_aaudio_sample_rate(AAudioStream *stream) { return AAudioStream_getSampleRate(stream); }
int32_t truver_aaudio_channel_count(AAudioStream *stream) { return AAudioStream_getChannelCount(stream); }
int32_t truver_aaudio_capacity(AAudioStream *stream) { return AAudioStream_getBufferCapacityInFrames(stream); }
int32_t truver_aaudio_is_exclusive(AAudioStream *stream) {
    return AAudioStream_getSharingMode(stream) == AAUDIO_SHARING_MODE_EXCLUSIVE;
}

int32_t truver_aaudio_is_running(AAudioStream *stream) {
    aaudio_stream_state_t state = AAudioStream_getState(stream);
    return state == AAUDIO_STREAM_STATE_STARTING || state == AAUDIO_STREAM_STATE_STARTED;
}

int64_t truver_aaudio_latency_ns(AAudioStream *stream, int32_t input) {
    int64_t framePosition = 0, timeNs = 0;
    if (AAudioStream_getTimestamp(stream, CLOCK_MONOTONIC, &framePosition, &timeNs) != AAUDIO_OK) return -1;
    int32_t rate = AAudioStream_getSampleRate(stream);
    if (rate <= 0) return -1;
    int64_t now = truver_monotonic_ns();
    if (input) {
        // Frame `framePosition` was captured at timeNs; the newest frame read is framesRead.
        int64_t newest = AAudioStream_getFramesRead(stream);
        int64_t captured = timeNs + (newest - framePosition) * 1000000000LL / rate;
        return now - captured;
    }
    // Frame `framePosition` is presented at timeNs; the next frame written is framesWritten.
    int64_t next = AAudioStream_getFramesWritten(stream);
    int64_t presented = timeNs + (next - framePosition) * 1000000000LL / rate;
    return presented - now;
}

const char *truver_aaudio_error_text(int32_t result) { return AAudio_convertResultToText(result); }

void truver_log(const char *message) { __android_log_write(ANDROID_LOG_INFO, "Truver", message); }
#endif

#ifdef __ANDROID__
// The Swift 6.4 runtime for Android is built against libc++ 21, whose std::hash calls the out-of-line
// std::__hash_memory. NDK r27–r29 ship an older libc++_shared.so without it, so an app (strict linker) fails
// to load with «cannot locate symbol _ZNSt6__ndk113__hash_memoryEPKvm». Only the Swift runtime inside this
// library calls it, so any good hash that is consistent within the process works: MurmurHash64A, like libc++.
#include <stddef.h>
#include <string.h>
__attribute__((visibility("hidden")))
size_t truver_hash_memory(const void *key, size_t len) __asm__("_ZNSt6__ndk113__hash_memoryEPKvm");
size_t truver_hash_memory(const void *key, size_t len) {
    const uint64_t m = 0xc6a4a7935bd1e995ULL;
    const int r = 47;
    uint64_t h = 0x9747b28cULL ^ (len * m);
    const unsigned char *data = (const unsigned char *)key;
    size_t blocks = len / 8;
    for (size_t i = 0; i < blocks; i++) {
        uint64_t k;
        memcpy(&k, data + i * 8, 8);
        k *= m; k ^= k >> r; k *= m;
        h ^= k; h *= m;
    }
    const unsigned char *tail = data + blocks * 8;
    switch (len & 7) {
    case 7: h ^= (uint64_t)tail[6] << 48; /* fallthrough */
    case 6: h ^= (uint64_t)tail[5] << 40; /* fallthrough */
    case 5: h ^= (uint64_t)tail[4] << 32; /* fallthrough */
    case 4: h ^= (uint64_t)tail[3] << 24; /* fallthrough */
    case 3: h ^= (uint64_t)tail[2] << 16; /* fallthrough */
    case 2: h ^= (uint64_t)tail[1] << 8;  /* fallthrough */
    case 1: h ^= (uint64_t)tail[0]; h *= m;
    }
    h ^= h >> r; h *= m; h ^= h >> r;
    return (size_t)h;
}
#endif
