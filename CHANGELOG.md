# Changelog

## 0.2.0 — 2025-08-17

- Performance: use radix-tree params directly in `RubyRoutes::RouteSet#match` to avoid reparsing paths.
- Performance: faster path-splitting in `RubyRoutes::RadixTree#find`.
- Path generation: tokenized templates + bounded LRU cache `RubyRoutes::Route#generate_path`.
- Caching: adaptive small LRU to avoid thrash (`RubyRoutes::Route::SmallLru`).
- Encoding: cheap safe-ASCII test before `URI.encode_www_form_component`.
- Constraint checks: lightweight checks moved into tree traversal for early rejection.
- Misc: avoid repeated string upcasing in `RubyRoutes::Node#get_handler`.
