package SignalWire::Utils;
use strict;
use warnings;
use Exporter qw(import);

use SignalWire::Core::LoggingConfig ();

our @EXPORT_OK = qw(is_serverless_mode);

# Cross-language SDK contract: SignalWire::Utils::is_serverless_mode
# mirrors signalwire.utils.is_serverless_mode in the Python reference.
# Returns 1 (true) when running inside any short-lived / event-driven
# environment (i.e. anything other than 'server'); 0 otherwise.
sub is_serverless_mode {
    return SignalWire::Core::LoggingConfig::get_execution_mode() ne 'server'
        ? 1
        : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Utils - miscellaneous SDK utility functions

=head1 SYNOPSIS

    use SignalWire::Utils qw(is_serverless_mode);

    if ( is_serverless_mode() ) {
        # running in Lambda / a cloud function / CGI, not a long-lived server
    }

=head1 DESCRIPTION

L<SignalWire::Utils> is the Perl port of C<signalwire.utils>. It collects
small cross-cutting helpers. Nothing is exported by default; import from
C<@EXPORT_OK>.

=head1 FUNCTIONS

=over 4

=item C<is_serverless_mode()>

Return true (C<1>) when the SDK is running inside any short-lived /
event-driven environment — that is, when
L<SignalWire::Core::LoggingConfig/get_execution_mode> returns anything
other than C<'server'>. Returns C<0> otherwise.

=back

=head1 SEE ALSO

L<SignalWire::Core::LoggingConfig>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
