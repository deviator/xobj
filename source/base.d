module xobj.base;

public import xobj.ctxhandler;
public import xobj.slot;
public import xobj.signal;

import std.traits;
import std.typetuple;
import std.string;
import std.exception;

// workaround alias some = __traits(...) => alias some = AT!(__traits(...))
template AT(alias T){ alias AT = T; }

interface XBase : SlotHandler, ContextHandler
{
public:
    enum signal;

protected:
    void __createSlotContext();
    void __createSignals();

    final void prepareXBase()
    {
        __createSlotContext();
        __createSignals();
    }

    final auto newSlot(Args...)( void delegate(Args) f )
    { return newCH!(Slot!Args)( this, f ); }

    final auto connect(Args...)( Signal!Args sig, void delegate(Args) f )
    {
        auto ret = newSlot!Args(f);
        sig.connect( ret );
        return ret;
    }

    mixin template MixX()
    {
        import std.traits;

        static if( !is(typeof(X_BASE_IMPL)) )
        {
            mixin MixContextHandler;

            enum X_BASE_IMPL = true;

            private SlotContext __slot_context;

            final
            {
                public SlotContext slotContext() @property { return __slot_context; }
                protected void __createSlotContext() { __slot_context = newCH!SlotContext; }
            }
        }

        mixin defineSignals;

        override protected
        {
            static if( isAbstractFunction!__createSignals )
                void __createSignals() { mixin( mix.createSignalsMixinString!(typeof(this)) ); }
            else
                void __createSignals()
                {
                    super.__createSignals();
                    mixin( mix.createSignalsMixinString!(typeof(this)) );
                }
        }
    }

    mixin template defineSignals() { mixin defineSignalsImpl!(typeof(this),getFunctionsWithAttrib!(typeof(this),signal)); }

    mixin template defineSignalsImpl(T,list...)
    {
        static if( list.length == 0 ) {}
        else static if( list.length > 1 )
        {
            mixin defineSignalsImpl!(T,list[0]);
            mixin defineSignalsImpl!(T,list[1..$]);
        }
        else mixin( mix.signalMixinString!(T,list[0]) );
    }

    template getFunctionsWithAttrib(T, Attr)
    {
        alias getFunctionsWithAttrib = impl!( __traits(derivedMembers,T) );

        enum AttrName = __traits(identifier,Attr);

        template isAttr(A) { template isAttr(T) { enum isAttr = __traits(isSame,T,A); } }

        template impl( names... )
        {
            alias empty = TypeTuple!();

            static if( names.length == 1 )
            {
                enum name = names[0];
                static if( __traits(compiles, { alias member = AT!(__traits(getMember,T,name)); } ) )
                {
                    alias member = AT!(__traits(getMember,T,name));

                    alias attribs = TypeTuple!(__traits(getAttributes,member));

                    static if( anySatisfy!( isAttr!Attr, attribs ) )
                    {
                        enum RULE = format( "%s must be a void function", AttrName );

                        static assert( isSomeFunction!member,
                                format( "fail mix X for '%s': %s, found '%s %s' with @%s attrib",
                                    T.stringof, RULE, typeof(member).stringof, name, AttrName ) );

                        static assert( is( ReturnType!member == void ),
                                format( "fail mix X for '%s': %s, found '%s' with @%s attrib",
                                    T.stringof, RULE, mix.functionFmt!member, AttrName ) );

                        static assert( mix.testName( name ),
                                format( "fail mix X for '%s': @%s name %s",
                                    T.stringof, mix.functionFmt!member, AttrName, mix.NAME_RULE ) );

                        alias impl = member;
                    }
                    else alias impl = empty;
                }
                else alias impl = empty;
            }
            else alias impl = TypeTuple!( impl!(names[0]), impl!(names[1..$]) );
        }
    }

    static struct __MixHelper
    {
        import std.algorithm, std.array;
        enum NAME_RULE = "must starts with '_'";

    static pure @safe:

        bool testName( string s ) { return s[0] == '_'; }
        string getMixName( string s ) { return s[1..$]; }

