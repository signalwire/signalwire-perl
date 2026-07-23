#!/usr/bin/env perl
# ai-chat-dump.pl — the Perl port's AI-CHAT dump program for the cross-port
# wire-behavioral gate (porting-sdk/scripts/diff_port_ai_chat.py, on the
# `ai-chat-client` branch — a COORDINATED pass).
#
# The gate boots the in-process mock_ai_chat server, exports MOCK_AI_CHAT_URL +
# SIGNALWIRE_PROJECT_ID / SIGNALWIRE_API_TOKEN into this program's env, runs it,
# and asserts the JSON it prints (+ the wire requests the mock recorded) speak the
# AI Chat protocol per the vendored spec (ai-chat-specs/ai-chat.yaml).
#
# This mirrors porting-sdk/scripts/ai_chat_dump_reference.py EXACTLY: it drives
# the Perl SignalWire::AIChat::Client through the shared ai_chat_corpus and emits
# ONE JSON object to stdout (nothing else), keyed by corpus step:
#
#   success steps (create/chat/end/delete/log/summarize):
#       { wire_method, decoded: { <spec result fields> } }
#   summarize_failed (the summarize {error} one_of branch — must SURFACE, not swallow):
#       { wire_method:"summarize", raised:true, error_type, message }
#   error steps (err_notfound/err_ratelimit/err_inprogress/err_auth/err_unmapped):
#       { raised:true, error_code, error_type }
#
# The corpus (steps + SUMMARIZE_ERROR_ID + ERROR_STEPS + force_error_id) is data,
# identical for every language; it is mirrored inline here from ai_chat_corpus.py.
#
# Run from the signalwire-perl repo root against a running mock:
#
#   MOCK_AI_CHAT_URL=http://127.0.0.1:PORT/api/ai/chat perl scripts/ai-chat-dump.pl
#
# Nothing but the JSON object is written to stdout on success.

use strict;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/../lib";

use JSON qw(encode_json);
use SignalWire::AIChat::Client;

# ── the shared corpus (mirror of porting-sdk/scripts/ai_chat_corpus.py) ──────

# The sentinel conversation id that makes summarize return its {error} branch.
my $SUMMARIZE_ERROR_ID = '__summarize_error';

# error step id -> the JSON-RPC code the port's raised error MUST carry, in the
# corpus order (create/chat/... come first; these are the error steps).
my @ERROR_STEPS = (
    [ 'err_notfound',   -32001 ],    # ConversationNotFound
    [ 'err_ratelimit',  -32005 ],    # RateLimit
    [ 'err_inprogress', -32007 ],    # ChatInProgress
    [ 'err_auth',       -32009 ],    # Authentication
    [ 'err_unmapped',   -32602 ],    # base AIChatError (unmapped code)
);

# The sentinel conversation id that makes the mock return <code>.
sub force_error_id {
    my ($code) = @_;
    return "__err_$code";
}

# The class-name tail (e.g. "SummaryError") for a blessed error, matching the
# reference dump's type(e).__name__.
sub error_type_name {
    my ($err) = @_;
    my $class = ref $err;
    return $class unless $class;
    $class =~ s/.*:://;
    return $class;
}

sub run {
    my ($url) = @_;
    my %out;

    my $client = SignalWire::AIChat::Client->new(
        url => $url,

        # deterministic gate run: byte-silence bound irrelevant against the
        # in-process mock, but keep the real default behavior.
    );

    # ── success steps ────────────────────────────────────────────────
    my $info = $client->create_conversation(
        'conv-1',
        config_url => 'http://cfg',
        timeout    => 30,
        reinit     => 1,
    );
    $out{create} = {
        wire_method => 'create_conversation',
        decoded     => {
            status          => $info->status,
            id              => $info->id,
            initial_message => $info->initial_message,
        },
    };

    my $reply = $client->chat( 'conv-1', 'hello', timeout => 30, reinit => 1 );
    $out{chat} = {
        wire_method => 'chat',
        decoded     => { response => $reply->text, user_event => $reply->user_event },
    };

    # end/delete return bool idiomatically; the wire result also carries the
    # conversation id (the caller's own input, echoed). Report both the derived
    # status and the id operated on — mirroring the reference dump.
    my $ended = $client->end('conv-1');
    $out{end} = {
        wire_method => 'end_conversation',
        decoded     => { status => ( $ended ? 'ended' : '?' ), id => 'conv-1' },
    };

    my $deleted = $client->delete('conv-1');
    $out{delete} = {
        wire_method => 'delete',
        decoded     => { status => ( $deleted ? 'deleted' : '?' ), id => 'conv-1' },
    };

    my $log = $client->log('conv-1');
    $out{log} = {
        wire_method => 'chat_log',
        decoded     => { chat_log => $log->messages, call_timeline => $log->call_timeline },
    };

    my $summary = $client->summarize('conv-1');
    $out{summarize} = { wire_method => 'summarize', decoded => { summary => $summary } };

    # ── summarize one_of {error} branch: must SURFACE, not swallow ───────
    my $swallowed = eval { $client->summarize($SUMMARIZE_ERROR_ID) };
    if ( my $err = $@ ) {
        die $err
            unless ref $err && $err->isa('SignalWire::AIChat::Error');
        $out{summarize_failed} = {
            wire_method => 'summarize',
            raised      => JSON::true(),
            error_type  => error_type_name($err),
            message     => $err->message,
        };
    } else {
        $out{summarize_failed} = {
            wire_method => 'summarize',
            raised      => JSON::false(),
            decoded     => { summary => $swallowed },
        };
    }

    # ── error-code steps (JSON-RPC error object) ─────────────────────────
    for my $entry (@ERROR_STEPS) {
        my ( $step, $code ) = @$entry;
        my $ok = eval { $client->chat( force_error_id($code), 'x' ); 1 };
        if ($ok) {
            $out{$step} = { raised => JSON::false() };
        } else {
            my $err = $@;
            die $err unless ref $err && $err->isa('SignalWire::AIChat::Error');
            # Coerce to numeric so JSON emits a bare number, not a quoted string:
            # a hash-key lookup on the code (in the client's error mapping) leaves
            # it flagged as a string (PV), which encode_json would serialize as
            # "-32001". The gate compares the code by value, and the mock sends an
            # int, so re-number it here.
            my $code_n = defined $err->code ? ( $err->code + 0 ) : undef;
            $out{$step} = {
                raised     => JSON::true(),
                error_code => $code_n,
                error_type => error_type_name($err),
            };
        }
    }

    return \%out;
}

sub main {
    my $url = $ENV{MOCK_AI_CHAT_URL};
    if ( !defined $url || !length $url ) {
        print {*STDERR} "MOCK_AI_CHAT_URL not set\n";
        return 2;
    }
    my $out = run($url);

    # JSON-only stdout: canonical, no trailing newline noise beyond the one \n.
    print encode_json($out), "\n";
    return 0;
}

exit main();
