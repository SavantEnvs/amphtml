// htmlparser fragment/option modes + renderer: bytes 0-1 pick ParseOptions
// flags and a fragment context element; the rest is parsed and re-rendered.
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string_view>

#include "cpp/htmlparser/atom.h"
#include "cpp/htmlparser/node.h"
#include "cpp/htmlparser/parser.h"
#include "cpp/htmlparser/renderer.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 2) return -1;
  htmlparser::ParseOptions opts;
  opts.scripting = data[0] & 1;
  opts.frameset_ok = data[0] & 2;
  opts.record_node_offsets = data[0] & 4;
  opts.record_attribute_offsets = data[0] & 8;
  opts.count_num_terms_in_text_node = data[0] & 16;
  bool fragment = data[0] & 32;
  static const htmlparser::Atom kContexts[] = {
      htmlparser::Atom::BODY, htmlparser::Atom::DIV, htmlparser::Atom::TABLE,
      htmlparser::Atom::TR, htmlparser::Atom::SELECT, htmlparser::Atom::TEMPLATE,
      htmlparser::Atom::SVG, htmlparser::Atom::MATH, htmlparser::Atom::TEXTAREA,
      htmlparser::Atom::SCRIPT, htmlparser::Atom::STYLE, htmlparser::Atom::HTML,
      htmlparser::Atom::HEAD, htmlparser::Atom::FRAMESET, htmlparser::Atom::TITLE,
      htmlparser::Atom::NOSCRIPT};
  std::string_view html(reinterpret_cast<const char*>(data + 2), size - 2);
  std::stringbuf buf;
  if (fragment) {
    htmlparser::Node context(htmlparser::NodeType::ELEMENT_NODE,
                             kContexts[data[1] % 16]);
    auto doc = htmlparser::ParseFragmentWithOptions(html, opts, &context);
    if (doc) {
      for (htmlparser::Node* n : doc->FragmentNodes()) {
        htmlparser::Renderer::Render(n, &buf);
      }
    }
  } else {
    auto doc = htmlparser::ParseWithOptions(html, opts);
    if (doc && doc->RootNode()) htmlparser::Renderer::Render(doc->RootNode(), &buf);
  }
  return 0;
}