        string signalMixinString(T,alias temp)() @property
        {
            enum temp_name = __traits(identifier,temp);
            enum func_name = mix.getMixName( temp_name );

            static if( __traits(hasMember,T,func_name) )
            {
                alias base = AT!(__traits(getMember,T,func_name));

                static assert( isAbstractFunction!base,
                        format( "fail Mix X for '%s': target signal function '%s' must be abstract in base class",
                            T.stringof, func_name ) );

                enum temp_attribs = sort([__traits(getFunctionAttributes,temp)]).array;
                enum base_attribs = sort([__traits(getFunctionAttributes,base)]).array;

                static assert( base_attribs == temp_attribs,
                        format( "fail Mix X for '%s'; template signal function '%s' must have same attribs as base target function '%s': have %s, expect %s",
                            T.stringof, temp_name, func_name, temp_attribs, base_attribs ) );

                enum need_override = true;
            }
            else enum need_override = false;

            enum signal_name = signalPrefix ~ func_name;

            enum args_define = format( "alias %sArgs = ParameterTypeTuple!%s;", func_name, temp_name );
            enum signal_define = format( "Signal!(%sArgs) %s;", func_name, signal_name );
            enum func_impl = format( "final %1$s %2$s void %3$s(%3$sArgs args) %4$s { %5$s(args); }",
                    (need_override ? "override" : ""),
                    (__traits(getProtection,temp)),
                    func_name,
                    [__traits(getFunctionAttributes,temp)].join(" "),
                    signal_name );

            return [args_define, signal_define, func_impl].join("\n");
        }

        string signalPrefix() @property { return "signal_"; }

        string createSignalsMixinString(T)() @property
        {
            auto signals = [ __traits(derivedMembers,T) ]
                .filter!(a=>a.startsWith(signalPrefix));

            /+ TODO: if you use "signal_" prefix in your class
             +       filter!(a=>isSignal(__traits(getMember,T,a)))
             +/

            return signals
                .map!(a=>format("%1$s = newCH!(typeof(%1$s));",a))
                .join("\n");
        }

        template functionFmt(alias fun) if( isSomeFunction!fun )
        {
            enum functionFmt = format( "%s %s%s",
                    (ReturnType!fun).stringof,
                    __traits(identifier,fun),
                    (ParameterTypeTuple!fun).stringof );
        }
    }

    protected enum mix = __MixHelper.init;
}

import std.stdio;

void connect(T,Args...)( Signal!Args sig, T delegate(Args) slot )
{
    auto slot_handler = cast(XBase)cast(Object)(slot.ptr);
    enforce( slot_handler, "slot context is not XBase" );
    static if( is(T==void) ) slot_handler.connect( sig, slot );
    else slot_handler.connect( sig, (Args args){ slot(args); } );
}

void connect(T,Args...)( T delegate(Args) slot, Signal!Args sig ) { connect( sig, slot ); }

class XObject : XBase
{
    mixin MixX;
    this() { prepareXBase(); }
}

unittest
{
    interface Messager { void onMessage( string ); }

    class Drawable { abstract void onDraw(); }

    class A : Drawable, XBase
    {
        mixin MixX;
        this() { prepareXBase(); }
        @signal void _onDraw() {}
    }

    class B : A, Messager
    {
        mixin MixX;
        @signal void _onMessage( string msg ) {}
    }

    class Printer : XObject
    {
        mixin MixX;
        string[] msgs;
        void print( string msg ) { msgs ~= msg; }
    }

    auto a = new B;
    auto b = new B;
    auto p = new Printer;

    connect( a.signal_onMessage, &b.onMessage );
    connect( &p.print, b.signal_onMessage );

    size_t draws;
    a.signal_onDraw.connect( a.newSlot({ draws++; }) );

    static void callMessager1( Messager m ) { m.onMessage( "hello" ); }
    static void callMessager2( Messager m ) { m.onMessage( "habr" ); }
    static void callDrawable( Drawable d ) { d.onDraw(); }

    assert( p.msgs == [] );
    callMessager1( a );
    assert( p.msgs == ["hello"] );
    callMessager2( a );
    assert( p.msgs == ["hello","habr"] );

    assert( draws == 0 );
    callDrawable( a );
    callDrawable( a );
    assert( draws == 2 );

    p.destroyCtx();
    callMessager1( a );
    assert( p.msgs == ["hello","habr"] );
}
