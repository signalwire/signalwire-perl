#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# emit-corpus.pl — the Perl port's EMISSION-DUMP program for the cross-port
# emission differ (porting-sdk/scripts/diff_port_emission.py).
#
# It builds the shared FunctionResult corpus
# (porting-sdk/scripts/emission_corpus.py — the single source of truth) using
# the Perl SDK's native SignalWire::SWAIG::FunctionResult API, serialises each
# entry the SAME way the SDK serialises on the wire (to_hash), and prints ONE
# JSON object mapping
#
#     corpus-id -> emission
#
# to stdout. The differ runs this program, parses that object, and byte-compares
# each entry against Python's to_dict(). See the "per-port dump contract" in the
# differ's --help and porting-sdk/IDIOM_PASS_JOURNAL.md §4 Tier-0; bin/emit-corpus
# mirrors signalwire-go/cmd/emit-corpus.
#
# CONTRACT (why this file looks the way it does):
#   - The corpus is read at runtime from the shared spec
#     (`python3 .../emission_corpus.py`, the single source of truth) and each
#     entry is dispatched by its CANONICAL Python method name. The id set is
#     therefore IDENTICAL to emission_corpus.corpus_ids() by construction (the
#     differ rejects an id-set mismatch as a setup error — a skewed set would
#     mask real diffs).
#   - The argument VALUES are the WIRE values (plain strings/numbers/bools/maps).
#     The corpus is positional/keyword in PYTHON terms; this dispatcher reshapes
#     each call into the Perl method's native signature (most Perl FunctionResult
#     verbs take %opts keyword args, e.g. send_sms/pay/execute_rpc/switch_context
#     take their leading positionals as named opts). Closed-set string values
#     pass straight through, proving the typed path emits byte-identically.
#   - Only stdout carries the JSON object; nothing else is printed there. Logs
#     (and the corpus-resolution diagnostics) go to stderr.
#   - The empty-object envelope (clear_dynamic_hints -> {}) is serialised by
#     to_hash as a plain Perl hashref, which JSON canonical renders as `{}`
#     (an object), NOT `[]` — see to_hash / clear_dynamic_hints.
#
# Run from the signalwire-perl repo root:
#
#     perl bin/emit-corpus.pl
#
# (the differ invokes exactly this; see PORT_DUMP_CMDS / --dump-cmd).

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

# Make the SDK importable when run from the repo root (bin/.. = repo root; lib/
# is a sibling of bin/). Mirrors how the other bin/ tools resolve lib/.
use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::SWAIG::FunctionResult;

# --------------------------------------------------------------------------- #
# Locate + load the shared corpus spec.
# --------------------------------------------------------------------------- #
# The corpus is the SINGLE source of truth. `python3 emission_corpus.py` dumps
# it as JSON (data-only; it does NOT import signalwire-python). We walk upward
# from this file to find porting-sdk/scripts/emission_corpus.py (the adjacency
# convention — porting-sdk cloned beside the port repo).
sub find_corpus_script {

    # 1. Explicit override.
    if ( my $p = $ENV{EMISSION_CORPUS} ) {
        return $p if -f $p;
        die "emit-corpus: EMISSION_CORPUS=$p does not exist\n";
    }

    # 2. Walk up from this script looking for ../porting-sdk/scripts/...
    my $dir = $RealBin;
    for ( 1 .. 8 ) {
        my $cand = File::Spec->catfile( $dir, File::Spec->updir, 'porting-sdk', 'scripts',
            'emission_corpus.py' );
        return $cand if -f $cand;
        my $parent = File::Spec->catdir( $dir, File::Spec->updir );
        last if File::Spec->rel2abs($parent) eq File::Spec->rel2abs($dir);
        $dir = $parent;
    }

    # 3. Home-relative fallback (CLAUDE.md §7 adjacency).
    my $home = $ENV{HOME} // '';
    if ($home) {
        my $cand =
            File::Spec->catfile( $home, 'src', 'porting-sdk', 'scripts', 'emission_corpus.py' );
        return $cand if -f $cand;
    }
    die "emit-corpus: cannot locate porting-sdk/scripts/emission_corpus.py "
        . "(clone porting-sdk adjacent to this repo, or set EMISSION_CORPUS).\n";
}

sub load_corpus {
    my $script = find_corpus_script();

    # Read the corpus JSON the spec prints on stdout.
    my $json = qx{python3 "$script"};
    die "emit-corpus: failed to run python3 on $script (exit $?)\n" if $? != 0;
    die "emit-corpus: empty corpus from $script\n" unless length $json;
    return JSON->new->decode($json);
}

