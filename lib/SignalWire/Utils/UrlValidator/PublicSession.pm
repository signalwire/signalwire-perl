package SignalWire::Utils::UrlValidator::PublicSession;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# An HTTP::Tiny for fetching USER-SUPPLIED URLs. Mirrors the python reference's
# signalwire.utils.url_validator._PublicSession (a requests.Session):
#
#   * every request, and every redirect hop, is checked with validate_url()
#     before it is sent -- a server can otherwise redirect to an internal address;
#   * a direct connection is pinned to an address that was checked, so a DNS
#     answer that changes between the check and the connect (DNS rebinding)
#     cannot reach a private or internal peer;
#   * the environment's HTTP(S)_PROXY is ignored (through a proxy the peer check
#     cannot apply) unless SWML_URL_FETCH_USE_PROXY is set.
#
# SWML_ALLOW_PRIVATE_URLS (or allow_private => 1) turns both checks off, as it
# does for validate_url(). A blocked request is answered the HTTP::Tiny way --
# a 599 "Internal Exception" response whose content says why -- rather than a
# die, so callers handle it on the same path as any other transport failure.

use strict;
use warnings;

use parent 'HTTP::Tiny';

use URI ();

use SignalWire::Utils::UrlValidator     ();
use SignalWire::Security::SecurityUtils ();

my %REDIRECT_STATUS = map { $_ => 1 } ( 301, 302, 303, 307, 308 );

sub new {
    my ( $class, %args ) = @_;
    my $allow_private = delete $args{allow_private} ? 1                   : 0;
    my $max_redirect  = exists $args{max_redirect}  ? $args{max_redirect} : 5;

    my $private_ok = $allow_private || SignalWire::Utils::UrlValidator::_env_allows_private();
    my $direct     = !( $private_ok || _proxy_allowed() );

    # Connect directly, so the peer address check applies: an explicit undef
    # stops HTTP::Tiny from reading the proxy environment.
    if ($direct) {
        $args{$_} = undef for qw(proxy http_proxy https_proxy);
    }

    # Verify TLS unless told otherwise (python's requests session verifies by
    # default; HTTP::Tiny's own default is version-dependent).
    $args{verify_SSL} = 1 unless exists $args{verify_SSL};

    # Redirects are followed here, hop by hop, so each target is checked.
    my $self = $class->SUPER::new( %args, max_redirect => 0 );
    $self->{_sw_allow_private} = $allow_private;
    $self->{_sw_max_redirect}  = $max_redirect;
    $self->{_sw_direct}        = $direct;
    return $self;
}

# The configured private-address policy.
sub allow_private { my ($self) = @_; return $self->{_sw_allow_private} }

sub request {
    my ( $self, $method, $url, $args ) = @_;
    my %args = %{ $args || {} };
    my @redirects;
    my $current = $url;

    while (1) {
        my $private_ok = $self->{_sw_allow_private};
        if ( !SignalWire::Utils::UrlValidator::validate_url( $current, $private_ok ) ) {
            return _refused(
                $current,
                'URL rejected: '
                    . SignalWire::Security::SecurityUtils::redact_url($current)
                    . ' is private, internal or invalid',
                \@redirects,
            );
        }

        my %send = %args;
        $send{peer} = \&_checked_peer
            if $self->{_sw_direct}
            && !$private_ok
            && !SignalWire::Utils::UrlValidator::_env_allows_private();

        my $res = $self->SUPER::request( $method, $current, \%send );

        my $location = $res->{headers}{location};
        $location = $location->[0] if ref $location eq 'ARRAY';
        my $follow =
               $REDIRECT_STATUS{ $res->{status} }
            && defined $location
            && ( $method eq 'GET' || $method eq 'HEAD' || $res->{status} == 303 );
        if ( !$follow || @redirects >= $self->{_sw_max_redirect} ) {
            $res->{redirects} = [@redirects] if @redirects;
            return $res;
        }

        push @redirects, $res;
        $current = URI->new_abs( $location, $current )->as_string;
        $method  = 'GET' if $res->{status} == 303;
        delete $args{content} if $method eq 'GET';
    }

    # Unreachable: the loop exits only through a return.
    return;
}

# HTTP::Tiny `peer` hook: resolve the host once, refuse a private or internal
# address, and connect to the address that was checked.
sub _checked_peer {
    my ($host) = @_;
    ( my $bare = $host ) =~ s/\A\[(.*)\]\z/$1/;
    my $ips = SignalWire::Utils::UrlValidator::_resolve($bare);
    die "Could not resolve $host\n" unless $ips && @$ips;
    for my $ip (@$ips) {
        die "Refused to connect to $host: $ip is a private or internal address\n"
            if SignalWire::Utils::UrlValidator::_address_is_blocked($ip);
    }
    return $ips->[0];
}

sub _refused {
    my ( $url, $reason, $redirects ) = @_;
    return {
        url     => $url,
        success => '',
        status  => 599,
        reason  => 'Internal Exception',
        content => "$reason\n",
        headers => {
            'content-type'   => 'text/plain',
            'content-length' => length("$reason\n"),
        },
        ( @$redirects ? ( redirects => [@$redirects] ) : () ),
    };
}

# SWML_URL_FETCH_USE_PROXY lets these fetches use the environment's proxy (one
# that restricts destinations itself).
sub _proxy_allowed {
    my $v = lc( $ENV{SWML_URL_FETCH_USE_PROXY} // '' );
    return ( $v eq '1' || $v eq 'true' || $v eq 'yes' ) ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Utils::UrlValidator::PublicSession - an HTTP::Tiny that refuses private and internal addresses

=head1 SYNOPSIS

    use SignalWire::Utils::UrlValidator::PublicSession;

    my $session = SignalWire::Utils::UrlValidator::PublicSession->new(
        agent   => 'MyFetcher/1.0',
        timeout => 5,
    );
    my $res = $session->get($user_supplied_url);
    # a private/internal target (or redirect) -> status 599, content says why

=head1 DESCRIPTION

An L<HTTP::Tiny> for fetching user-supplied URLs. Checking a URL with
C<validate_url> before fetching it is not enough on its own: the server can
redirect to an internal address, and the hostname can resolve differently when
the connection is made. This session checks the URL of every request it sends,
each redirect hop included, and pins a direct connection to an address it has
checked. It ignores C<HTTP_PROXY>/C<HTTPS_PROXY> (through a proxy the
connection check cannot apply) unless C<SWML_URL_FETCH_USE_PROXY> is set.
C<SWML_ALLOW_PRIVATE_URLS> -- or C<< allow_private => 1 >> -- turns the checks
off, as it does for C<validate_url>.

A refused request is returned the way HTTP::Tiny reports any transport failure:
status C<599>, reason C<Internal Exception>, with the reason as the content.

=head1 METHODS

=over 4

=item C<new(%args)>

Every L<HTTP::Tiny> constructor argument, plus C<allow_private>. C<verify_SSL>
defaults to 1 (TLS verification on). C<max_redirect>
(default 5) bounds the redirects followed; redirects are followed for C<GET> and
C<HEAD> (and a C<303> becomes a C<GET>), as HTTP::Tiny does.

=item C<request($method, $url, \%args)>

As L<HTTP::Tiny/request>, with every hop checked.

=item C<allow_private>

Whether private and internal addresses were allowed at construction.

=back

=head1 SEE ALSO

L<SignalWire::Utils::UrlValidator>, L<SignalWire::Skills::Builtin::Spider>.

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
