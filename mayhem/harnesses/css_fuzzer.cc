// CSS3 syntax parser (validator/cpp/htmlparser/css/parse-css.cc) the way the
// validator drives it: tokenize, parse a stylesheet with the AMP at-rule
// config, then the URL/media-query/AMP4ADS/keyframes passes; also the inline
// style (style="...") path on a second tokenization of the same input.
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>
#include <vector>

#include "cpp/engine/keyframes-parse-css.h"
#include "cpp/engine/validator.h"
#include "cpp/htmlparser/css/amp4ads-parse-css.h"
#include "cpp/htmlparser/css/parse-css.h"
#include "cpp/htmlparser/strings.h"

using namespace htmlparser::css;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string_view in(reinterpret_cast<const char*>(data), size);
  static const CssParsingConfig* config =
      new CssParsingConfig(amp::validator::GenCssParsingConfig());
  {
    std::vector<char32_t> cp = htmlparser::Strings::Utf8ToCodepoints(in);
    std::vector<std::unique_ptr<ErrorToken>> errors;
    auto tokens = Tokenize(&cp, 1, 0, &errors);
    auto sheet = ParseAStylesheet(&tokens, *config, &errors);
    if (sheet) {
      std::vector<std::unique_ptr<ParsedCssUrl>> urls;
      ExtractUrls(*sheet, &urls, &errors);
      std::vector<const Declaration*> important;
      ExtractImportantDeclarations(*sheet, &important);
      std::vector<std::unique_ptr<Token>> types, features;
      ParseMediaQueries(*sheet, &types, &features, &errors);
      ValidateAmp4AdsCss(*sheet, &errors);
      amp::validator::parse_css::ValidateKeyframesCss(*sheet, &errors);
      (void)sheet->ToJson();
    }
  }
  {
    std::vector<char32_t> cp = htmlparser::Strings::Utf8ToCodepoints(in);
    std::vector<std::unique_ptr<ErrorToken>> errors;
    auto tokens = Tokenize(&cp, 1, 0, &errors);
    auto decls = ParseInlineStyle(&tokens, &errors);
    std::vector<std::unique_ptr<ParsedCssUrl>> urls;
    for (const auto& d : decls) ExtractUrls(*d, &urls, &errors);
  }
  return 0;
}
