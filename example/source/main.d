import std.stdio;
import std.traits;
import std.typetuple;

import xobj;

class Foo : XObject
{
    mixin MixX;
    @signal void _message( string str ) {}
}

class Bar : XObject
{
    mixin MixX;
    void print( string str ) { writefln( "Bar.print: %s", str ); }
}

void main()
{
    auto a = new Foo, b = new Bar;
    connect( a.signal_message, &b.print );
    a.message( "hello habr" ); // Bar.print: hello habr
}
