module xobj.ctxhandler;

interface ContextHandler
{
protected:

    void selfDestroyCtx();
    void preChildsDestroy();

public:

    bool isCtxDestroyed() const @property;
    protected void destroyCtxFinish();

    @property
    {
        ContextHandler parentCH();
        const(ContextHandler) parentCH() const;
        ContextHandler parentCH( ContextHandler );

        ContextHandler[] childCH();
        const(ContextHandler)[] childCH() const;
    }

    void changeParentCH( ContextHandler );

    final bool findInChildCH( const(ContextHandler) obj ) const
    {
        foreach( ch; childCH )
        {
            if( ch is obj ) return true;
            if( ch.findInChildCH(obj) ) return true;
        }
        return false;
    }

    final
    {
        T registerCH(T)( T obj, bool force=true )
            if( is( T == class ) )
        {
            if( auto ch = cast(ContextHandler)obj )
                if( force || ( !force && ch.parentCH is null ) )
                    attachCH( ch );
            return obj;
        }

        T newCH(T,Args...)( Args args ) { return registerCH( new T(args) ); }

        void destroyCtx()
        {
            if( isCtxDestroyed ) return;
            preChildsDestroy();
            foreach( c; childCH )
                c.destroyCtx();
            selfDestroyCtx();
            destroyCtxFinish();
        }
    }

    void attachCH( ContextHandler[] list... );
    void detachCH( ContextHandler[] list... );

    mixin template MixContextHandler()
    {
        import std.traits;
        import std.exception;
        import std.algorithm;
        import std.array;

        static if( !is(typeof(CONTEXT_HANDLER_IMPL)) )
        {
            private bool is_ctx_destroyed = false;
            public final bool isCtxDestroyed() const @property { return is_ctx_destroyed; }
            protected final void destroyCtxFinish() { is_ctx_destroyed = true; }

            protected
            {
                enum CONTEXT_HANDLER_IMPL = true;

                ContextHandler __parent_ch;
                ContextHandler[] __child_ch;

                override
                {
                    static if( isAbstractFunction!selfDestroyCtx )
                        void selfDestroyCtx() {}
                    static if( isAbstractFunction!preChildsDestroy )
                        void preChildsDestroy() {}
                }
            }

            public final
            {
                @property
                {
                    ContextHandler parentCH() { return __parent_ch; }
                    const(ContextHandler) parentCH() const { return __parent_ch; }

                    ContextHandler parentCH( ContextHandler p )
                    {
                        if( __parent_ch !is null ) __parent_ch.detachCH( this );
                        __parent_ch = p;
                        if( __parent_ch !is null ) __parent_ch.attachCH( this );
                        return p;
                    }

                    void changeParentCH( ContextHandler p ) { __parent_ch = p; }

                    ContextHandler[] childCH() { return __child_ch; }
                    const(ContextHandler)[] childCH() const { return __child_ch; }
                }

                void attachCH( ContextHandler[] list... )
                {
                    foreach( e; list )
                        enforce( e !is null, "can't attach null context handler" );

                    enforce( cycleCheck( list ), "found cycle" );

                    auto parentDetach(ContextHandler e)
                    {
                        if( e.parentCH !is null )
                            e.parentCH.detachCH(e);
                        e.changeParentCH( this );
                        return e;
                    }

                    __child_ch = list
                        .filter!(a=>!findInChildCH(a))
                        .map!(a=>parentDetach(a))
                        .array;
                }

                void detachCH( ContextHandler[] list... )
                {
                    foreach( e; list )
                        e.changeParentCH( null );

                    __child_ch = list.filter!(a=>!canFind(childCH,a)).array;
                }
            }

            final protected bool cycleCheck( const(ContextHandler)[] list... ) const
            {
                const(ContextHandler)[] plist = [this];

                while( plist[$-1].parentCH )
                    plist ~= plist[$-1].parentCH;

                foreach( p; plist )
                    foreach( e; list )
                        if( e.findInChildCH(p) )
                            return false;

                return true;
            }
        }
    }
}

unittest
{
    string[] buf;

    class Test : ContextHandler
    {
        mixin MixContextHandler;
        string name;
        this( string n ) { name = n; }
    protected:
        void preChildsDestroy() { buf ~= name ~ "[pre]"; }
        void selfDestroyCtx() { buf ~= name ~ "[ctx]"; }
    }

    auto a = new Test("a");
    auto b = new Test("b");
    auto c = new Test("c");
    auto d = new Test("d");

    assert( a.parentCH is null );
    assert( b.parentCH is null );
    assert( c.parentCH is null );
    assert( d.parentCH is null );

    assert( a.childCH is null );
    assert( b.childCH is null );
    assert( c.childCH is null );
    assert( d.childCH is null );

    a.registerCH(b);
    assert( a.childCH == [b] );
    assert( b.parentCH is a );

    c.registerCH(b);
    assert( c.childCH == [b] );
    assert( b.parentCH is c );
    assert( a.childCH == [] );

    a.registerCH(b,false);
    assert( c.childCH == [b] );
    assert( b.parentCH is c );
    assert( a.childCH == [] );

    a.registerCH(b);
    assert( a.childCH == [b] );
    assert( b.parentCH is a );
    assert( c.childCH == [] );

    b.registerCH(c);
    c.registerCH(d);

    a.destroyCtx();

    assert( buf ==
            [
                "a[pre]",
                "b[pre]",
                "c[pre]",
                "d[pre]",
                "d[ctx]",
                "c[ctx]",
                "b[ctx]",
                "a[ctx]"
            ]
          );
}
