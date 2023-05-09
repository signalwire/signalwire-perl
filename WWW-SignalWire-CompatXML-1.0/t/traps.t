#-*- mode: cperl -*-#
use Test::More tests => 1;
use WWW::SignalWire::CompatXML;

#########################

{
    my $tw = new WWW::SignalWire::CompatXML;
    my $resp = $tw->Respose;
    local $SIG{__WARN__} = sub { die $@ };
    eval { $resp->Dial(undef) };
    is( $@, '', "empty arguments" );
}
