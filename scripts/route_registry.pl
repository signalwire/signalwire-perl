#!/usr/bin/env perl
# route_registry.pl — enumerate the REST routes the Perl SDK ACTUALLY IMPLEMENTS.
#
# "Set B" for the cross-port SPEC-PARITY gate: the routes the live RestClient
# dispatches, captured from the REAL code path — not parsed from source (an AST
# scraper would re-implement the Base/_path machinery and drift) and not read
# from the test journal (which only sees TESTED routes, the blind spot the gate
# closes).
#
# How: build the real RestClient with a RECORDING HttpClient injected via the
# lazy `_http` attribute — it overrides the verb methods to capture (method,
# path) and return {} (no network). Then walk every namespace accessor on the
# client, every Base-derived sub-resource, and every public route method,
# invoking each with sentinel args ('__ID__' for path params, normalised back to
# {id}). A method that cannot be invoked is a hard ERROR (recorded + non-zero
# exit) unless listed in %REGISTRY_SKIP with a reason — mirrors
# python_route_registry.py / route-registry.ts.
#
# Output: JSON {"routes":[{"method","path_template","via"}],"skipped":[...],
# "errors":[...]} on stdout (diagnostics to stderr). Exit 1 if Set B is incomplete.
#
# Run from the signalwire-perl repo root:  perl -Ilib scripts/route_registry.pl
#
# REUSABLE MODULE: this file is `package RouteRegistry` with a run-if-main guard,
# so scripts/rest_test_plan.pl (the REST wire-TEST generator's per-`via` call
# plan) can `require` it and reuse the SAME live-client walk — the plan can never
# drift from the registry's route set (mirrors ruby's route_registry.rb +
# rest_test_plan.rb split). When required, only the subs are defined; the
# top-level walk + JSON print run only when this file is the program entry point.

package RouteRegistry;

use strict;
use warnings;
use Scalar::Util ();
use JSON::PP     ();

use SignalWire::REST::RestClient;

# Sentinel for any path parameter: one segment, no '/', normalised to {id}. The
# project id passed to the client also becomes a path segment (compat's
# {AccountSid}); we pass the same sentinel so it too normalises to {id}.
our $SENTINEL = '__ID__';

# Methods that do NOT map to a single canonical route, keyed by
# "<ns>.<resource>.<method>" or a "<ns>.<resource>.*" / "*.<method>" wildcard.
# Every entry needs a reason; a method that fails to invoke or issues no HTTP
# request is an ERROR, not an implicit skip.
our %REGISTRY_SKIP = (

    # cXML applications expose list/get/update/delete/list_addresses but NOT create
    # — the generated CxmlApplications resource extends BaseResource with no create
    # method (cXML apps cannot be created via the API), so there is no route to
    # skip. (Left empty; entries added here need a reason.)

    # paginate is a client-side pagination helper on every ReadResource: it returns
    # a lazy paginator that follows the cursor via the already-covered list route
    # and issues no HTTP request itself, so it is not a distinct wire route. Mirrors
    # the python reference's paginate skip in porting-sdk python_route_registry.py.
    '*.paginate' =>
'client-side pagination helper, not a route (issues no HTTP request; follows the covered list route lazily)',
);

# Moo / Moo::Object sugar + base plumbing that are NOT route methods. (This
# denylist is what keeps the symbol-table walk from thrashing on imported
# keywords.)
our %SUGAR = map { $_ => 1 } qw(
    has with extends around before after new meta does DOES
    import unimport BUILD BUILDARGS BUILDALL DEMOLISHALL can isa
);

# Top-level namespace accessors exposed on RestClient. The flat resources +
# namespace containers are provided by the generated ResourceTree role the client
# composes (accessor names verbatim from the specs). `project` is the
# ProjectNamespace container (the raw project-id credential lives on the private
# `_project_id` slot).
our @NAMESPACES = qw(
    fabric calling phone_numbers addresses queues recordings number_groups
    verified_callers sip_profile lookup short_codes imported_numbers mfa
    registry datasphere video logs project pubsub chat
);