# --------------------------------------------------------------------------- #
# Argument-shape helpers.
# --------------------------------------------------------------------------- #
# The corpus speaks PYTHON arg shape (positional args + keyword args). The Perl
# verbs each have a native signature; these helpers reshape one corpus entry's
# (args, kwargs) into the Perl call.

# Turn a decoded-JSON kwargs hashref into a flat (key => value, ...) list,
# preserving the values verbatim (strings/numbers stay scalars; JSON true/false
# stay JSON::PP::Boolean objects, which the verbs read in boolean context;
# arrays/objects stay array/hash refs).
sub kw_list ($kwargs) {
    return () unless $kwargs;
    return map { $_ => $kwargs->{$_} } keys %$kwargs;
}

# --------------------------------------------------------------------------- #
# The dispatch table: canonical Python method name -> coderef($fr, $args, $kwargs)
# that applies the call to the FunctionResult $fr and returns $fr.
# --------------------------------------------------------------------------- #
# Grouped to mirror emission_corpus.py. Each coderef performs ONLY the Python->
# Perl arg reshaping; the emission itself is the verb's own native behavior.
my %DISPATCH;

# ---- pure single-positional verbs (Python positional -> Perl positional) ----
for my $m (
    qw(
    say hold update_global_data remove_global_data set_metadata remove_metadata
    swml_user_event swml_change_step swml_change_context add_dynamic_hints
    set_end_of_speech_timeout set_speech_event_timeout toggle_functions
    update_settings simulate_user_input join_room sip_refer
    )
    )
{
    $DISPATCH{$m} = sub ( $fr, $args, $kwargs ) {
        return $fr->$m(@$args);
    };
}

# ---- zero-arg verbs ---------------------------------------------------------
for my $m (qw(hangup stop stop_background_file clear_dynamic_hints)) {
    $DISPATCH{$m} = sub ( $fr, $args, $kwargs ) {
        return $fr->$m();
    };
}

# ---- optional-single-arg verbs (default applied when corpus omits it) -------
# replace_in_history($text?), enable_functions_on_timeout($enabled?),
# enable_extensive_data($enabled?). The corpus passes the arg positionally when
# present (e.g. extensive_data.false => [false]); absent => Perl default.
for my $m (qw(replace_in_history enable_functions_on_timeout enable_extensive_data)) {
    $DISPATCH{$m} = sub ( $fr, $args, $kwargs ) {
        return @$args ? $fr->$m(@$args) : $fr->$m();
    };
}

# ---- keyword-only verbs (Perl %opts; corpus already keyword) ----------------
# play_background_file(filename, wait=>...), wait_for_user(enabled/timeout/
# answer_first=>...), record_call(...), stop_record_call(...), tap(uri, ...),
# stop_tap(...), execute_swml(content, transfer=>...).
$DISPATCH{play_background_file} = sub ( $fr, $args, $kwargs ) {
    return $fr->play_background_file( $args->[0], kw_list($kwargs) );
};
$DISPATCH{wait_for_user} = sub ( $fr, $args, $kwargs ) {
    return $fr->wait_for_user( kw_list($kwargs) );
};
$DISPATCH{record_call} = sub ( $fr, $args, $kwargs ) {
    return $fr->record_call( kw_list($kwargs) );
};
$DISPATCH{stop_record_call} = sub ( $fr, $args, $kwargs ) {
    return $fr->stop_record_call( kw_list($kwargs) );
};
$DISPATCH{tap} = sub ( $fr, $args, $kwargs ) {
    return $fr->tap( $args->[0], kw_list($kwargs) );
};
$DISPATCH{stop_tap} = sub ( $fr, $args, $kwargs ) {
    return $fr->stop_tap( kw_list($kwargs) );
};
$DISPATCH{execute_swml} = sub ( $fr, $args, $kwargs ) {
    return $fr->execute_swml( $args->[0], kw_list($kwargs) );
};
$DISPATCH{join_conference} = sub ( $fr, $args, $kwargs ) {

    # name is positional; everything else keyword (Perl signature matches).
    return $fr->join_conference( $args->[0], kw_list($kwargs) );
};

