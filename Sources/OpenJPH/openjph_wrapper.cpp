#include "openjph_wrapper.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <new>
#include <string>
#include <vector>

#include "common/ojph_codestream.h"
#include "common/ojph_file.h"
#include "common/ojph_mem.h"
#include "common/ojph_message.h"
#include "common/ojph_params.h"

namespace {

using ojph::codestream;
using ojph::mem_infile;
using ojph::param_cod;
using ojph::param_siz;
using ojph::point;
using ojph::si32;
using ojph::ui32;

inline void write_error(char *dst, size_t max_len, const char *msg) {
  if (!dst || max_len == 0 || !msg) {
    return;
  }
  size_t to_copy = std::min(max_len - 1, std::strlen(msg));
  std::memcpy(dst, msg, to_copy);
  dst[to_copy] = '\0';
}

struct ImageBuffers {
  std::vector<uint8_t> u8;
  std::vector<uint16_t> u16;
};

inline uint16_t clamp_to_uint16(int32_t value, uint32_t bit_depth, bool is_signed) {
  if (bit_depth >= 16 && !is_signed) {
    if (value < 0) value = 0;
    if (value > 0xFFFF) value = 0xFFFF;
    return static_cast<uint16_t>(value);
  }
  if (is_signed) {
    const int32_t min_val = -(1 << (bit_depth - 1));
    const int32_t max_val = (1 << (bit_depth - 1)) - 1;
    if (value < min_val) value = min_val;
    if (value > max_val) value = max_val;
    int16_t signed_val = static_cast<int16_t>(value);
    return static_cast<uint16_t>(signed_val);
  } else {
    const int32_t max_val = (bit_depth >= 16) ? 0xFFFF : ((1 << bit_depth) - 1);
    if (value < 0) value = 0;
    if (value > max_val) value = max_val;
    return static_cast<uint16_t>(value);
  }
}

inline uint8_t clamp_to_uint8(int32_t value, uint32_t bit_depth) {
  const int32_t max_val = (bit_depth >= 8) ? 0xFF : ((1 << bit_depth) - 1);
  if (value < 0) value = 0;
  if (value > max_val) value = max_val;
  return static_cast<uint8_t>(value);
}

inline uint8_t float_to_uint8(float value, uint32_t bit_depth) {
  int32_t rounded = static_cast<int32_t>(std::lround(value));
  return clamp_to_uint8(rounded, bit_depth);
}

inline uint16_t float_to_uint16(float value, uint32_t bit_depth, bool is_signed) {
  int32_t rounded = static_cast<int32_t>(std::lround(value));
  return clamp_to_uint16(rounded, bit_depth, is_signed);
}

bool decode_codestream(const uint8_t *codestream_data,
                       size_t length,
                       ojph_decoded_image *out_image,
                       char *error_message,
                       size_t error_length) {
  mem_infile input;
  input.open(codestream_data, length);

  codestream cs;
  cs.enable_resilience();
  cs.read_headers(&input);

  param_siz siz = cs.access_siz();
  const ui32 num_components = siz.get_num_components();
  if (num_components == 0) {
    write_error(error_message, error_length, "codestream has no components");
    return false;
  }

  const ui32 width = siz.get_recon_width(0);
  const ui32 height = siz.get_recon_height(0);
  const point downsample0 = siz.get_downsampling(0);
  const ui32 bit_depth0 = siz.get_bit_depth(0);
  const bool signed0 = siz.is_signed(0) != 0;

  for (ui32 c = 1; c < num_components; ++c) {
    if (siz.get_recon_width(c) != width || siz.get_recon_height(c) != height) {
      write_error(error_message, error_length,
                  "subsampled components are not yet supported");
      return false;
    }
    point p = siz.get_downsampling(c);
    if (p.x != downsample0.x || p.y != downsample0.y) {
      write_error(error_message, error_length,
                  "component downsampling mismatch is not supported");
      return false;
    }
    if (siz.get_bit_depth(c) != bit_depth0) {
      write_error(error_message, error_length,
                  "mixed component bit depth is not supported");
      return false;
    }
    if ((siz.is_signed(c) != 0) != signed0) {
      write_error(error_message, error_length,
                  "mixed signed/unsigned components are not supported");
      return false;
    }
  }

  cs.set_planar(false);
  cs.create();

  const bool output_u8 = (bit_depth0 <= 8) && !signed0;
  const size_t total_samples = static_cast<size_t>(width) * height * num_components;

  ImageBuffers buffers;
  if (output_u8) {
    buffers.u8.resize(total_samples);
  } else {
    buffers.u16.resize(total_samples);
  }

  for (ui32 row = 0; row < height; ++row) {
    for (ui32 comp = 0; comp < num_components; ++comp) {
      ui32 comp_index = comp;
      ojph::line_buf *line = cs.pull(comp_index);
      if (!line) {
        write_error(error_message, error_length, "failed to pull line from codestream");
        return false;
      }
      if (comp_index != comp) {
        comp = comp_index; // keep indices in sync if library reorders
      }

      const size_t samples_in_line = std::min(static_cast<size_t>(line->size), static_cast<size_t>(width));
      const size_t base_index = (static_cast<size_t>(row) * width) * num_components + comp;

      if ((line->flags & ojph::line_buf::LFT_INTEGER) != 0) {
        const si32 *src = line->i32;
        if (output_u8) {
          uint8_t *dst = buffers.u8.data();
          for (size_t x = 0; x < samples_in_line; ++x) {
            dst[base_index + x * num_components] = clamp_to_uint8(src[x], bit_depth0);
          }
        } else {
          uint16_t *dst = buffers.u16.data();
          for (size_t x = 0; x < samples_in_line; ++x) {
            dst[base_index + x * num_components] = clamp_to_uint16(src[x], bit_depth0, signed0);
          }
        }
      } else if ((line->flags & ojph::line_buf::LFT_32BIT) != 0) {
        const float *src = line->f32;
        if (output_u8) {
          uint8_t *dst = buffers.u8.data();
          for (size_t x = 0; x < samples_in_line; ++x) {
            dst[base_index + x * num_components] = float_to_uint8(src[x], bit_depth0);
          }
        } else {
          uint16_t *dst = buffers.u16.data();
          for (size_t x = 0; x < samples_in_line; ++x) {
            dst[base_index + x * num_components] = float_to_uint16(src[x], bit_depth0, signed0);
          }
        }
      } else {
        write_error(error_message, error_length, "unsupported line buffer layout");
        return false;
      }
    }
  }

  cs.close();
  input.close();

  if (output_u8) {
    uint8_t *result = static_cast<uint8_t *>(std::malloc(buffers.u8.size()));
    if (!result) {
      write_error(error_message, error_length, "memory allocation failure");
      return false;
    }
    std::memcpy(result, buffers.u8.data(), buffers.u8.size());
    out_image->pixels8 = result;
    out_image->pixels16 = nullptr;
  } else {
    uint16_t *result = static_cast<uint16_t *>(std::malloc(buffers.u16.size() * sizeof(uint16_t)));
    if (!result) {
      write_error(error_message, error_length, "memory allocation failure");
      return false;
    }
    std::memcpy(result, buffers.u16.data(), buffers.u16.size() * sizeof(uint16_t));
    out_image->pixels8 = nullptr;
    out_image->pixels16 = result;
  }

  out_image->width = width;
  out_image->height = height;
  out_image->components = static_cast<uint16_t>(num_components);
  out_image->bit_depth = static_cast<uint16_t>(bit_depth0);
  out_image->is_signed = signed0 ? 1 : 0;
  out_image->is_float = 0;
  out_image->reserved = 0;
  out_image->pixel_count = total_samples;
  return true;
}

} // namespace

