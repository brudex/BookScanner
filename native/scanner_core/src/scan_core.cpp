#include "bookscanner/scan_core.hpp"

#include <algorithm>
#include <cmath>
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

namespace bookscanner {
namespace {

struct Scored {
  Quad quad;
  double score = 0;
};

double dist(const cv::Point2f& a, const cv::Point2f& b) {
  const double dx = a.x - b.x;
  const double dy = a.y - b.y;
  return std::sqrt(dx * dx + dy * dy);
}

Quad order_corners(const std::vector<cv::Point2f>& pts) {
  Quad q;
  double min_sum = 1e9, max_sum = -1e9, min_diff = 1e9, max_diff = -1e9;
  cv::Point2f tl, tr, br, bl;
  for (const auto& p : pts) {
    const double s = p.x + p.y;
    const double d = p.x - p.y;
    if (s < min_sum) {
      min_sum = s;
      tl = p;
    }
    if (s > max_sum) {
      max_sum = s;
      br = p;
    }
    if (d > max_diff) {
      max_diff = d;
      tr = p;
    }
    if (d < min_diff) {
      min_diff = d;
      bl = p;
    }
  }
  q.tl = {tl.x, tl.y};
  q.tr = {tr.x, tr.y};
  q.br = {br.x, br.y};
  q.bl = {bl.x, bl.y};
  return q;
}

double polygon_area(const Quad& q) {
  const Point pts[4] = {q.tl, q.tr, q.br, q.bl};
  double sum = 0;
  for (int i = 0; i < 4; ++i) {
    const Point& a = pts[i];
    const Point& b = pts[(i + 1) % 4];
    sum += a.x * b.y - b.x * a.y;
  }
  return std::abs(sum) / 2.0;
}

bool nearly_full_frame(const Quad& q) {
  return q.tl.x < 0.03 && q.tl.y < 0.03 && q.tr.x > 0.97 && q.tr.y < 0.03 &&
         q.br.x > 0.97 && q.br.y > 0.97 && q.bl.x < 0.03 && q.bl.y > 0.97;
}

double score_quad(const Quad& q, int w, int h) {
  const double area = polygon_area(q);
  if (area < 0.12 || area > 0.96) return 0;
  if (nearly_full_frame(q)) return 0;
  const double cx = (q.tl.x + q.tr.x + q.br.x + q.bl.x) / 4.0 - 0.5;
  const double cy = (q.tl.y + q.tr.y + q.br.y + q.bl.y) / 4.0 - 0.5;
  const double center = std::clamp(1.0 - 2.0 * std::sqrt(cx * cx + cy * cy), 0.15, 1.0);
  const double top = dist({q.tl.x * w, q.tl.y * h}, {q.tr.x * w, q.tr.y * h});
  const double bot = dist({q.bl.x * w, q.bl.y * h}, {q.br.x * w, q.br.y * h});
  const double left = dist({q.tl.x * w, q.tl.y * h}, {q.bl.x * w, q.bl.y * h});
  const double right = dist({q.tr.x * w, q.tr.y * h}, {q.br.x * w, q.br.y * h});
  const double aspect = std::min(top, bot) / std::max(top, bot);
  const double sides = std::min(left, right) / std::max(left, right);
  return area * center * aspect * sides;
}

Detection detect_mat(const cv::Mat& gray_in, int max_dim) {
  Detection out;
  if (gray_in.empty()) {
    out.rejection = "empty";
    return out;
  }
  cv::Mat gray;
  const double scale = static_cast<double>(max_dim) / std::max(gray_in.cols, gray_in.rows);
  if (scale < 1.0) {
    cv::resize(gray_in, gray, cv::Size(), scale, scale, cv::INTER_AREA);
  } else {
    gray = gray_in;
  }
  cv::GaussianBlur(gray, gray, cv::Size(5, 5), 0);
  const double median = cv::mean(gray)[0];
  const double lower = std::max(10.0, 0.66 * median);
  const double upper = std::min(255.0, 1.33 * median * 1.5);
  cv::Mat edges;
  cv::Canny(gray, edges, lower, upper);
  cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
  cv::morphologyEx(edges, edges, cv::MORPH_CLOSE, kernel);

  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(edges, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
  std::sort(contours.begin(), contours.end(), [](const auto& a, const auto& b) {
    return cv::contourArea(a) > cv::contourArea(b);
  });

  Scored best;
  const int limit = static_cast<int>(std::min(contours.size(), size_t{12}));
  for (int i = 0; i < limit; ++i) {
    std::vector<cv::Point> approx;
    const double peri = cv::arcLength(contours[i], true);
    cv::approxPolyDP(contours[i], approx, 0.02 * peri, true);
    if (approx.size() != 4) continue;
    if (!cv::isContourConvex(approx)) continue;
    std::vector<cv::Point2f> pts(4);
    for (int k = 0; k < 4; ++k) {
      pts[k] = cv::Point2f(static_cast<float>(approx[k].x) / gray.cols,
                           static_cast<float>(approx[k].y) / gray.rows);
    }
    const Quad q = order_corners(pts);
    const double s = score_quad(q, gray.cols, gray.rows);
    if (s > best.score) {
      best.score = s;
      best.quad = q;
    }
  }
  if (best.score < kMinDetectionConfidence) {
    out.rejection = "low_confidence";
    return out;
  }
  out.found = true;
  out.quad = best.quad;
  out.confidence = std::min(1.0, best.score);
  return out;
}

cv::Mat warp_quad(const cv::Mat& src, const Quad& q) {
  const float w = static_cast<float>(src.cols);
  const float h = static_cast<float>(src.rows);
  cv::Point2f src_pts[4] = {
      {static_cast<float>(q.tl.x * w), static_cast<float>(q.tl.y * h)},
      {static_cast<float>(q.tr.x * w), static_cast<float>(q.tr.y * h)},
      {static_cast<float>(q.br.x * w), static_cast<float>(q.br.y * h)},
      {static_cast<float>(q.bl.x * w), static_cast<float>(q.bl.y * h)},
  };
  const double top = dist(src_pts[0], src_pts[1]);
  const double bot = dist(src_pts[3], src_pts[2]);
  const double left = dist(src_pts[0], src_pts[3]);
  const double right = dist(src_pts[1], src_pts[2]);
  const int out_w = std::clamp(static_cast<int>((top + bot) / 2), 1, 1 << 16);
  const int out_h = std::clamp(static_cast<int>((left + right) / 2), 1, 1 << 16);
  cv::Point2f dst_pts[4] = {
      {0.f, 0.f},
      {static_cast<float>(out_w - 1), 0.f},
      {static_cast<float>(out_w - 1), static_cast<float>(out_h - 1)},
      {0.f, static_cast<float>(out_h - 1)},
  };
  cv::Mat M = cv::getPerspectiveTransform(src_pts, dst_pts);
  cv::Mat out;
  cv::warpPerspective(src, out, M, cv::Size(out_w, out_h));
  return out;
}

cv::Mat normalize_illumination(const cv::Mat& src) {
  cv::Mat small;
  const double scale = 300.0 / src.cols;
  cv::resize(src, small, cv::Size(300, std::max(1, static_cast<int>(src.rows * scale))));
  cv::Mat blur;
  cv::GaussianBlur(small, blur, cv::Size(0, 0), 12);
  cv::Mat bg;
  cv::resize(blur, bg, src.size(), 0, 0, cv::INTER_LINEAR);
  cv::Mat src_f, bg_f;
  src.convertTo(src_f, CV_32FC3);
  bg.convertTo(bg_f, CV_32FC3);
  cv::Mat out_f;
  cv::divide(src_f, bg_f + 1.0f, out_f);
  out_f *= 235.0f;
  cv::Mat out;
  out_f.convertTo(out, CV_8UC3);
  return out;
}

cv::Mat apply_filter(const cv::Mat& src, int filter) {
  switch (filter) {
    case 1: {  // enhanced color
      cv::Mat ycrcb;
      cv::cvtColor(src, ycrcb, cv::COLOR_BGR2YCrCb);
      std::vector<cv::Mat> ch;
      cv::split(ycrcb, ch);
      cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(2.0, cv::Size(8, 8));
      clahe->apply(ch[0], ch[0]);
      cv::merge(ch, ycrcb);
      cv::Mat out;
      cv::cvtColor(ycrcb, out, cv::COLOR_YCrCb2BGR);
      return out;
    }
    case 2: {
      cv::Mat g;
      cv::cvtColor(src, g, cv::COLOR_BGR2GRAY);
      cv::Mat out;
      cv::cvtColor(g, out, cv::COLOR_GRAY2BGR);
      return out;
    }
    case 3: {
      cv::Mat g;
      cv::cvtColor(src, g, cv::COLOR_BGR2GRAY);
      cv::Mat bw;
      cv::adaptiveThreshold(g, bw, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C,
                            cv::THRESH_BINARY, 15, 8);
      cv::Mat out;
      cv::cvtColor(bw, out, cv::COLOR_GRAY2BGR);
      return out;
    }
    case 4: {
      cv::Mat out;
      src.convertTo(out, -1, 1.05, 4);
      return out;
    }
    default:
      return src;
  }
}

}  // namespace

Detection detect_gray(const uint8_t* gray, int width, int height, int max_dim) {
  cv::Mat mat(height, width, CV_8UC1, const_cast<uint8_t*>(gray));
  return detect_mat(mat, max_dim);
}

Detection detect_file(const char* path, bool /*split_open_book*/) {
  cv::Mat bgr = cv::imread(path, cv::IMREAD_COLOR);
  if (bgr.empty()) {
    Detection d;
    d.rejection = "decode_failed";
    return d;
  }
  cv::Mat gray;
  cv::cvtColor(bgr, gray, cv::COLOR_BGR2GRAY);
  return detect_mat(gray, 1400);
}

bool warp_enhance_file(const char* source, const char* dest, const EnhanceOptions& opt) {
  cv::Mat bgr = cv::imread(source, cv::IMREAD_COLOR);
  if (bgr.empty()) return false;
  Quad crop;
  crop.tl = {opt.crop[0], opt.crop[1]};
  crop.tr = {opt.crop[2], opt.crop[3]};
  crop.br = {opt.crop[4], opt.crop[5]};
  crop.bl = {opt.crop[6], opt.crop[7]};
  if (opt.detect_crop) {
    cv::Mat gray;
    cv::cvtColor(bgr, gray, cv::COLOR_BGR2GRAY);
    const Detection d = detect_mat(gray, 1400);
    if (d.found) crop = d.quad;
  }
  const bool cropped = polygon_area(crop) > 0.02 && !nearly_full_frame(crop);
  cv::Mat page = cropped ? warp_quad(bgr, crop) : bgr;
  const bool needs_flatten =
      opt.remove_shadows &&
      (cropped || opt.filter == 1 || opt.filter == 2 || opt.filter == 3);
  if (needs_flatten) {
    page = normalize_illumination(page);
  }
  page = apply_filter(page, opt.filter);
  return cv::imwrite(dest, page);
}

double score_file(const char* path) {
  cv::Mat bgr = cv::imread(path, cv::IMREAD_COLOR);
  if (bgr.empty()) return 0;
  cv::Mat gray, lap;
  cv::cvtColor(bgr, gray, cv::COLOR_BGR2GRAY);
  cv::Laplacian(gray, lap, CV_64F);
  cv::Scalar mu, sigma;
  cv::meanStdDev(lap, mu, sigma);
  return std::clamp((sigma[0] * sigma[0]) / 900.0, 0.0, 1.0);
}

}  // namespace bookscanner
