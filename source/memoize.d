module memoize;

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

// Ugh, repeated code
private template _memoize(alias fun, string attr)
{
    // alias Args = Parameters!fun; // Bugzilla 13580

    ReturnType!fun _memoize(const(Parameters!fun) args)
    {
        alias Args = Parameters!fun;
        import std.typecons : Tuple;

        mixin(attr ~ " static Unqual!(ReturnType!fun)[Tuple!Args] memo;");
        auto t = Tuple!Args(args);
        if (auto p = t in memo)
            return *p;
        return memo[t] = fun(args);
    }
}

private template _referenceMemoize(alias fun, string attr)
{
    // alias Args = Parameters!fun; // Bugzilla 13580

    ref Unqual!(ReturnType!fun) _referenceMemoize(const(Parameters!fun) args)
    {
        alias Args = Parameters!fun;
        import std.typecons : Tuple;

        static ReturnType!fun*[Tuple!Args] memo;
        auto t = Tuple!Args(args);
        if (auto p = t in memo) return **p;
        memo[t] = &fun(args);
        return *memo[t];
    }
}

private template _memoize(alias fun, uint maxSize, string modifier)
{
    // alias Args = Parameters!fun; // Bugzilla 13580
    // Ugh, repeated code
    ReturnType!fun _memoize(const(Parameters!fun) args)
    {
        import std.traits : hasIndirections;
        import std.typecons : tuple;
        static struct Value { const(Parameters!fun) args; ReturnType!fun res; }
        mixin(modifier ~ " static Unqual!(Value)[] memo;");
        mixin(modifier ~ " static size_t[] initialized;");

        if (!memo.length)
        {
            import core.memory : GC;

            // Ensure no allocation overflows
            static assert(maxSize < size_t.max / Value.sizeof);
            static assert(maxSize < size_t.max - (8 * size_t.sizeof - 1));

            enum attr = GC.BlkAttr.NO_INTERIOR | (hasIndirections!Value ? 0 : GC.BlkAttr.NO_SCAN);
            mixin("alias VType = " ~ modifier ~ " Value;");
            memo = (cast(VType*) GC.malloc(Value.sizeof * maxSize, attr))[0 .. maxSize];
            enum nwords = (maxSize + 8 * size_t.sizeof - 1) / (8 * size_t.sizeof);
            mixin("alias mysize_t = " ~ modifier ~ " size_t;");
            initialized = (cast(mysize_t*) GC.calloc(nwords * size_t.sizeof, attr | GC.BlkAttr.NO_SCAN))[0 .. nwords];
        }

        import core.bitop : bt, bts;
        import std.conv : emplace;

        size_t hash;
        foreach (ref arg; args)
            hash = hashOf(arg, hash);
        // cuckoo hashing
        immutable idx1 = hash % maxSize;
        if (!bt(cast(size_t*) initialized.ptr, idx1))
        {
            emplace(&memo[idx1], args, fun(args));
            bts(cast(size_t*) initialized.ptr, idx1); // only set to initialized after setting args and value (bugzilla 14025)
            return memo[idx1].res;
        }
        else if (memo[idx1].args == args)
            return memo[idx1].res;
        // FNV prime
        immutable idx2 = (hash * 16_777_619) % maxSize;
        if (!bt(cast(size_t*) initialized.ptr, idx2))
        {
            emplace(&memo[idx2], memo[idx1]);
            bts(cast(size_t*) initialized.ptr, idx2); // only set to initialized after setting args and value (bugzilla 14025)
        }
        else if (memo[idx2].args == args)
            return memo[idx2].res;
        else if (idx1 != idx2)
            memo[idx2] = memo[idx1];

        memo[idx1] = Value(args, fun(args));
        return memo[idx1].res;
    }
}

