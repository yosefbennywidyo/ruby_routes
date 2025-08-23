# Changelog

## 2.3.0 - 2025-09-02

- Refactoring: Improved code organization, naming, and maintainability across router, route, segment, and utility modules.
- Documentation: Enhanced documentation for clarity and consistency in UrlHelpers, Constant, and other modules.
- Performance: Optimizations in caching strategies, parameter handling, and HTTP method normalization.
- Additions: New utility modules (InflectorUtility, MethodUtility), constants, and comprehensive tests.
- Fixes: Bug fixes in route insertion, constraint validation, and parameter handling.

## 1.1.0 - 2025-08-17

- Route Matching Optimization: Reduced route matching time by ~40-50% through optimized cache key building and method normalization
- Memory Usage Reduction: Decreased object allocations by ~30-40% in hot paths through thread-local hash reuse and frozen string optimizations
- Cache Performance: Enhanced recognition cache with better hit rates (8192 entries) and simplified LRU eviction strategy
- RadixTree Traversal: Streamlined path splitting and traversal logic with fast-path optimizations for common route patterns (1-3 segments)
- Parameter Handling: Optimized parameter extraction and merging with reduced string allocations and improved constraint validation

## 1.0.0 - 2025-08-17

### Breaking Changes

- RouteSet#match now returns frozen params (Hash). Callers that need to mutate params must call .dup explicitly.
  - Example:
    - Before: res = router.route_set.match(:get, "/users/1"); res[:params]['id'] = 'x'
    - After: res = router.route_set.match(:get, "/users/1"); params = res[:params].dup; params['id'] = 'x'
- Internal refactors may have changed load/require order for segment files; ensure `require_relative` paths are preserved if embedding in other projects.

### Enhancements

- RadixTree traversal refactored to use Segment/SegmentMatcher strategies.
- Segment classes extracted into `lib/ruby_routes/segments/` (Static, Dynamic, Wildcard).
- Node traversal logic encapsulated in `Node#traverse_for`.
- Recognition cache improvements and more stable lookup keys (path-only caching).
- SmallLru: strategies extracted to top-level classes and exposed as singletons for lower allocations.
- RouteSet: added collection helpers (size, length, empty?, routes, clear!, find_named_route, generate_path, generate_path_from_route).

### Bug Fixes

- Fixed missing RouteSet API methods that prevented route insertion and lookup.
- Fixed RadixTree#add/find to correctly insert and locate routes for all segment types.
- Fixed various require/load ordering issues for segment files.

### Performance

- Reduced exception churn in benchmarks and lowered per-route LRU evictions by increasing sensible defaults.
- Reduced allocations by returning frozen cached params and using singleton strategy objects.

### Migration Notes

- Update any code that mutates route params returned by RouteSet#match to call `.dup` first.
- If you previously relied on internal classes (Segments, Node internals), review usages — these were refactored for encapsulation and lower allocations.

## 0.2.0 — 2025-08-17

- Performance: use radix-tree params directly in `RubyRoutes::RouteSet#match` to avoid reparsing paths.
- Performance: faster path-splitting in `RubyRoutes::RadixTree#find`.
- Path generation: tokenized templates + bounded LRU cache `RubyRoutes::Route#generate_path`.
- Caching: adaptive small LRU to avoid thrash (`RubyRoutes::Route::SmallLru`).
- Encoding: cheap safe-ASCII test before `URI.encode_www_form_component`.
- Constraint checks: lightweight checks moved into tree traversal for early rejection.
- Misc: avoid repeated string upcasing in `RubyRoutes::Node#get_handler`.
