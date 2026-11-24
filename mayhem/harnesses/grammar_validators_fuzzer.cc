// The table-driven push-down grammar validators generated into
// validator/cpp/htmlparser/validators/ (JSON, IP address, supported media
// query): the first byte picks one, the rest is the string to validate.
#include <cstddef>
#include <cstdint>
#include <string_view>

#include "cpp/htmlparser/validators/ipaddress.h"
#include "cpp/htmlparser/validators/json.h"
#include "cpp/htmlparser/validators/supported_media_query.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  std::string_view in(reinterpret_cast<const char*>(data + 1), size - 1);
  switch (data[0] % 3) {
    case 0: (void)htmlparser::json::Validate(in); break;
    case 1: (void)htmlparser::ipaddress::Validate(in); break;
    case 2: (void)htmlparser::css::Validate(in); break;
  }
  return 0;
}
