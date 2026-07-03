#!/usr/bin/env perl
# rest_test_plan.pl — per-`via` call plan for the REST wire-test generator.
#
# Companion capture to scripts/route_registry.pl. route_registry.pl answers
# "which (method, path) routes does the SDK implement" (deduped, via-merged) for
# the SPEC-PARITY gate; this script answers the sibling question the TEST
# generator (scripts/generate_rest_tests.py) needs: for EVERY `via` accessor
# method, what is the exact Perl call expression that reaches it AND what sentinel
# arguments must be passed. It is the Perl realisation of the reflection the
# ruby/go/ts/php generators do in their own language (rest_test_plan.rb in Ruby,
# buildCallIndex in go, SignatureResolver in ts).
#
# It REUSES route_registry.pl's live-client walk (RouteRegistry::walk, which
# drives the real RestClient through the recording HttpClient and the SAME
# invoke_method + required-kwarg discovery) so the plan can never drift from the
# registry's route set. For each route method it records, per `via`:
#   - via     : "<ns>.<res>.<member>" — identical to route_registry.pl's via
#               strings, so the generator joins registry routes -> spec
#               operationId -> this plan by via with no ambiguity.
#   - method  : the HTTP verb captured from the recording client.
#   - path    : the captured path template (params already {id}).
#   - chain   : the ordered accessor call chain to reach the method off the
#               client — ["video","rooms"] for video.rooms.get, or ["calling"]
#               for the flat calling.calling.dial (the leading duplicate
#               namespace segment is collapsed, mirroring ruby/go/ts/php attrPath).
#   - member  : the route method name (get, create, list_streams, ...).
#   - args    : the ordered Perl literal argument tokens for the method's REQUIRED
#               params — one 'x' POSITIONAL per {id} path segment (a valid
#               one-segment path id), followed by `key => 'x'` for every REQUIRED
#               named kwarg the SDK demanded (discovered by RouteRegistry's
#               invoke_method from the SDK's own "'<key>' is required" die).
#               Perl has no formal signature reflection, and every closed required
#               field the SDK exposes is string-shaped at the wire (a path id or a
#               body string), so a single 'x' sentinel is type-faithful for all of
#               them — proven by rest_test_plan.pl RE-INVOKING every via with
#               EXACTLY these emitted tokens (verify_call) and reporting zero
#               errors before emitting the plan.
#
# Output: JSON {"plan":[{via,method,path,chain,member,args}],"errors":[...]} on
# stdout. Exit 1 if any route method could not be reflected/re-invoked (never
# silently dropped — a dropped via is a hole in the generated suite). Mirrors
# route_registry.pl's fail-loud contract.
#
# Run: perl -Ilib scripts/rest_test_plan.pl   (via generate_rest_tests.py)

use strict;
use warnings;
use FindBin  ();
use JSON::PP ();

require "$FindBin::Bin/route_registry.pl";    ## no critic (Modules::RequireBarewordIncludes)

# The literal Perl sentinel for a required string arg — a valid one-segment path
# id AND a valid closed-param body string.
my $ARG = "'x'";

# Collapse a leading duplicate accessor segment, mirroring ruby/go/ts/php
# attrPath: a flat namespace's chain is [calling, calling] -> [calling]; a
# container chain [video, rooms] is unchanged.
sub collapse_chain {
    my ( $ns, $res ) = @_;
    return $ns eq $res ? [$ns] : [ $ns, $res ];
}

# The Perl literal argument tokens for a route's REQUIRED params: one 'x'
# positional per {id} path segment, then `key => 'x'` for each SDK-required
# kwarg (discovery order preserved). Positionals first, then keywords — matching
# the real method signatures (get($id), update($id, %kwargs), create(%kwargs)).
sub arg_tokens {
    my ( $path, $required_kw ) = @_;
    my $n_ids  = () = $path =~ /\{id\}/g;
    my @tokens = ($ARG) x $n_ids;
    push @tokens, "$_ => $ARG" for @$required_kw;
    return \@tokens;
}

# Re-invoke a via with EXACTLY the emitted token shape (n_ids positionals +
# key => sentinel kwargs) against a fresh recording client, and confirm it
# dispatches the SAME (verb, path) the registry captured. This makes the plan
# self-verifying: a token shape that would not reproduce the route is a hard
# error, never a silently-wrong generated test.
sub verify_call {
    my ( $res, $member, $path, $required_kw, $verb ) = @_;
    my $n_ids = () = $path =~ /\{id\}/g;
    my @args  = ($RouteRegistry::SENTINEL) x $n_ids;
    push @args, ( $_ => $RouteRegistry::SENTINEL ) for @$required_kw;

    my $http = $res->_http;
    $http->_reset;
    local $@;
    my $ok = eval { $res->$member(@args); 1 };
    return "re-invoke died: $@" unless $ok;
    my @calls = $http->_snapshot;
    return 're-invoke issued no HTTP request' unless @calls;
    my ( $v, $p ) = @{ $calls[0] };
    $p =~ s/\Q$RouteRegistry::SENTINEL\E/{id}/g;
    return "re-invoke produced $v $p, expected $verb $path"
        unless $v eq $verb && $p eq $path;
    return '';
}

my @plan;
my @errors;
my %seen_via;    # a via may capture >1 call; plan it once (first capture)

# Reuse the registry walk. $res is the live resource object, so we can re-invoke
# it for verify_call — the plan literally re-drives the same objects the registry
# walked, so it cannot diverge from Set B.
my $meta = RouteRegistry::walk(
    sub {
        my ( $ns_name, $res_name, $member, $verb, $path, $required_kw, $res ) = @_;
        my $via = "$ns_name.$res_name.$member";
        return if $seen_via{$via}++;
        my $err = verify_call( $res, $member, $path, $required_kw, $verb );
        if ($err) {
            push @errors, { via => $via, error => $err };
            return;
        }
        push @plan,
            {
            via    => $via,
            method => $verb,
            path   => $path,
            chain  => collapse_chain( $ns_name, $res_name ),
            member => $member,
            args   => arg_tokens( $path, $required_kw ),
            };
        return;
    }
);

push @errors, @{ $meta->{errors} };
@plan   = sort { $a->{via} cmp $b->{via} } @plan;
@errors = sort { ( $a->{via} // '' ) cmp( $b->{via} // '' ) } @errors;

my $json = JSON::PP->new->canonical->pretty;
print $json->encode( { plan => \@plan, errors => \@errors } );
exit( @errors ? 1 : 0 );
