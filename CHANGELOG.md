# Changelog

## 2.7.0 - 2025-09-16

### ✨ Features & Performance

* **Hybrid Matching Strategy**: Implemented a new default `HybridStrategy` that combines a fast hash-based lookup for static routes with a `RadixTree` for dynamic routes. This significantly improves performance for applications with many static paths.
* **Optimized Traversal Strategy**: Introduced `TraversalStrategy` with an "unrolled" loop for common short paths (1-3 segments) and a generic loop for longer paths. This reduces overhead and speeds up route matching across the board.
* **Memory Efficiency**: Optimized key-building, path-splitting, and method normalization to reduce object allocations in hot paths. Replaced a manual ring-buffer cache with a more robust `SmallLru` implementation.

### ♻️ Refactoring & Fixes

* **Unified Caching**: Consolidated the recognition cache logic into a single, more efficient `SmallLru` instance, removing a complex manual eviction strategy.
* **Improved Encapsulation**: Refactored `SmallLru` and its `HitStrategy` to better encapsulate cache promotion logic.
* **Robust Validation**: Hardened constraint validation to prevent errors with `nil` or unexpected values.
* **Bug Fixes**:
  * Corrected a cache eviction miscalculation to ensure the proper number of entries are retained.
  * Fixed an issue in `WildcardSegment` to prevent parameter names from being overwritten.
  * Resolved a bug in `HashBasedStrategy` to correctly normalize keys.
* **Code Quality**: Streamlined cache initialization with a `CacheSetup` module, improved naming consistency, and removed minor redundancies from the test suite.

## 2.6.0 - 2025-09-08

- **Architecture**: Implemented a flexible strategy pattern for route matching, allowing for hybrid lookups (static hash, dynamic radix tree) to optimize performance.
- **Performance**: Introduced new traversal strategies (`Unrolled`, `GenericLoop`) to significantly speed up matching for common short path lengths while maintaining efficiency for longer paths.
- **Refactoring**: Major refactoring across `RouteSet`, `RadixTree`, `Node`, and utility modules to improve code organization, reduce complexity, and enhance maintainability.
- **Memory Efficiency**: Optimized key-building, path-splitting, and method normalization to reduce object allocations in hot paths. Replaced a manual ring-buffer cache with a more robust `SmallLru` implementation.
- **Code Quality**: Consolidated constants, improved naming consistency, and streamlined initialization and validation logic across the library for better clarity.

## 2.5.0 - 2025-09-04

- **Performance**: Improved route matching speed and reduced memory usage through optimized data structures.
- **Bug Fixes**: Addressed issues with nested route parameters and improved error messages for invalid routes.

## 2.4.0 - 2025-09-04

- **Performance**: Significant optimizations in path caching, HTTP method normalization, and memory allocation reduction
- **Bug Fixes**: Fixed route insertion issues, constraint validation problems, parameter handling edge cases, and path normalization consistency
- **Refactoring**: Improved code organization, consistent naming across modules, and enhanced maintainability
- **Documentation**: Added comprehensive USAGE.md with routing scenarios, enhanced inline documentation, and improved method descriptions
- **Thread Safety**: Enhanced concurrent access handling and cache synchronization
- **Testing**: Added extensive test coverage for edge cases, improved test reliability, and better error handling validation
- **Code Quality**: Removed unused methods, improved error messages, and streamlined code structure

## 2.3.0 - 2025-09-02

- **Refactoring**: Improved code organization, naming, and maintainability across router, route, segment, and utility modules.
- **Documentation**: Enhanced documentation for clarity and consistency in UrlHelpers, Constant module, and other modules.
- **Performance**: Optimizations in caching strategies, parameter handling, and HTTP method normalization.
- **Additions**: New utility modules (InflectorUtility, MethodUtility), constants, and comprehensive tests.
- **Fixes**: Bug fixes in route insertion, constraint validation, and parameter handling.

## 2.2.0 - 2025-08-31

- **Security**: Enhanced subprocess execution security in benchmarks and scripts.
- **Performance**: Optimizations in path generation, parameter validation, cache handling, and RadixTree.
- **Features**: Added KeyBuilderUtility, PathUtility, RouteUtility modules; method_missing for params.
- **Refactoring**: Improved code organization, naming, and readability.
- **Tests**: Added comprehensive tests for concerns, private methods.
- **Fixes**: Fixed longest prefix match logic, insecure Object.send usage.

## 2.1.0 - 2025-08-22

- **Features**: Added tests for various modules (Constant, UrlHelpers, segments, router, query params, pluralize).
- **Enhancements**: Extended pluralize method, improved path handling, added rack requirement.
- **Refactoring**: Removed unnecessary whitespace.

## 2.0.0 - 2025-08-20

- **Features**: Enhanced resources routing for custom paths and controllers.
- **Security**: Fixed command injection, replaced Proc constraints, fixed XSS in URL helpers, multiple vulnerabilities.
- **Performance**: 40x faster routing, major optimizations.
- **Fixes**: Fixed cache eviction, button_to mutation, wildcard parameter extraction, path generation, router initialization, HTML form method.
- **Tests**: Added comprehensive tests for coverage, integration, utilities, LRU, core routing.
- **Refactoring**: Improved test readability.

## 1.1.0 - 2025-08-17

- **Route Matching Optimization**: Reduced route matching time by ~40-50% through optimized cache key building and method normalization
- **Memory Usage Reduction**: Decreased object allocations by ~30-40% in hot paths through thread-local hash reuse and frozen string optimizations
- **Cache Performance**: Enhanced recognition cache with better hit rates (8192 entries) and simplified LRU eviction strategy
- **RadixTree Traversal**: Streamlined path splitting and traversal logic with fast-path optimizations for common route patterns (1-3 segments)
- **Parameter Handling**: Optimized parameter extraction and merging with reduced string allocations and improved constraint validation

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
- **SmallLru**: strategies extracted to top-level classes and exposed as singletons for lower allocations.
- **RouteSet**: added collection helpers (size, length, empty?, routes, clear!, find_named_route, generate_path, generate_path_from_route).

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

- **Performance**: use radix-tree params directly in `RubyRoutes::RouteSet#match` to avoid reparsing paths.
- **Performance**: faster path-splitting in `RubyRoutes::RadixTree#find`.
- **Path generation**: tokenized templates + bounded LRU cache `RubyRoutes::Route#generate_path`.
- **Caching**: adaptive small LRU to avoid thrash (`RubyRoutes::Route::SmallLru`).
- **Encoding**: cheap safe-ASCII test before `URI.encode_www_form_component`.
- **Constraint checks**: lightweight checks moved into tree traversal for early rejection.
- **Misc**: avoid repeated string upcasing in `RubyRoutes::Node#get_handler`.

## 0.1.0 - 2025-08-17

- Initial release of RubyRoutes gem.
