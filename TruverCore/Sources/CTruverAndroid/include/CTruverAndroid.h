#ifndef C_TRUVER_ANDROID_H
#define C_TRUVER_ANDROID_H

#include <stdint.h>

// Thin C layer over AAudio (Android 10+). AAudio declares its constants as anonymous enums, which are awkward
// from Swift; these helpers take plain ints and build float PCM streams the way the Truver audio host needs.
// On other platforms the header is empty.

#ifdef __ANDROID__
#include <aaudio/AAudio.h>

typedef aaudio_data_callback_result_t (*truver_aaudio_data_fn)(AAudioStream *stream, void *context,
                                                               void *audioData, int32_t numFrames);
typedef void (*truver_aaudio_error_fn)(AAudioStream *stream, void *context, aaudio_result_t error);

/// Opens a float PCM stream with low-latency performance mode. `input` 0 = output (media usage), 1 = input
/// (unprocessed preset: no AGC or noise suppression — the tuner needs the raw signal, like `.measurement` on iOS).
/// `sampleRate` 0 lets the device choose. Returns an AAudio result code; `*stream` is set on success.
int32_t truver_aaudio_open(int32_t input, int32_t sampleRate, int32_t channelCount, int32_t exclusive,
                           truver_aaudio_data_fn dataCallback, truver_aaudio_error_fn errorCallback,
                           void *context, AAudioStream **stream);

/// Starts the stream and sets a double-burst buffer (low latency without underruns).
int32_t truver_aaudio_start(AAudioStream *stream);
void truver_aaudio_close(AAudioStream *stream);

int32_t truver_aaudio_sample_rate(AAudioStream *stream);
int32_t truver_aaudio_channel_count(AAudioStream *stream);
int32_t truver_aaudio_capacity(AAudioStream *stream);
int32_t truver_aaudio_is_exclusive(AAudioStream *stream);
/// 1 while the stream is starting or started.
int32_t truver_aaudio_is_running(AAudioStream *stream);

/// Output: nanoseconds from now until the next frame written is heard. Input: how long ago the newest frame
/// read was captured. -1 when the stream has no timestamp yet.
int64_t truver_aaudio_latency_ns(AAudioStream *stream, int32_t input);

const char *truver_aaudio_error_text(int32_t result);

/// Log to logcat under the tag "Truver".
void truver_log(const char *message);
#endif

/// CLOCK_MONOTONIC in nanoseconds (the clock AAudio timestamps use).
int64_t truver_monotonic_ns(void);

#endif
