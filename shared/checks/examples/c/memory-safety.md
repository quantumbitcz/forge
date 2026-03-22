# Memory Safety Patterns (C)

## malloc-free-pairs

**Instead of:**
```c
char *buf = malloc(256);
process(buf);
// forgot to free
```

**Do this:**
```c
char *buf = malloc(256);
if (!buf) return -1;
process(buf);
free(buf);
buf = NULL;
```

**Why:** Every `malloc` must have a matching `free`, and nullifying the pointer afterward prevents dangling-pointer dereferences.

## bounds-checking

**Instead of:**
```c
void copy_name(const char *src) {
    char dest[64];
    strcpy(dest, src);
}
```

**Do this:**
```c
void copy_name(const char *src) {
    char dest[64];
    strncpy(dest, src, sizeof(dest) - 1);
    dest[sizeof(dest) - 1] = '\0';
}
```

**Why:** Unbounded `strcpy` writes past the buffer when `src` is longer than `dest`, causing stack corruption.

## use-after-free-prevention

**Instead of:**
```c
free(node);
printf("id=%d\n", node->id);
```

**Do this:**
```c
int id = node->id;
free(node);
node = NULL;
printf("id=%d\n", id);
```

**Why:** Accessing memory after `free` is undefined behavior; copying needed values before freeing eliminates the hazard.

## stack-allocation-preference

**Instead of:**
```c
int *counts = malloc(10 * sizeof(int));
memset(counts, 0, 10 * sizeof(int));
tally(counts, 10);
free(counts);
```

**Do this:**
```c
int counts[10] = {0};
tally(counts, 10);
```

**Why:** Small, fixed-size buffers belong on the stack -- no allocation failure to handle and no free to forget.
