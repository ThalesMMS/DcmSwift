#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t width;
    uint32_t height;
    uint16_t components;
    uint16_t bit_depth;
    uint8_t is_signed;
    uint8_t is_float;
    uint16_t reserved;
    size_t pixel_count;
    uint8_t *pixels8;
    uint16_t *pixels16;
} ojph_decoded_image;

typedef enum {
    OJPH_STATUS_OK = 0,
    OJPH_STATUS_UNSUPPORTED = 1,
    OJPH_STATUS_ERROR = 2
} ojph_status;

/// Decodes a JPEG 2000 / HTJ2K codestream into 8-bit or 16-bit interleaved pixels.
/// On success the caller owns the returned pixel buffer(s) and must release them
/// with `ojph_free_image`.
ojph_status ojph_decode_image(const uint8_t *codestream,
                              size_t length,
                              ojph_decoded_image *out_image,
                              char *error_message,
                              size_t error_length);

/// Releases buffers allocated during decoding and zeroes the structure.
void ojph_free_image(ojph_decoded_image *image);

#ifdef __cplusplus
}
#endif
