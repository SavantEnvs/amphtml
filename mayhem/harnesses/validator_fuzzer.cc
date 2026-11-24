// Whole AMP validator: amp::validator::Validate(html, format). The first byte
// picks the HtmlFormat (AMP, AMP4ADS, AMP4EMAIL), the rest is the document.
#include <cstddef>
#include <cstdint>
#include <string_view>

#include "cpp/engine/validator.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  static const amp::validator::HtmlFormat_Code kFormats[] = {
      amp::validator::HtmlFormat::AMP, amp::validator::HtmlFormat::AMP4ADS,
      amp::validator::HtmlFormat::AMP4EMAIL};
  auto fmt = kFormats[data[0] % 3];
  std::string_view html(reinterpret_cast<const char*>(data + 1), size - 1);
  auto result = amp::validator::Validate(html, fmt);
  (void)result.status();
  return 0;
}