private template _referenceMemoize(alias fun, uint maxSize, string modifier)
{
    ref Unqual!(ReturnType!fun) _referenceMemoize(const(Parameters!fun) args)
    {
        import std.traits : hasIndirections;
        import std.typecons : tuple;
        static struct Value { const(Parameters!fun) args; ReturnType!fun *res; }
        mixin(modifier ~ " static Unqual!(Value)*[] memo;");
        mixin(modifier ~ " static size_t[] initialized;");

        if (!memo.length)
        {
            import core.memory : GC;

            // Ensure no allocation overflows
            static assert(maxSize < size_t.max / Value.sizeof);
            static assert(maxSize < size_t.max - (8 * size_t.sizeof - 1));

            enum attr = GC.BlkAttr.NO_INTERIOR | (hasIndirections!Value ? 0 : GC.BlkAttr.NO_SCAN);
            mixin("alias VType = " ~ modifier ~ " Value;");
            memo = (cast(VType*) GC.malloc(Value.sizeof * maxSize, attr))[0 .. maxSize];
            enum nwords = (maxSize + 8 * size_t.sizeof - 1) / (8 * size_t.sizeof);
            mixin("alias mysize_t = " ~ modifier ~ " size_t;");
            initialized = (cast(mysize_t*) GC.calloc(nwords * size_t.sizeof, attr | GC.BlkAttr.NO_SCAN))[0 .. nwords];
        }

        import core.bitop : bt, bts;
        import std.conv : emplace;

        size_t hash;
        foreach (ref arg; args)
            hash = hashOf(arg, hash);
        // cuckoo hashing
        immutable idx1 = hash % maxSize;
        if (!bt(cast(size_t*) initialized.ptr, idx1))
        {
            emplace(&memo[idx1], args, &fun(args));
            bts(cast(size_t*) initialized.ptr, idx1); // only set to initialized after setting args and value (bugzilla 14025)
            return *memo[idx1].res;
        }
        else if (memo[idx1].args == args)
            return *memo[idx1].res;
        // FNV prime
        immutable idx2 = (hash * 16_777_619) % maxSize;
        if (!bt(cast(size_t*) initialized.ptr, idx2))
        {
            emplace(&memo[idx2], memo[idx1]);
            bts(cast(size_t*) initialized.ptr, idx2); // only set to initialized after setting args and value (bugzilla 14025)
        }
        else if (memo[idx2].args == args)
            return *memo[idx2].res;
        else if (idx1 != idx2)
            memo[idx2] = memo[idx1];

        memo[idx1] = Value(args, &fun(args));
        return *memo[idx1].res;
    }
}

// See https://issues.dlang.org/show_bug.cgi?id=4533 why aliases are not used.

/**
The same as in Phobos `std.functional`.
*/
//alias memoize(alias fun) = _memoize!(fun, "");
template memoize(alias fun)
{
    ReturnType!fun memoize(const(Parameters!fun) args)
    {
        return _memoize!(fun, "")(args);
    }
}

template referenceMemoize(alias fun)
{
    ref Unqual!(ReturnType!fun) referenceMemoize(const(Parameters!fun) args)
    {
        return _referenceMemoize!(fun, "")(args);
    }
}

/// ditto
//alias memoize(alias fun, uint maxSize) = _memoize!(fun, maxSize, "");
template memoize(alias fun, uint maxSize)
{
    ReturnType!fun memoize(const(Parameters!fun) args)
    {
        return _memoize!(fun, maxSize, "")(args);
    }
}

template referenceMemoize(alias fun, uint maxSize)
{
    ref Unqual!(ReturnType!fun) referenceMemoize(const(Parameters!fun) args)
    {
        return _referenceMemoize!(fun, maxSize, "")(args);
    }
}

/// must be locked explicitly!
//alias noLockMemoize(alias fun) = _memoize!(fun, "shared");
template noLockMemoize(alias fun)
{
    ReturnType!fun noLockMemoize(const(Parameters!fun) args)
    {
        return _memoize!(fun, "shared")(args);
    }
}

template referenceNoLockMemoize(alias fun)
{
    ref Unqual!(ReturnType!fun) referenceNoLockMemoize(const(Parameters!fun) args)
    {
        return _referenceMemoize!(fun, "shared")(args);
    }
}

/// must be locked explicitly!
//alias noLockMemoize(alias fun, uint maxSize) = _memoize!(fun, maxSize, "shared");
template noLockMemoize(alias fun, uint maxSize)
{
    ReturnType!fun noLockMemoize(const(Parameters!fun) args)
    {
        return _memoize!(fun, maxSize, "shared")(args);
    }
}

template referenceNoLockMemoize(alias fun, uint maxSize)
{
    ref Unqual!(ReturnType!fun) referenceNoLockMemoize(const(Parameters!fun) args)
    {
        return _referenceMemoize!(fun, maxSize, "shared")(args);
    }
}

/**
Synchronized version of `memoize` using global (interthread) cache.
*/
template synchronizedMemoize(alias fun) {
    private alias impl = memoize!fun;
    ReturnType!fun synchronizedMemoize(const(Parameters!fun) args) {
        synchronized {
            return impl(args);
        }
    }
}

template referenceSynchronizedMemoize(alias fun) {
    private alias impl = referenceMemoize!fun;
    ref Unqual!(ReturnType!fun) referenceSynchronizedMemoize(const(Parameters!fun) args) {
        synchronized {
            return impl(args);
        }
    }
}

/// ditto
template synchronizedMemoize(alias fun, uint maxSize) {
    private alias impl = memoize!(fun, maxSize);
    ReturnType!fun synchronizedMemoize(const(Parameters!fun) args) {
        synchronized {
            return impl(args);
        }
    }
}

template referenceSynchronizedMemoize(alias fun, uint maxSize) {
    private alias impl = referenceMemoize!(fun, maxSize);
    ref Unqual!(ReturnType!fun) referenceSynchronizedMemoize(const(Parameters!fun) args) {
        synchronized {
            return impl(args);
        }
    }
}

