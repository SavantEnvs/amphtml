// JSON parser (validator/cpp/htmlparser/json/json.cc) in both string modes.
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

#include "cpp/htmlparser/json/json.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string_view in(reinterpret_cast<const char*>(data), size);
  for (bool refs : {false, true}) {
    htmlparser::json::ParseOptions opts;
    opts.use_string_references = refs;
    auto obj = htmlparser::json::Parse(in, opts);
  }
  return 0;
}
