# Error Handling Patterns (C++)

## raii-resource-management

**Instead of:**
```cpp
void process(const std::string& path) {
    FILE* f = fopen(path.c_str(), "r");
    if (!f) return;
    char* buf = new char[1024];
    fread(buf, 1, 1024, f);
    // If exception thrown here, f and buf leak
    transform(buf);
    delete[] buf;
    fclose(f);
}
```

**Do this:**
```cpp
void process(const std::string& path) {
    std::ifstream file(path);
    if (!file) return;
    auto buf = std::make_unique<char[]>(1024);
    file.read(buf.get(), 1024);
    transform(buf.get());
}
```

**Why:** RAII (Resource Acquisition Is Initialization) guarantees cleanup even when exceptions propagate. Manual `delete`/`fclose` calls are fragile — any early return or throw skips them.

## expected-error-handling

**Instead of:**
```cpp
int parse_port(const std::string& s) {
    try {
        int port = std::stoi(s);
        if (port < 0 || port > 65535) throw std::runtime_error("out of range");
        return port;
    } catch (...) {
        return -1;  // Magic sentinel
    }
}
```

**Do this:**
```cpp
std::expected<int, std::string> parse_port(const std::string& s) {
    int port;
    auto [ptr, ec] = std::from_chars(s.data(), s.data() + s.size(), port);
    if (ec != std::errc{}) return std::unexpected("not a number");
    if (port < 0 || port > 65535) return std::unexpected("port out of range");
    return port;
}
```

**Why:** `std::expected` (C++23) makes failure a first-class return value, avoids exception overhead for expected failures, and forces callers to handle the error case explicitly.

## noexcept-move

**Instead of:**
```cpp
class Buffer {
public:
    Buffer(Buffer&& other) {
        data_ = other.data_;
        other.data_ = nullptr;
    }
};
```

**Do this:**
```cpp
class Buffer {
public:
    Buffer(Buffer&& other) noexcept
        : data_(std::exchange(other.data_, nullptr)) {}
};
```

**Why:** Move constructors without `noexcept` prevent `std::vector` from using moves during reallocation (it falls back to copies for exception safety). `std::exchange` makes the swap atomic and self-documenting.
