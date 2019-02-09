module memoize.property;

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
