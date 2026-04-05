# Readability Patterns (C++)

## structured-bindings

**Instead of:**
```cpp
for (auto it = map.begin(); it != map.end(); ++it) {
    std::string key = it->first;
    int value = it->second;
    process(key, value);
}
```

**Do this:**
```cpp
for (const auto& [key, value] : map) {
    process(key, value);
}
```

**Why:** Structured bindings (C++17) eliminate iterator boilerplate and give meaningful names to tuple/pair elements at the declaration site.

## auto-return-type

**Instead of:**
```cpp
std::vector<std::pair<std::string, int>> get_scores() {
    std::vector<std::pair<std::string, int>> result;
    // ...
    return result;
}
```

**Do this:**
```cpp
auto get_scores() -> std::vector<std::pair<std::string, int>> {
    std::vector<std::pair<std::string, int>> result;
    // ...
    return result;
}
```

**Why:** Trailing return types align function names vertically and reduce visual noise when the return type is complex. The function name appears first, which is what readers scan for.

## constexpr-compile-time

**Instead of:**
```cpp
const int MAX_RETRIES = 3;
const double PI = 3.14159265358979;
```

**Do this:**
```cpp
constexpr int MAX_RETRIES = 3;
constexpr double PI = 3.14159265358979;
```

**Why:** `constexpr` guarantees compile-time evaluation, enabling optimizations that `const` alone cannot. The compiler verifies the value is truly constant rather than just promising not to modify it.