# ---- recording HTTP client -------------------------------------------------
{

    package RecordingHttpClient;
    use Moo;
    has _calls => ( is => 'rw', default => sub { [] } );

    sub _reset {
        my ($self) = @_;
        $self->_calls( [] );
        return;
    }

    sub _snapshot {
        my ($self) = @_;
        return @{ $self->_calls };
    }

    sub _record {
        my ( $self, $method, $path ) = @_;
        push @{ $self->_calls }, [ $method, $path ];
        return {};
    }

    # Verb wrappers the Base resource calls (mirror the real HttpClient API).
    sub get {
        my ( $self, $path ) = @_;
        return $self->_record( 'GET', $path );
    }

    sub post {
        my ( $self, $path ) = @_;
        return $self->_record( 'POST', $path );
    }

    sub put {
        my ( $self, $path ) = @_;
        return $self->_record( 'PUT', $path );
    }

    sub patch {
        my ( $self, $path ) = @_;
        return $self->_record( 'PATCH', $path );
    }

    sub delete_request {
        my ( $self, $path ) = @_;
        return $self->_record( 'DELETE', $path );
    }
}

sub is_resource {
    my ($obj) = @_;
    return Scalar::Util::blessed($obj)
        && $obj->isa('SignalWire::REST::Namespaces::Base');
}

sub public_methods {
    my ($obj) = @_;
    my %seen_pkg;
    my %methods;
    my @queue = ( ref $obj );

    # Symbol-table introspection genuinely needs soft refs to read @ISA and the
    # stash of each package in the chain; there is no Moo meta-object to use.
    no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict)
    while ( my $pkg = shift @queue ) {
        next if $seen_pkg{$pkg}++;
        last if $pkg eq 'Moo::Object';    # stop before the Moo base
        push @queue, @{"${pkg}::ISA"};
        for my $sym ( keys %{"${pkg}::"} ) {
            next if $sym =~ /^_/;         # private
            next if $sym !~ /^[a-z]/;     # not a route method name
            next if $SUGAR{$sym};         # Moo sugar / plumbing
            next unless defined &{"${pkg}::${sym}"};
            $methods{$sym} = 1;
        }
    }
    my @names = sort keys %methods;
    return @names;
}

sub skip_reason {
    my ($key) = @_;
    return $REGISTRY_SKIP{$key} if exists $REGISTRY_SKIP{$key};
    ( my $star_res = $key ) =~ s/\.[^.]+$/.*/;            # <ns>.<res>.*
    return $REGISTRY_SKIP{$star_res} if exists $REGISTRY_SKIP{$star_res};
    ( my $star_meth = $key ) =~ s/^[^.]+\.[^.]+\./*./;    # *.<method>
    return $REGISTRY_SKIP{$star_meth} if exists $REGISTRY_SKIP{$star_meth};
    return;
}

# Number of leading positional sentinels to supply. A method may take up to this
# many required POSITIONAL path ids (get($id), get_chunk($documentId, $chunkId),
# queue members get($queue_id, $member_id)); the deepest real signature is 2 path
# ids, so 3 is a safe upper bound. Every sentinel is '__ID__' so each fills a
# path-id slot and normalises to {id}; extra sentinels beyond a method's arity
# land in its trailing %params/%kwargs (harmless — they don't shape the path).
#
# CRITICAL: we do NOT append a `body => {}` kwarg. Doing so leaks the literal
# string "body" into the SECOND positional slot of a multi-id method
# (get_chunk($documentId, $chunkId) then captured $chunkId eq 'body' → the
# malformed path .../chunks/body instead of .../chunks/{id}). Padding with real
# ID sentinels instead gives every positional path id a proper {id} placeholder.
our $POSITIONAL_SENTINELS = 3;

# Invoke a route method with sentinel args: $POSITIONAL_SENTINELS leading '__ID__'
# positionals fill every required path-id slot (list/create ignore them; get/
# update/delete/get_chunk consume 1–2). Some helper methods (phone_numbers.set_*)
# validate REQUIRED named kwargs and die "'<key>' is required" before dispatching
# — those ARE real routes, so when we see that error we learn the missing key
# from the SDK's own message and retry with it set to the sentinel, accumulating
# keys until the call dispatches (or fails for a non-missing-kwarg reason).
# Body/param values don't affect the captured path.
#
# Returns (error_string, \@required_kwarg_keys): error_string is '' on success;
# @required_kwarg_keys is the list of kwarg names the SDK demanded (in discovery
# order) so the TEST plan can reproduce the SAME faithful call. On error the key
# list is empty.
sub invoke_method {
    my ( $obj, $method ) = @_;
    my @pos = ($SENTINEL) x $POSITIONAL_SENTINELS;
    my %kw;
    my @kw_order;
    for ( 1 .. 12 ) {    # bounded: at most a handful of required kwargs
        local $@;
        my $ok = eval { $obj->$method( @pos, %kw ); 1 };
        return ( '', \@kw_order ) if $ok;
        my $err = "$@";
        if ( $err =~ /'([A-Za-z0-9_]+)'\s+is\s+required/ && !exists $kw{$1} ) {
            $kw{$1} = $SENTINEL;    # supply the required key the SDK named, retry
            push @kw_order, $1;
            next;
        }
        $err =~ s/\s+at\s+\S+\s+line\s+\d+.*//s;    # trim file:line noise
        $err =~ s/\s+$//;
        return ( $err || 'died', [] );
    }
    return ( 'could not satisfy required arguments after 12 retries', [] );
}

