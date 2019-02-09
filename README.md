# memoize-dlang
Memoize struct or class properties (Dlang)

```d
import memoize;

struct S {
    @property float _x() { return 1.5; }
    mixin CachedProperty!"x";
}
```
