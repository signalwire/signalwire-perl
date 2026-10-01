package SignalWire::Core::Capabilities;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# Reading what a client says it can do. Mirrors signalwire.core.capabilities.
#
# A browser client (the SignalWire address widget, or anything speaking the
# same convention) declares its rendering capabilities in the user variables it
# sends at dial time:
#
#   { "vars": { "userVariables": { "capabilities": { "display_content": true, ... } } } }
#
# These are declarations of what the client can RENDER, not grants of
# authority. Absence means no: every function here resolves errors and missing
# data to "not declared".

use strict;
use warnings;

use B    ();
use JSON ();

use Exporter qw(import);
our @EXPORT_OK = qw(declared_capabilities has_capability user_variables);

# The user variables from a SWML request body (vars.userVariables), or {}.
sub user_variables {
    my ($body_params) = @_;
    return {} unless ref $body_params eq 'HASH';
    return {} if exists $body_params->{vars} && ref $body_params->{vars} ne 'HASH';
    my $vars      = $body_params->{vars} // {};
    my $variables = exists $vars->{userVariables} ? $vars->{userVariables} : {};
    return ref $variables eq 'HASH' ? $variables : {};
}

# The capability names the client declared as truthy, as a sorted arrayref.
# Accepts a full SWML request body or an already-extracted user-variables
# hashref. Empty when nothing was declared or the payload was malformed.
sub declared_capabilities {
    my ($body_params) = @_;
    my $variables = user_variables($body_params);

    # Already-extracted user variables were passed directly.
    $variables = $body_params if !%$variables && ref $body_params eq 'HASH';

    my $capabilities = $variables->{capabilities};
    return [] unless ref $capabilities eq 'HASH';
    return [ sort grep { _py_truthy( $capabilities->{$_} ) } keys %$capabilities ];
}

# Whether the client declared $name -- true only when explicitly declared truthy.
sub has_capability {
    my ( $body_params, $name ) = @_;
    return 0 unless defined $name;
    return ( grep { $_ eq $name } @{ declared_capabilities($body_params) } ) ? 1 : 0;
}

# Python truthiness for a JSON-decoded value (a non-empty string, even "0",
# is truthy; empty containers, 0, null and false are not).
sub _py_truthy {
    my ($v) = @_;
    return 0 unless defined $v;
    return $v          ? 1 : 0 if JSON::is_bool($v);
    return scalar(%$v) ? 1 : 0 if ref $v eq 'HASH';
    return scalar(@$v) ? 1 : 0 if ref $v eq 'ARRAY';
    return 1 if ref $v;
    my $flags = B::svref_2object( \$v )->FLAGS;
    return length($v) ? 1 : 0
        if ( $flags & B::SVp_POK() ) || !( $flags & ( B::SVp_IOK() | B::SVp_NOK() ) );
    return $v != 0 ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::Capabilities - read the rendering capabilities a client declared

=head1 SYNOPSIS

    use SignalWire::Core::Capabilities qw(has_capability declared_capabilities);

    $agent->add_per_call_config( sub {
        my ( $query, $body, $headers, $agent ) = @_;
        if ( has_capability( $body, 'display_content' ) ) {
            $agent->prompt_add_section( 'Screen', 'You can show content on the caller\'s screen.' );
        }
    } );

=head1 DESCRIPTION

A browser client declares what it can render in the user variables it sends at
dial time (C<< vars.userVariables.capabilities >>). These are hints for
deciding what to offer, B<never> grants of authority -- a caller controls its
own user variables. Absence means no: errors and missing data resolve to "not
declared", because offering a PSTN caller something only a browser can show is
worse than never mentioning it. There is deliberately no enum of capability
names: a client may declare something this SDK has never heard of.

=head1 FUNCTIONS

All are exportable on request.

=over 4

=item C<user_variables($body_params)>

The user variables from a SWML request body (C<vars.userVariables>), or C<{}>.

=item C<declared_capabilities($body_params)>

The capability names declared truthy, as a sorted arrayref. Accepts a full SWML
request body or an already-extracted user-variables hashref. Empty when nothing
was declared, the payload was malformed, or the client is not a browser.

=item C<has_capability($body_params, $name)>

True (1) only when C<$name> was explicitly declared truthy; 0 otherwise.

=back

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