# Walk the live client, invoking every route method through the recording HTTP
# client. $on_route->($ns_name, $res_name, $method, $verb, $path_template,
# \@required_kwargs, $res) is called once per (via, captured-call) with the {id}-
# normalised path and the LIVE resource object (so a consumer can re-invoke it —
# rest_test_plan.pl's verify_call does). Returns { skipped => [...],
# errors => [...] }. Reused by BOTH the registry (build) and the test plan
# (rest_test_plan.pl) so they can't drift.
sub walk {
    my ($on_route) = @_;
    my $http       = RecordingHttpClient->new;
    my $client     = SignalWire::REST::RestClient->new(
        project => $SENTINEL,
        token   => 't',
        host    => 'example.signalwire.com',
        _http   => $http,
    );

    my @skipped;
    my @errors;

    my $handle = sub {
        my ( $ns_name, $res_name, $res ) = @_;
        for my $m ( public_methods($res) ) {
            my $key = "$ns_name.$res_name.$m";
            if ( defined( my $reason = skip_reason($key) ) ) {
                push @skipped, { key => $key, reason => $reason };
                next;
            }
            $http->_reset;
            my ( $err, $kw ) = invoke_method( $res, $m );
            if ( $err ne '' ) {
                push @errors, { key => $key, error => $err };
                next;
            }
            my @calls = $http->_snapshot;
            if ( !@calls ) {
                push @errors,
                    {
                    key   => $key,
                    error => 'invoked but issued no HTTP request '
                        . '(client-side helper? add to %REGISTRY_SKIP with a reason)'
                    };
                next;
            }
            for my $c (@calls) {
                my ( $verb, $path ) = @$c;
                $path =~ s/\Q$SENTINEL\E/{id}/g;
                $on_route->( $ns_name, $res_name, $m, $verb, $path, $kw, $res );
            }
        }
        return;
    };

    for my $ns_name (@NAMESPACES) {
        next unless $client->can($ns_name);
        my $ns = eval { $client->$ns_name };
        next unless defined $ns && ref $ns;

        # A namespace may itself be a flat resource with route methods…
        $handle->( $ns_name, $ns_name, $ns ) if is_resource($ns);

        # …and/or a container of sub-resources.
        for my $acc ( public_methods($ns) ) {
            my $val = eval { $ns->$acc };
            next unless defined $val && is_resource($val);
            $handle->( $ns_name, $acc, $val );
        }
    }

    return { skipped => \@skipped, errors => \@errors };
}

# Build the deduped (via-merged) route set — the registry's Set B.
sub build {
    my @routes;
    my %route_idx;    # "METHOD PATH" => index into @routes (for via dedup)

    my $meta = walk(
        sub {
            my ( $ns_name, $res_name, $method, $verb, $path ) = @_;
            my $key = "$ns_name.$res_name.$method";
            my $rk  = "$verb $path";
            if ( defined( my $i = $route_idx{$rk} ) ) {
                push @{ $routes[$i]{via} }, $key;
            } else {
                push @routes, { method => $verb, path_template => $path, via => [$key] };
                $route_idx{$rk} = $#routes;
            }
        }
    );

    # Deterministic ordering.
    @routes =
        sort { $a->{path_template} cmp $b->{path_template} || $a->{method} cmp $b->{method} }
        @routes;
    $_->{via} = [ sort @{ $_->{via} } ] for @routes;
    my @skipped = sort { $a->{key} cmp $b->{key} } @{ $meta->{skipped} };
    my @errors  = sort { $a->{key} cmp $b->{key} } @{ $meta->{errors} };

    return { routes => \@routes, skipped => \@skipped, errors => \@errors };
}

# Run-if-main: emit the registry JSON only when this file is the program entry
# point (not when rest_test_plan.pl `require`s it as a module).
unless ( caller() ) {
    my $result = build();
    my $json   = JSON::PP->new->canonical->pretty;
    print $json->encode($result);
    exit( @{ $result->{errors} } ? 1 : 0 );
}

1;