@safe unittest
{
    ulong fib(ulong n) @safe
    {
        return n < 2 ? n : memoize!fib(n - 2) + memoize!fib(n - 1);
    }
    assert(fib(10) == 55);
    ulong fib2(ulong n) @safe
    {
        return n < 2 ? n : synchronizedMemoize!fib2(n - 2) + synchronizedMemoize!fib2(n - 1);
    }
    assert(fib2(10) == 55);
}

@safe unittest
{
    ulong fact(ulong n) @safe
    {
        return n < 2 ? 1 : n * memoize!fact(n - 1);
    }
    assert(fact(10) == 3628800);
    ulong fact2(ulong n) @safe
    {
        return n < 2 ? 1 : n * synchronizedMemoize!fact2(n - 1);
    }
    assert(fact2(10) == 3628800);
}

@safe unittest
{
    ulong factImpl(ulong n) @safe
    {
        return n < 2 ? 1 : n * factImpl(n - 1);
    }
    alias fact = memoize!factImpl;
    assert(fact(10) == 3628800);
    ulong factImpl2(ulong n) @safe
    {
        return n < 2 ? 1 : n * factImpl2(n - 1);
    }
    alias fact2 = synchronizedMemoize!factImpl;
    assert(fact2(10) == 3628800);
}

@system unittest // not @safe due to memoize
{
    ulong fact(ulong n)
    {
        // Memoize no more than 8 values
        return n < 2 ? 1 : n * memoize!(fact, 8)(n - 1);
    }
    assert(fact(8) == 40320);
    // using more entries than maxSize will overwrite existing entries
    assert(fact(10) == 3628800);
    ulong fact2(ulong n)
    {
        // Memoize no more than 8 values
        return n < 2 ? 1 : n * synchronizedMemoize!(fact2, 8)(n - 1);
    }
    assert(fact2(8) == 40320);
    // using more entries than maxSize will overwrite existing entries
    assert(fact2(10) == 3628800);
}

@system unittest
{
    static ulong x;
    ref ulong f()
    {
        return x;
    }
    assert(&referenceMemoize!f() == &x);
    assert(&referenceNoLockMemoize!f() == &x);
    assert(&referenceSynchronizedMemoize!f() == &x);
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
    alias memoizeMember = memoize!f;
}

template referenceMemoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ref ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias referenceMemoizeMember = referenceMemoize!f;
}

/// ditto
template memoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias memoizeMember = memoize!(f, maxSize);
}

template referenceMemoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ref ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias referenceMemoizeMember = referenceMemoize!(f, maxSize);
}

/// ditto
template noLockMemoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias noLockMemoizeMember = noLockMemoize!f;
}

template referenceNoLockMemoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ref ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias referenceNoLockMemoizeMember = referenceNoLockMemoize!f;
}

/// ditto
template noLockMemoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias noLockMemoizeMember = noLockMemoize!(f, maxSize);
}

template referenceNoLockMemoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ref ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias referenceNoLockMemoizeMember = referenceNoLockMemoize!(f, maxSize);
}

/// ditto
template synchronizedMemoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias synchronizedMemoizeMember = synchronizedMemoize!f;
}

template referenceSynchronizedMemoizeMember(S, string name) {
    alias Member = __traits(getMember, S, name);
    ref ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias referenceSynchronizedMemoizeMember = referenceSynchronizedMemoize!f;
}

/// ditto
template synchronizedMemoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias synchronizedMemoizeMember = synchronizedMemoize!(f, maxSize);
}

template referenceSynchronizedMemoizeMember(S, string name, uint maxSize) {
    alias Member = __traits(getMember, S, name);
    ref ReturnType!Member f(S s, Parameters!Member others) {
        return __traits(getMember, s, name)(others);
    }
    alias referenceSynchronizedMemoizeMember = referenceSynchronizedMemoize!(f, maxSize);
}

unittest {
    struct S2 {
        int f(int a, int b) {
            return a + b;
        }
    }
    alias f2 = memoizeMember!(S2, "f");
    alias f3 = memoizeMember!(S2, "f", 10);
    alias f4 = synchronizedMemoizeMember!(S2, "f");
    alias f5 = synchronizedMemoizeMember!(S2, "f", 10);
    S2 s;
    assert(f2(s, 2, 3) == 5);
    assert(f2(s, 2, 3) == 5);
    assert(f3(s, 2, 3) == 5);
    assert(f4(s, 2, 3) == 5);
    assert(f5(s, 2, 3) == 5);
}

unittest {
    int x;
    struct S2 {
        ref int f() {
            return x;
        }
    }
    S2 s;
    assert(&referenceMemoizeMember!(S2, "f")(s) == &x);
    assert(&referenceNoLockMemoizeMember!(S2, "f")(s) == &x);
    assert(&referenceSynchronizedMemoizeMember!(S2, "f")(s) == &x);
}
