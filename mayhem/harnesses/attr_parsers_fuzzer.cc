// AMP attribute-value parsers in validator/cpp/engine: srcset, layout /
// width / height (CssLength), sizes, viewport content, and the UTF-16 offset
// helpers. The first byte selects the parser; the rest is the attribute value.
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

#include "cpp/engine/parse-layout-sizes.h"
#include "cpp/engine/parse-layout.h"
#include "cpp/engine/parse-srcset.h"
#include "cpp/engine/parse-viewport.h"
#include "cpp/engine/utf8-util.h"

namespace pl = amp::validator::parse_layout;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  std::string v(reinterpret_cast<const char*>(data + 1), size - 1);
  switch (data[0] % 6) {
    case 0: {
      auto r = amp::validator::parse_srcset::ParseSourceSet(v);
      (void)r;
      break;
    }
    case 1: {
      pl::CssLength len(v, data[0] & 8, data[0] & 16);
      if (len.is_valid) (void)pl::GetCssLengthStyle(len, "width");
      break;
    }
    case 2: {
      // layout \0 width \0 height \0 tagname
      std::string_view rest(v);
      std::string_view parts[4];
      for (int i = 0; i < 4; ++i) {
        size_t p = rest.find('\0');
        parts[i] = rest.substr(0, p);
        rest = p == std::string_view::npos ? std::string_view() : rest.substr(p + 1);
      }
      pl::CssLength w, h;
      auto layout = pl::ParseAndCalculateLayout(parts[0], parts[1], parts[2],
                                                parts[3], data[0] & 8,
                                                data[0] & 16, &w, &h);
      (void)pl::GetLayoutClass(layout);
      (void)pl::GetLayoutName(layout);
      break;
    }
    case 3: {
      amp::validator::parse_layout_sizes::CssSizes sizes(v);
      (void)sizes;
      break;
    }
    case 4: {
      auto m = amp::validator::parse_viewport::ParseContent(v);
      (void)m;
      break;
    }
    case 5: {
      int64_t n = amp::validator::utf8_util::Utf16StrLen(v);
      (void)amp::validator::utf8_util::Utf16OffsetToByteOffset(v, n / 2);
      break;
    }
  }
  return 0;
}
