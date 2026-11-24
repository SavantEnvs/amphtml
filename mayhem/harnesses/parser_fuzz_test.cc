// Port of OSS-Fuzz's FuzzTest harness (projects/ampproject fuzz_patch.diff,
// validator/cpp/htmlparser/parser_fuzz_test.cc: FUZZ_TEST(CC_FUZZING, FuzzParser))
// as a plain libFuzzer entry point: the same htmlparser::Parser(raw_html).Parse().
#include <cstddef>
#include <cstdint>
#include <string>

#include "cpp/htmlparser/parser.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string raw_html(reinterpret_cast<const char*>(data), size);
  htmlparser::Parser parser(raw_html);
  auto doc = parser.Parse();
  return 0;
}
