module memoize;

import std.functional;
import std.traits;

/**
The following code makes cached (memoized) property `f`
```
class {
    @property string _f() { ... }
    mixin CachedProperty!"f";
}
```
*/
mixin template CachedProperty(string name, string baseName = '_' ~ name) {
    mixin("private typeof(" ~ baseName ~ ") " ~ name ~ "Cache;");
    mixin("private bool " ~ name ~ "IsCached = false;");
    mixin("@property typeof(" ~ baseName ~ ") " ~ name ~ "() {\n" ~
          "if (" ~ name ~ "IsCached" ~ ") return " ~ name ~ "Cache;\n" ~
          name ~ "IsCached = true;\n" ~
          "return " ~ name ~ "Cache = " ~ baseName ~ ";\n" ~
          '}');
}

template memoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member memoizeMember(S s, Parameters!Member others) {
        ReturnType!Member f(S s, Parameters!Member others) {
            return __traits(getMember, s, name)(others);
        }
        return memoize!f;
    }
}

template memoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member memoizeMember(S s, Parameters!Member others) {
        ReturnType!Member f(S s, Parameters!Member others) {
            return __traits(getMember, s, name)(others);
        }
        return memoize!(f, maxSize);
    }
}

unittest {
    struct S {
        @property float _x() { return 1.5; }
        mixin CachedProperty!"x";
    }
    class C {
        @property float _x() { return 1.5; }
        mixin CachedProperty!"x";
    }
    S s;
    assert(s.x == 1.5);
    assert(s.x == 1.5);
    C c = new C();
    assert(c.x == 1.5);
}
