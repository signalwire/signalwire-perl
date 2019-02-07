#-*- mode: cperl -*-#
use Test::More tests => 1;
use WWW::SignalWire::LaML;

#########################

{
    my $tw = new WWW::SignalWire::LaML;
    my $resp = $tw->Respose;
    local $SIG{__WARN__} = sub { die $@ };
    eval { $resp->Dial(undef) };
    is( $@, '', "empty arguments" );
}
