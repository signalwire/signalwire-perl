#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;

# t/68_idiom_pass.t — Tier-2 idiom pass guards.
#
# This file pins the three internal-quality idioms adopted across the
# public surface so a later refactor can't silently regress them:
#
#   1. Moo `isa` constraints actually REJECT bad construction (we assert
#      the die, with the real die message), and the SAME constructor with
#      a good value succeeds. No mocks — real Moo objects, real failures.
#
#   2. Subroutine signatures didn't break call sites — we drive real
#      methods (whose `my (...) = @_` was replaced by a signature) through
#      their public API and assert on the produced wire shape / behavior.
#
#   3. POD is valid — every module we documented passes Pod::Checker with
#      zero errors (the same check `podchecker` performs).
#
# All three are behavioral: each assertion exercises real code, not a
# stand-in.

use_ok('SignalWire::Relay::Message');
use_ok('SignalWire::Relay::Call');
use_ok('SignalWire::Relay::Action');
use_ok('SignalWire::Relay::Client');
use_ok('SignalWire::Skills::SkillBase');
use_ok('SignalWire::POM::Section');
use_ok('SignalWire::SWAIG::FunctionResult');
use_ok('SignalWire::Agent::AgentBase');

# ------------------------------------------------------------------
# 1. Moo `isa` constraints reject bad construction (assert the die).
# ------------------------------------------------------------------

subtest 'isa: Relay::Message rejects bad values' => sub {
    # message_id: required non-empty string.
    throws_ok { SignalWire::Relay::Message->new(message_id => '') }
        qr/non-empty string/, 'empty message_id dies';
    throws_ok { SignalWire::Relay::Message->new(message_id => {}) }
        qr/non-empty string/, 'hashref message_id dies';

    # media / tags: arrayref.
    throws_ok { SignalWire::Relay::Message->new(message_id => 'm1', media => 'oops') }
        qr/arrayref/, 'string media dies';
    throws_ok { SignalWire::Relay::Message->new(message_id => 'm1', tags => {}) }
        qr/arrayref/, 'hashref tags dies';

    # segments: number.
    throws_ok { SignalWire::Relay::Message->new(message_id => 'm1', segments => 'three') }
        qr/number/, 'non-numeric segments dies';

    # Good construction with the SAME constructor path succeeds and the
    # values round-trip.
    my $msg = SignalWire::Relay::Message->new(
        message_id => 'msg-1',
        media      => ['https://x/y.jpg'],
        tags       => ['vip'],
        segments   => 2,
    );
    isa_ok($msg, 'SignalWire::Relay::Message');
    is($msg->message_id, 'msg-1', 'good message_id stored');
    is_deeply($msg->media, ['https://x/y.jpg'], 'good media stored');
    is($msg->segments, 2, 'good segments stored');

    # rw accessor write is also policed (Moo checks isa on set).
    throws_ok { $msg->media('nope') } qr/arrayref/, 'bad media write dies';
    # ...and a good write still works.
    lives_ok { $msg->media(['a', 'b']) } 'good media write lives';
    is_deeply($msg->media, ['a', 'b'], 'media write took effect');
};

subtest 'isa: Relay::Call requires non-empty call_id' => sub {
    throws_ok { SignalWire::Relay::Call->new(call_id => '') }
        qr/non-empty string/, 'empty call_id dies';
    throws_ok { SignalWire::Relay::Call->new(call_id => []) }
        qr/non-empty string/, 'arrayref call_id dies';
    throws_ok { SignalWire::Relay::Call->new(call_id => 'c1', device => 'x') }
        qr/hashref/, 'string device dies';

    my $call = SignalWire::Relay::Call->new(call_id => 'call-1');
    isa_ok($call, 'SignalWire::Relay::Call');
    is($call->call_id, 'call-1', 'good call_id stored');
};

subtest 'isa: Relay::Action requires non-empty control_id' => sub {
    throws_ok { SignalWire::Relay::Action->new(control_id => '') }
        qr/non-empty string/, 'empty control_id dies';
    throws_ok { SignalWire::Relay::Action->new(control_id => 'a1', payload => []) }
        qr/hashref/, 'arrayref payload dies';

    my $action = SignalWire::Relay::Action->new(control_id => 'ctl-1');
    isa_ok($action, 'SignalWire::Relay::Action');
    is($action->control_id, 'ctl-1', 'good control_id stored');
};

subtest 'isa: Relay::Client requires non-empty host' => sub {
    throws_ok { SignalWire::Relay::Client->new(host => '') }
        qr/host must be a non-empty string/, 'empty host dies';
    throws_ok { SignalWire::Relay::Client->new(host => {}) }
        qr/host must be a non-empty string/, 'hashref host dies';
    throws_ok { SignalWire::Relay::Client->new(host => 'h', contexts => 'office') }
        qr/contexts must be an arrayref/, 'string contexts dies';

    my $client = SignalWire::Relay::Client->new(host => 'relay.example.com');
    isa_ok($client, 'SignalWire::Relay::Client');
    is($client->host, 'relay.example.com', 'good host stored');
};

