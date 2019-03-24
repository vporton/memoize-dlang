module memoize;

static import std.functional;
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

/**
Use it to memoize both a struct or class instance for a member function and function arguments like:
```
struct S {
    int f(int a, int b) {
        return a + b;
    }
}
alias f2 = memoizeMember!(S, "f");
alias f3 = memoizeMember!(S, "f", 10);
S s;
assert(f2(s, 2, 3) == 5);
```

As you see the member function name ("f" in the example) is passed as a string.
This is very unnatural, but I found no other way to do it.
*/
template memoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias memoizeMember = std.functional.memoize!f;
}

/// ditto
template memoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias memoizeMember = std.functional.memoize!(f, maxSize);
}

unittest {
    struct S2 {
        int f(int a, int b) {
            return a + b;
        }
    }
    alias f2 = memoizeMember!(S2, "f");
    alias f3 = memoizeMember!(S2, "f", 10);
    S2 s;
    assert(f2(s, 2, 3) == 5);
    assert(f2(s, 2, 3) == 5);
    assert(f3(s, 2, 3) == 5);
}
