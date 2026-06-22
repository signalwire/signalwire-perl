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

use strict;
use warnings;
use Scalar::Util ();
use JSON::PP     ();

use SignalWire::REST::RestClient;

# Sentinel for any path parameter: one segment, no '/', normalised to {id}. The
# project id passed to the client also becomes a path segment (compat's
# {AccountSid}); we pass the same sentinel so it too normalises to {id}.
my $SENTINEL = '__ID__';

# Methods that do NOT map to a single canonical route, keyed by
# "<ns>.<resource>.<method>" or a "<ns>.<resource>.*" / "*.<method>" wildcard.
# Every entry needs a reason; a method that fails to invoke or issues no HTTP
# request is an ERROR, not an implicit skip.
my %REGISTRY_SKIP = (

    # cXML applications expose the CRUD surface but create is unsupported (dies
    # by design) — no POST /cxml_applications canonical route. Mirrors python.
    'fabric.cxml_applications.create' =>
        'no create route — dies by design (cXML apps cannot be created via API)',
);

# Moo / Moo::Object sugar + base plumbing that are NOT route methods. (This
# denylist is what keeps the symbol-table walk from thrashing on imported
# keywords.)
my %SUGAR = map { $_ => 1 } qw(
    has with extends around before after new meta does DOES
    import unimport BUILD BUILDARGS BUILDALL DEMOLISHALL can isa
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

# Top-level namespace accessors exposed on RestClient (the `has ... lazy` names).
my @NAMESPACES = qw(
    fabric calling phone_numbers addresses queues recordings number_groups
    verified_callers sip_profile lookup short_codes imported_numbers mfa
    registry datasphere video logs project_ns pubsub chat compat
);

my @routes;       # { method, path_template, via }
my @skipped;      # { key, reason }
my @errors;       # { key, error }
my %route_idx;    # "METHOD PATH" => index into @routes (for via dedup)

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

# Invoke a route method with sentinel args. get/update/delete take a leading id;
# list/create take none; (id, body) covers the common shapes and Perl ignores
# extra args. Some helper methods (phone_numbers.set_*) validate REQUIRED named
# kwargs and die "'<key>' is required" before dispatching — those ARE real
# routes, so when we see that error we learn the missing key from the SDK's own
# message and retry with it set to the sentinel, accumulating keys until the
# call dispatches (or fails for a non-missing-kwarg reason). Body/param values
# don't affect the captured path.
sub invoke_method {
    my ( $obj, $method ) = @_;
    my %kw;
    for ( 1 .. 12 ) {    # bounded: at most a handful of required kwargs
        local $@;
        my $ok = eval { $obj->$method( $SENTINEL, %kw, ( body => {} ) ); 1 };
        return '' if $ok;
        my $err = "$@";
        if ( $err =~ /'([A-Za-z0-9_]+)'\s+is\s+required/ && !exists $kw{$1} ) {
            $kw{$1} = $SENTINEL;    # supply the required key the SDK named, retry
            next;
        }
        $err =~ s/\s+at\s+\S+\s+line\s+\d+.*//s;    # trim file:line noise
        $err =~ s/\s+$//;
        return $err || 'died';
    }
    return 'could not satisfy required arguments after 12 retries';
}

sub handle_resource {
    my ( $http, $ns_name, $res_name, $res ) = @_;
    for my $m ( public_methods($res) ) {
        my $key = "$ns_name.$res_name.$m";
        if ( defined( my $reason = skip_reason($key) ) ) {
            push @skipped, { key => $key, reason => $reason };
            next;
        }
        $http->_reset;
        my $err = invoke_method( $res, $m );
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
            my $rk = "$verb $path";
            if ( defined( my $i = $route_idx{$rk} ) ) {
                push @{ $routes[$i]{via} }, $key;
            } else {
                push @routes, { method => $verb, path_template => $path, via => [$key] };
                $route_idx{$rk} = $#routes;
            }
        }
    }
    return;
}

# Sub-resources of a namespace: blessed Base-derived objects reachable via its
# public accessors (Moo `has ... lazy`).
sub sub_resources {
    my ($ns) = @_;
    my @out;
    for my $acc ( public_methods($ns) ) {
        my $val = eval { $ns->$acc };
        next unless defined $val && is_resource($val);
        push @out, [ $acc, $val ];
    }
    return @out;
}

# --------------------------------------------------------------------------
my $http   = RecordingHttpClient->new;
my $client = SignalWire::REST::RestClient->new(
    project => $SENTINEL,
    token   => 't',
    host    => 'example.signalwire.com',
    _http   => $http,
);

for my $ns_name (@NAMESPACES) {
    next unless $client->can($ns_name);
    my $ns = eval { $client->$ns_name };
    next unless defined $ns && ref $ns;

    # A namespace may itself be a flat resource with route methods…
    handle_resource( $http, $ns_name, $ns_name, $ns ) if is_resource($ns);

    # …and/or a container of sub-resources.
    handle_resource( $http, $ns_name, $_->[0], $_->[1] ) for sub_resources($ns);
}

# Deterministic ordering.
@routes =
    sort { $a->{path_template} cmp $b->{path_template} || $a->{method} cmp $b->{method} } @routes;
$_->{via} = [ sort @{ $_->{via} } ] for @routes;
@skipped  = sort { $a->{key} cmp $b->{key} } @skipped;
@errors   = sort { $a->{key} cmp $b->{key} } @errors;

my $json = JSON::PP->new->canonical->pretty;
print $json->encode( { routes => \@routes, skipped => \@skipped, errors => \@errors } );

exit( @errors ? 1 : 0 );
