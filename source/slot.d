module xobj.slot;

import xobj.ctxhandler;

import std.stdio;

interface SignalConnector
{
    void disconnect( SlotContext );
    void disonnectAll();
}

class SlotContext : ContextHandler
{
    mixin MixContextHandler;

protected:
    size_t[SignalConnector] signals;

public:

    void connect( SignalConnector sc ) { signals[sc]++; }

    void disconnect( SignalConnector sc )
    {
        if( sc in signals )
        {
            if( signals[sc] > 0 ) signals[sc]--;
            else signals.remove(sc);
        }
    }

protected:

    void selfDestroyCtx()
    {
        foreach( sig, count; signals )
            sig.disconnect(this);
    }
}

interface SlotHandler
{
    SlotContext slotContext() @property;
}

class Slot(Args...)
{
protected:
    Func func;
    SlotContext ctrl;

public:
    alias void delegate(Args) Func;

    this( SlotContext ctrl, Func func )
    {
        this.ctrl = ctrl;
        this.func = func;
    }

    this( SlotHandler hndl, Func func )
    { this( hndl.slotContext, func ); }

    void opCall( Args args ) { func( args ); }

    SlotContext context() @property { return ctrl; }
}

template isSlot(T)
{
    static if( is( T : S!Args, alias S, Args... ) )
        enum isSlot = __traits(isSame,Slot,S);
    else
        enum isSlot = false;
}

unittest
{
    static assert(  isSlot!( Slot!float ) );
    static assert(  isSlot!( Slot!(string,int) ) );
    static assert( !isSlot!( string ) );
}