# ---- connect: positional dest; final=>... ; Python from_addr -> Perl from ----
$DISPATCH{connect} = sub ( $fr, $args, $kwargs ) {
    my %opts = %{ $kwargs // {} };

    # Python's kwarg is `from_addr`; the Perl verb names it `from`.
    if ( exists $opts{from_addr} ) {
        $opts{from} = delete $opts{from_addr};
    }
    return $fr->connect( $args->[0], %opts );
};

# ---- swml_transfer: (dest, ai_response) positional; final=>... ---------------
$DISPATCH{swml_transfer} = sub ( $fr, $args, $kwargs ) {
    return $fr->swml_transfer( $args->[0], $args->[1], kw_list($kwargs) );
};

# ---- switch_context: 4 Python positionals -> Perl %opts named ----------------
# Python: switch_context(system_prompt, user_prompt, consolidate, full_reset).
$DISPATCH{switch_context} = sub ( $fr, $args, $kwargs ) {
    my @names = qw(system_prompt user_prompt consolidate full_reset);
    my %opts;
    for my $i ( 0 .. $#$args ) {
        my $v = $args->[$i];
        next unless defined $v;    # Python None -> omit (Perl default)
        $opts{ $names[$i] } = $v;
    }

    # Any keyword overrides (none in the corpus today, but be faithful).
    %opts = ( %opts, %{ $kwargs // {} } );
    return $fr->switch_context(%opts);
};

# ---- send_sms: Python (to_number, from_number) positional -> Perl named ------
$DISPATCH{send_sms} = sub ( $fr, $args, $kwargs ) {
    return $fr->send_sms(
        to_number   => $args->[0],
        from_number => $args->[1],
        kw_list($kwargs),
    );
};

# ---- pay: Python payment_connector_url positional -> Perl named --------------
$DISPATCH{pay} = sub ( $fr, $args, $kwargs ) {
    return $fr->pay(
        payment_connector_url => $args->[0],
        kw_list($kwargs),
    );
};

# ---- execute_rpc: Python method positional -> Perl named --------------------
$DISPATCH{execute_rpc} = sub ( $fr, $args, $kwargs ) {
    return $fr->execute_rpc(
        method => $args->[0],
        kw_list($kwargs),
    );
};

# ---- rpc_dial: Python (to_number, from_number, dest_swml) positional ---------
$DISPATCH{rpc_dial} = sub ( $fr, $args, $kwargs ) {
    return $fr->rpc_dial(
        to_number   => $args->[0],
        from_number => $args->[1],
        dest_swml   => $args->[2],
        kw_list($kwargs),
    );
};

# ---- rpc_ai_message: Python (call_id, message_text) positional ---------------
$DISPATCH{rpc_ai_message} = sub ( $fr, $args, $kwargs ) {
    return $fr->rpc_ai_message(
        call_id      => $args->[0],
        message_text => $args->[1],
        kw_list($kwargs),
    );
};

# ---- rpc_ai_unhold: Python (call_id) positional ------------------------------
$DISPATCH{rpc_ai_unhold} = sub ( $fr, $args, $kwargs ) {
    return $fr->rpc_ai_unhold( call_id => $args->[0], kw_list($kwargs) );
};

# --------------------------------------------------------------------------- #
# Build the emission for one corpus entry: construct FunctionResult with the
# entry's ctor args, apply the method (+ any chain), return its to_hash.
# --------------------------------------------------------------------------- #
sub apply_one ( $fr, $spec ) {
    my $method = $spec->{method};
    return $fr unless defined $method;    # envelope-only entry: ctor did the work
    my $code = $DISPATCH{$method}
        or die "emit-corpus: no dispatch for corpus method '$method' "
        . "(corpus id may reference a verb this port lacks)\n";
    return $code->( $fr, $spec->{args} // [], $spec->{kwargs} // {} );
}

sub build_emission ($entry) {
    my $ctor = $entry->{ctor} // {};
    my %args;

    # ctor: { response => "...", post_process => true }. JSON true/false decode
    # to JSON::PP::Boolean; set_post_process / the post_process attr read them
    # in boolean context.
    $args{response} = $ctor->{response} if exists $ctor->{response};
    my $fr = SignalWire::SWAIG::FunctionResult->new(%args);
    $fr->set_post_process( $ctor->{post_process} ? 1 : 0 ) if exists $ctor->{post_process};

    $fr = apply_one( $fr, $entry );
    for my $chained ( @{ $entry->{chain} // [] } ) {
        $fr = apply_one( $fr, $chained );
    }
    return $fr->to_hash;
}

# --------------------------------------------------------------------------- #
# main: emit one JSON object { id => emission }.
# --------------------------------------------------------------------------- #
sub main {
    my $corpus = load_corpus();

    my %out;
    my %seen;
    for my $entry (@$corpus) {
        my $id = $entry->{id};
        die "emit-corpus: duplicate corpus id '$id'\n" if $seen{$id}++;
        $out{$id} = build_emission($entry);
    }

    # Canonical so the bytes are stable; the empty hashref {} renders as the
    # JSON object {} (NOT []), which is the contract for clear_dynamic_hints.
    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
