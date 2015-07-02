module xobj.signal;

import xobj.ctxhandler;
import xobj.slot;

import std.typecons;

template isSignal(T)
{
    static if( is( T : S!Args, alias S, Args... ) )
        enum isSignal = __traits(isSame,Signal,S);
    else 
        enum isSignal = false;
}

unittest
{
    static assert(  isSignal!( Signal!float ) );
    static assert(  isSignal!( Signal!(string,int) ) );
    static assert( !isSignal!string );
    static assert( !isSignal!( Slot!float ) );
}

class Signal(Args...) : SignalConnector, ContextHandler
{
    mixin MixContextHandler;

protected:

    alias Slot!Args TSlot;

    TSlot[] slots;

public:

    TSlot connect( TSlot s )
    {
        if( !connected(s) )
        {
            slots ~= s;
            s.context.connect(this);
        }
        return s;
    }

    void disconnect( TSlot s )
    {
        slots = slots.filter!(a=>a !is s).array;
        s.context.disconnect(this);
    }

    void disconnect( SlotContext sc )
    {
        foreach( s; slots.map!(a=>a.context).filter!(a=> a is sc) )
            s.disconnect(this);
        slots = slots
            .map!(a=>tuple(a,a.context))
            .filter!(a=> a[1] !is sc)
            .map!(a=>a[0])
            .array;
    }

    void disconnect( SlotHandler sh ) { disconnect( sh.slotContext ); }

    void disonnectAll()
    {
        slots = [];
        foreach( s; slots )
            s.context.disconnect( this );
    }

    void opCall( Args args ) { foreach( s; slots ) s(args); }

protected:

    bool connected( TSlot s ) { return canFind(slots,s); }

    void selfDestroyCtx() { disonnectAll(); }
}

unittest
{
    string[] msg;
    string[] cl1;
    string[] cl2;

    class Postal : ContextHandler
    {
        mixin MixContextHandler;
        Signal!string onMessage;
        this() { onMessage = newCH!(typeof(onMessage)); }
        void send( string m ) { msg ~= m; onMessage( m ); }
    }

    class Client : SlotHandler, ContextHandler
    {
        mixin MixContextHandler;

        SlotContext sc;
        Slot!string read_slot;

        this()
        {
            sc = newCH!SlotContext;
            read_slot = newCH!(typeof(read_slot))( this, &read );
        }

        SlotContext slotContext() @property { return sc; }

        abstract void read( string );
    }

    auto postal = new Postal;
    auto client1 = new class Client { override void read( string m ) { cl1 ~= m; } };
    auto client2 = new class Client { override void read( string m ) { cl2 ~= m; } };

    postal.send( "zero" );
    assert( msg == ["zero"] );
    assert( cl1 == cl2 && cl2 == [] );

    postal.onMessage.connect( client1.read_slot );
    postal.onMessage.connect( client1.read_slot ); // duplicate, must not add

    postal.onMessage.connect( client2.read_slot );

    postal.send( "one" );

    assert( msg == ["zero","one"] );
    assert( cl1 == cl2 && cl2 == ["one"] );

    postal.onMessage.disconnect( client2 );

    postal.send( "two" );
    assert( msg == ["zero","one","two"] );
    assert( cl1 == ["one","two"] );
    assert( cl2 == ["one"] );

    postal.onMessage.connect( client2.read_slot );

    postal.send( "three" );
    assert( msg == ["zero","one","two","three"] );
    assert( cl1 == ["one","two","three"] );
    assert( cl2 == ["one","three"] );

    client1.destroyCtx();

    postal.send( "four" );
    assert( msg == ["zero","one","two","three","four"] );
    assert( cl1 == ["one","two","three"] );
    assert( cl2 == ["one","three","four"] );

    postal.onMessage.disonnectAll();
    postal.send( "five" );
    assert( msg == ["zero","one","two","three","four","five"] );
    assert( cl1 == ["one","two","three"] );
    assert( cl2 == ["one","three","four"] );
}