extern "C" ojph_status ojph_decode_image(const uint8_t *codestream_data,
                                          size_t length,
                                          ojph_decoded_image *out_image,
                                          char *error_message,
                                          size_t error_length) {
  if (!codestream_data || length == 0 || !out_image) {
    write_error(error_message, error_length, "invalid arguments");
    return OJPH_STATUS_ERROR;
  }

  std::memset(out_image, 0, sizeof(*out_image));

  try {
    const bool ok = decode_codestream(codestream_data, length, out_image,
                                      error_message, error_length);
    return ok ? OJPH_STATUS_OK : OJPH_STATUS_UNSUPPORTED;
  } catch (const std::exception &ex) {
    write_error(error_message, error_length, ex.what());
    ojph_free_image(out_image);
    return OJPH_STATUS_ERROR;
  } catch (...) {
    write_error(error_message, error_length, "unknown OpenJPH error");
    ojph_free_image(out_image);
    return OJPH_STATUS_ERROR;
  }
}

extern "C" void ojph_free_image(ojph_decoded_image *image) {
  if (!image) {
    return;
  }
  if (image->pixels8) {
    std::free(image->pixels8);
  }
  if (image->pixels16) {
    std::free(image->pixels16);
  }
  std::memset(image, 0, sizeof(*image));
}
