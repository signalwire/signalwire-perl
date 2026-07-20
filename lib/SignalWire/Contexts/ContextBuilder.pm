package SignalWire::Contexts::ContextBuilder;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# This file is a thin loader: the real SignalWire::Contexts::ContextBuilder
# package (along with Context, Step, GatherInfo, GatherQuestion, and helpers)
# is defined inside lib/SignalWire/Contexts.pm. Loading the parent module
# defines all of those packages in one shot.
#
# Earlier this file shipped a 28-line stub that overrode the real
# implementation when AgentBase did `require SignalWire::Contexts::ContextBuilder`.
# Now we just re-load the canonical source so the require yields the full DSL.

use strict;
use warnings;

require SignalWire::Contexts;

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Contexts::ContextBuilder - loader for the ContextBuilder workflow DSL

=head1 SYNOPSIS

    use SignalWire::Contexts::ContextBuilder;

    my $builder = SignalWire::Contexts::ContextBuilder->new;
    my $ctx     = $builder->add_context('default');
    $ctx->add_step('start', task => 'Greet the caller.')->set_end(1);
    my $swml = $builder->to_hash;

=head1 DESCRIPTION

This file is a thin loader. The real
C<SignalWire::Contexts::ContextBuilder> package — along with C<Context>,
C<Step>, C<GatherInfo>, C<GatherQuestion>, and the module helpers — is
defined inside L<SignalWire::Contexts>. Requiring this module simply loads
L<SignalWire::Contexts>, which defines all of those packages in one shot,
so C<< require SignalWire::Contexts::ContextBuilder >> yields the full DSL.

See L<SignalWire::Contexts> for the constructor, the public method surface,
and worked examples.

=head1 SEE ALSO

L<SignalWire::Contexts>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
