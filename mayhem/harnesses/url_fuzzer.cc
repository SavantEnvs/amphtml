// URL parser (validator/cpp/htmlparser/url.cc).
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

#include "cpp/htmlparser/url.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string_view in(reinterpret_cast<const char*>(data), size);
  htmlparser::URL url(in);
  if (url.is_valid()) {
    (void)url.protocol(); (void)url.hostname(); (void)url.login();
    (void)url.port(); (void)url.path_params_fragment(); (void)url.has_protocol();
  }
  (void)htmlparser::URL::ProtocolStrict(in);
  return 0;
}
