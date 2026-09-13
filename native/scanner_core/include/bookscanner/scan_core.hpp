#pragma once

#include <cstdint>
#include <string>
#include <vector>

// Shared flat-document vision API. Android and iOS adapters convert
// platform buffers/paths into this C ABI; Flutter never sees OpenCV types.
//
// Linked against pinned OpenCV 4.11.0 (Apache-2.0). Algorithm version is
// independent of the OpenCV soname so golden tests can pin both.

namespace bookscanner {

struct Point {
  double x = 0;
  double y = 0;
};

struct Quad {
  Point tl, tr, br, bl;
};

struct Detection {
  bool found = false;
  Quad quad{};
  double confidence = 0;
  const char* rejection = "";
};

struct EnhanceOptions {
  int filter = 0;  // 0 original, 1 enhancedColor, 2 grayscale, 3 bw, 4 photo
  bool detect_crop = false;
  bool split_open_book = false;
  bool remove_shadows = true;
  double crop[8] = {0, 0, 1, 0, 1, 1, 0, 1};
};

constexpr const char* kOpenCvVersion = "4.11.0";
constexpr const char* kAlgorithmVersion = "1.0.0";
constexpr double kMinDetectionConfidence = 0.45;

Detection detect_gray(const uint8_t* gray, int width, int height, int max_dim);
Detection detect_file(const char* path, bool split_open_book);
bool warp_enhance_file(const char* source, const char* dest, const EnhanceOptions& opt);
double score_file(const char* path);

}  // namespace bookscanner