subtest 'isa: SkillBase rejects bad metadata and non-object agent' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'isa_skill_test');

    # A minimal concrete subclass so we can construct (SkillBase's setup /
    # register_tools are abstract). This is real Moo, not a mock.
    {
        package T::IsaSkill;
        use Moo;
        extends 'SignalWire::Skills::SkillBase';
        has '+skill_name'        => (default => sub { 'isa_demo' });
        has '+skill_description' => (default => sub { 'isa demo skill' });
        sub setup          { 1 }
        sub register_tools { 1 }
    }

    # agent must be a blessed object.
    throws_ok { T::IsaSkill->new(agent => 'not-an-object') }
        qr/must be an object/, 'string agent dies';

    # params / swaig_fields must be hashrefs.
    throws_ok { T::IsaSkill->new(agent => $agent, params => []) }
        qr/hashref/, 'arrayref params dies';

    # skill_name override to empty (via a second subclass) must die: an
    # empty-string name is not a valid skill name.
    throws_ok {
        package T::EmptyNameSkill;
        use Moo;
        extends 'SignalWire::Skills::SkillBase';
        has '+skill_name'        => (default => sub { '' });
        has '+skill_description' => (default => sub { 'x' });
        sub setup          { 1 }
        sub register_tools { 1 }
        T::EmptyNameSkill->new(agent => $agent);
    } qr/non-empty string/, 'empty skill_name dies';

    # Good construction with a real agent succeeds.
    my $skill = T::IsaSkill->new(agent => $agent, params => { tool_name => 'demo' });
    isa_ok($skill, 'SignalWire::Skills::SkillBase');
    is($skill->skill_name, 'isa_demo', 'good skill_name stored');
    is($skill->get_instance_key, 'isa_demo:demo', 'instance key honours tool_name');
};

subtest 'isa: POM::Section rejects non-arrayref subsections' => sub {
    throws_ok { SignalWire::POM::Section->new(subsections => 'oops') }
        qr/subsections must be an arrayref/, 'string subsections dies';
    my $sec = SignalWire::POM::Section->new(title => 'T', subsections => []);
    isa_ok($sec, 'SignalWire::POM::Section');
};

# ------------------------------------------------------------------
# 2. Signatures didn't break call sites — drive real signature-form
#    methods and assert on produced behavior / wire shape.
# ------------------------------------------------------------------

subtest 'signatures: FunctionResult methods still behave' => sub {
    # connect() — signature ($self, $destination, %opts). The %opts slurpy
    # carries the kwargs; assert the produced SWML wire shape.
    my $fr = SignalWire::SWAIG::FunctionResult->new;
    my $ret = $fr->connect('+15551234567', final => 0);
    is($ret, $fr, 'connect returns $self (chainable)');
    my $hash = $fr->to_hash;
    is($hash->{action}[0]{SWML}{sections}{main}[0]{connect}{to},
       '+15551234567', 'connect destination on the wire');
    is($hash->{action}[0]{transfer}, 'false', 'final=0 -> transfer false');

    # hold() — signature ($self, $timeout = undef). Default + clamping.
    my $h = SignalWire::SWAIG::FunctionResult->new;
    $h->hold;            # default 300
    is($h->to_hash->{action}[0]{hold}, 300, 'hold default 300');
    my $h2 = SignalWire::SWAIG::FunctionResult->new;
    $h2->hold(5000);     # clamps to 900
    is($h2->to_hash->{action}[0]{hold}, 900, 'hold clamps to 900');

    # record_call() — signature ($self, %opts) with closed-set validation
    # still firing from inside the signature-form body.
    my $rc = SignalWire::SWAIG::FunctionResult->new;
    throws_ok { $rc->record_call(format => 'flac') }
        qr/format must be/, 'record_call still validates format';
    my $rc2 = SignalWire::SWAIG::FunctionResult->new;
    $rc2->record_call(format => 'mp3', direction => 'both');
    my $rcp = $rc2->to_hash->{action}[0]{SWML}{sections}{main}[0]{record_call};
    is($rcp->{format}, 'mp3', 'record_call format on the wire');

    # A leading-positional + %opts wrapper-style method: create_payment_action
    # (class-or-instance, signature ($class_or_self, $action_type, $phrase)).
    my $act = SignalWire::SWAIG::FunctionResult->create_payment_action('say', 'hi');
    is_deeply($act, { type => 'say', phrase => 'hi' },
        'create_payment_action builds the right hashref');
};

