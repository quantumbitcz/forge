# Readability Patterns (C)

## nesting

**Instead of:**
```c
int handle(Request *r) {
    if (r) {
        if (r->type == REQ_GET) {
            if (r->auth) {
                return serve(r);
            }
        }
    }
    return -1;
}
```

**Do this:**
```c
int handle(Request *r) {
    if (!r) return -1;
    if (r->type != REQ_GET) return -1;
    if (!r->auth) return -1;
    return serve(r);
}
```

**Why:** Early returns flatten deeply nested conditionals, making the main path visible at the top indentation level.

## naming

**Instead of:**
```c
int f(int a, int b) {
    int x = a * b;
    return x > T ? T : x;
}
```

**Do this:**
```c
int clamp_area(int width, int height) {
    int area = width * height;
    return area > MAX_AREA ? MAX_AREA : area;
}
```

**Why:** Descriptive names for functions, parameters, and constants convey intent without requiring a comment.

## guard-clauses

**Instead of:**
```c
void process_buffer(const char *buf, size_t len) {
    if (buf != NULL) {
        if (len > 0) {
            // ... 30 lines of real logic ...
        }
    }
}
```

**Do this:**
```c
void process_buffer(const char *buf, size_t len) {
    if (!buf || len == 0) return;
    // ... 30 lines of real logic ...
}
```

**Why:** Guard clauses reject invalid input upfront so the body of the function does not live inside a conditional wrapper.

## single-exit-point

**Instead of:**
```c
int parse_config(Config *cfg) {
    if (!cfg) return -1;
    if (load_defaults(cfg) < 0) return -2;
    if (read_file(cfg) < 0) return -3;
    if (validate(cfg) < 0) return -4;
    return 0;
}
```

**Do this:**
```c
int parse_config(Config *cfg) {
    int rc = -1;
    if (!cfg) goto done;
    if (load_defaults(cfg) < 0) goto done;
    if (read_file(cfg) < 0) goto done;
    if (validate(cfg) < 0) goto done;
    rc = 0;
done:
    return rc;
}
```

**Why:** A single return via `goto done` gives one place to set breakpoints and add cleanup, which is valuable in functions that acquire resources.