subtest 'signatures: Relay::Call verbs route through _execute' => sub {
    # A tiny stand-in client (NOT a mock of transport — a real object that
    # records the (method, params) a Call verb dispatches, so we can assert
    # the signature-form verb forwarded correctly).
    {
        package T::RecordingClient;
        use Moo;
        has calls => (is => 'rw', default => sub { [] });
        sub execute {
            my ($self, $method, $params) = @_;
            push @{ $self->calls }, [ $method, $params ];
            return { code => '200' };
        }
    }
    my $client = T::RecordingClient->new;
    my $call = SignalWire::Relay::Call->new(
        call_id => 'call-xyz',
        node_id => 'node-1',
        _client => $client,
    );

    # answer() — signature ($self, %opts).
    $call->answer;
    is($client->calls->[0][0], 'calling.answer', 'answer -> calling.answer');
    is($client->calls->[0][1]{call_id}, 'call-xyz', 'answer carries call_id');

    # play_tts() — signature ($self, $text, %opts) leading positional +
    # slurpy; assert the media object it builds.
    $call->play_tts('Hello there', voice => 'en-US-Neural2-A');
    my ($method, $params) = @{ $client->calls->[-1] };
    is($method, 'calling.play', 'play_tts -> calling.play');
    is($params->{play}[0]{type}, 'tts', 'play_tts media type is tts');
    is($params->{play}[0]{params}{text}, 'Hello there', 'play_tts text on the wire');
    is($params->{play}[0]{params}{voice}, 'en-US-Neural2-A', 'play_tts voice on the wire');

    # on() — signature ($self, $cb); the coderef guard added alongside the
    # signature must reject a non-coderef but accept a coderef.
    throws_ok { $call->on('not-a-sub') } qr/coderef/, 'Call->on rejects non-coderef';
    my $fired = 0;
    lives_ok { $call->on(sub { $fired++ }) } 'Call->on accepts a coderef';
};

subtest 'signatures: Relay::Message callbacks + wait shape' => sub {
    my $msg = SignalWire::Relay::Message->new(message_id => 'm-sig');
    # on_completed() — signature ($self, $cb = undef): no-arg getter form,
    # register form, and coderef guard.
    is($msg->on_completed, undef, 'on_completed getter is undef initially');
    throws_ok { $msg->on_completed('x') } qr/coderef/, 'on_completed rejects non-coderef';
    my $seen;
    $msg->on_completed(sub { $seen = $_[0]->message_id });
    ok($msg->on_completed, 'on_completed registered a coderef');

    # Drive a terminal messaging.state event through dispatch_event (real
    # signature-form method) and confirm the callback fired with $self.
    my $event = SignalWire::Relay::Event->parse_event(
        'messaging.state',
        { message_id => 'm-sig', message_state => 'delivered' },
    );
    $msg->dispatch_event($event);
    ok($msg->is_done, 'message completed after terminal state');
    is($seen, 'm-sig', 'on_completed fired with the message');
};

# ------------------------------------------------------------------
# 3. POD is valid (Pod::Checker — same engine as podchecker(1)).
# ------------------------------------------------------------------

subtest 'POD: documented modules are Pod::Checker-clean' => sub {
    eval { require Pod::Checker; 1 }
        or plan skip_all => 'Pod::Checker not available';

    require File::Spec;
    # Derive lib/ from this test file's own path (t/68_idiom_pass.t ->
    # ../lib) without FindBin, so there's no used-once package-var warning.
    my (undef, $test_dir, undef) = File::Spec->splitpath(File::Spec->rel2abs(__FILE__));
    my $lib = File::Spec->catdir($test_dir, File::Spec->updir, 'lib');

    my @modules = qw(
        SignalWire/SWAIG/ParameterSchema.pm
        SignalWire/SWAIG/RecordCall.pm
        SignalWire/SWAIG/Tap.pm
        SignalWire/SWAIG/JoinConference.pm
        SignalWire/SWAIG/FunctionResult.pm
        SignalWire/Skills/SkillName.pm
        SignalWire/Logging/LogLevel.pm
        SignalWire/Skills/SkillBase.pm
        SignalWire/Relay/Message.pm
        SignalWire/Relay/Event.pm
        SignalWire/Relay/Action.pm
        SignalWire/Relay/Call.pm
        SignalWire/Relay/Client.pm
        SignalWire/Relay/CallState.pm
        SignalWire/Relay/DialState.pm
        SignalWire/Relay/MessageState.pm
        SignalWire/Relay/Device.pm
        SignalWire/POM/Section.pm
    );

    for my $rel (@modules) {
        my $path = File::Spec->catfile($lib, split m{/}, $rel);
        ok(-f $path, "module exists: $rel");

        # Pod::Checker writes diagnostics to the output filehandle; capture
        # them and assert zero errors. num_errors() is the authoritative
        # count (same as podchecker's exit status).
        my $errs = '';
        open my $out_fh, '>', \$errs or die "cannot open string fh: $!";
        my $checker = Pod::Checker->new();
        $checker->parse_from_file($path, $out_fh);
        close $out_fh;
        is($checker->num_errors, 0, "POD clean: $rel")
            or diag("Pod::Checker output for $rel:\n$errs");
    }
};

done_testing();
