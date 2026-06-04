package SignalWire::Relay::Call;
use strict;
use warnings;
use Moo;

use SignalWire::Relay::Action;
use SignalWire::Relay::Constants qw(CALL_TERMINAL_STATES ACTION_TERMINAL_STATES);

has 'call_id'    => ( is => 'ro', required => 1 );
has 'node_id'    => ( is => 'rw', default => sub { '' } );
has 'tag'        => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'rw', default => sub { 'created' } );
has 'device'     => ( is => 'rw', default => sub { {} } );
has 'end_reason' => ( is => 'rw', default => sub { '' } );
has 'peer'       => ( is => 'rw', default => sub { {} } );
has 'context'    => ( is => 'rw', default => sub { '' } );
has 'dial_winner' => ( is => 'rw', default => sub { 0 } );

has '_client'  => ( is => 'rw', default => sub { undef } );
has '_actions' => ( is => 'rw', default => sub { {} } );   # control_id => Action
has '_on_event' => ( is => 'rw', default => sub { [] } );  # event callbacks

# Helper to generate a UUID-like control_id
sub _generate_uuid {
    my @hex = map { sprintf('%02x', int(rand(256))) } 1..16;
    $hex[6] = sprintf('%02x', (hex($hex[6]) & 0x0f) | 0x40);
    $hex[8] = sprintf('%02x', (hex($hex[8]) & 0x3f) | 0x80);
    return join('-',
        join('', @hex[0..3]),
        join('', @hex[4..5]),
        join('', @hex[6..7]),
        join('', @hex[8..9]),
        join('', @hex[10..15]),
    );
}

sub _base_params {
    my ($self) = @_;
    return (
        node_id => $self->node_id,
        call_id => $self->call_id,
    );
}

sub _execute {
    my ($self, $method, %extra) = @_;
    my $client = $self->_client;
    die "No client attached to call" unless $client;
    my %params = ($self->_base_params, %extra);
    return $client->execute($method, \%params);
}

# Start an action-based method: creates the Action, registers it, executes the RPC
sub _start_action {
    my ($self, $method, $action_class, %extra) = @_;
    my $control_id = _generate_uuid();
    my %params = ($self->_base_params, control_id => $control_id, %extra);

    my $action = $action_class->new(
        control_id => $control_id,
        call_id    => $self->call_id,
        node_id    => $self->node_id,
        _client    => $self->_client,
    );
    $self->_actions->{$control_id} = $action;

    my $client = $self->_client;
    if ($client) {
        my $result = $client->execute($method, \%params);
        # If call is gone (404/410), resolve action immediately
        if (ref $result eq 'HASH' && $result->{code} && $result->{code} =~ /^(404|410)$/) {
            $action->_resolve(undef);
        }
    }

    return $action;
}

# --- Event dispatch ---

sub dispatch_event {
    my ($self, $event) = @_;
    my $event_type = $event->event_type // '';

    # Update call state from state events
    if ($event_type eq 'calling.call.state') {
        my $new_state = $event->call_state // '';
        $self->state($new_state);
        $self->end_reason($event->end_reason) if $event->can('end_reason') && $event->end_reason;
        $self->peer($event->peer) if $event->can('peer') && ref $event->peer eq 'HASH' && %{$event->peer};

        # If call ended, resolve all pending actions
        if (CALL_TERMINAL_STATES->{$new_state}) {
            $self->_resolve_all_actions;
        }
    }
    elsif ($event_type eq 'calling.call.connect') {
        $self->peer($event->peer) if $event->can('peer');
    }

    # Route to action by control_id
    my $control_id = $event->can('control_id') ? $event->control_id : '';
    if ($control_id && exists $self->_actions->{$control_id}) {
        my $action = $self->_actions->{$control_id};
        # The action decides whether to consume the event. play_and_collect's
        # CollectAction filters calling.call.play events out entirely so they
        # neither dispatch nor terminally resolve.
        my $consumed = 1;
        if ($action->can('_should_consume_event')) {
            $consumed = $action->_should_consume_event($event);
        }
        if ($consumed) {
            $action->_handle_event($event);

            # Check if action reached terminal state — but only for events
            # the action consumed, AND only if the action hasn't already
            # decided to resolve itself in _handle_event (e.g. Detect on
            # first detect payload).
            unless ($action->completed) {
                my $terminal = ACTION_TERMINAL_STATES->{$event_type} // {};
                my $action_state = $event->can('state') ? ($event->state // '') : '';
                if ($terminal->{$action_state}) {
                    $action->_resolve($event);
                }
            }
            if ($action->completed) {
                delete $self->_actions->{$control_id};
            }
        }
    }

    # Fire registered event callbacks
    for my $cb (@{$self->_on_event}) {
        eval { $cb->($self, $event) };
        warn "Call event callback error: $@" if $@;
    }
}

# Register an event listener
sub on {
    my ($self, $cb) = @_;
    push @{$self->_on_event}, $cb;
    return $self;
}

# Resolve all pending actions (e.g., on call ended or call-gone)
sub _resolve_all_actions {
    my ($self) = @_;
    for my $action (values %{$self->_actions}) {
        $action->_resolve(undef) unless $action->completed;
    }
    $self->_actions({});
}

# --- Simple fire-and-response methods ---

sub answer {
    my ($self, %opts) = @_;
    return $self->_execute('calling.answer', %opts);
}

sub hangup {
    my ($self, %opts) = @_;
    return $self->_execute('calling.end', %opts);
}

sub pass {
    my ($self) = @_;
    return $self->_execute('calling.pass');
}

sub connect {
    my ($self, %opts) = @_;
    return $self->_execute('calling.connect', %opts);
}

sub disconnect {
    my ($self) = @_;
    return $self->_execute('calling.disconnect');
}

sub hold {
    my ($self) = @_;
    return $self->_execute('calling.hold');
}

sub unhold {
    my ($self) = @_;
    return $self->_execute('calling.unhold');
}

sub denoise {
    my ($self) = @_;
    return $self->_execute('calling.denoise');
}

sub denoise_stop {
    my ($self) = @_;
    return $self->_execute('calling.denoise.stop');
}

sub transfer {
    my ($self, %opts) = @_;
    return $self->_execute('calling.transfer', %opts);
}

sub join_conference {
    my ($self, %opts) = @_;
    return $self->_execute('calling.join_conference', %opts);
}

sub leave_conference {
    my ($self, %opts) = @_;
    return $self->_execute('calling.leave_conference', %opts);
}

sub echo {
    my ($self, %opts) = @_;
    return $self->_execute('calling.echo', %opts);
}

sub bind_digit {
    my ($self, %opts) = @_;
    return $self->_execute('calling.bind_digit', %opts);
}

sub clear_digit_bindings {
    my ($self, %opts) = @_;
    return $self->_execute('calling.clear_digit_bindings', %opts);
}

sub live_transcribe {
    my ($self, %opts) = @_;
    return $self->_execute('calling.live_transcribe', %opts);
}

sub live_translate {
    my ($self, %opts) = @_;
    return $self->_execute('calling.live_translate', %opts);
}

sub join_room {
    my ($self, %opts) = @_;
    return $self->_execute('calling.join_room', %opts);
}

sub leave_room {
    my ($self, %opts) = @_;
    # Python parity: Call.leave_room(**kwargs). Forwards any caller-provided
    # kwargs to the Relay leave_room dispatch (slurpy hash on the Perl side
    # ≡ **kwargs on the Python side).
    return $self->_execute('calling.leave_room', %opts);
}

sub amazon_bedrock {
    my ($self, %opts) = @_;
    return $self->_execute('calling.amazon_bedrock', %opts);
}

sub ai_message {
    my ($self, %opts) = @_;
    return $self->_execute('calling.ai_message', %opts);
}

sub ai_hold {
    my ($self, %opts) = @_;
    return $self->_execute('calling.ai_hold', %opts);
}

sub ai_unhold {
    my ($self, %opts) = @_;
    return $self->_execute('calling.ai_unhold', %opts);
}

sub user_event {
    my ($self, %opts) = @_;
    return $self->_execute('calling.user_event', %opts);
}

sub queue_enter {
    my ($self, %opts) = @_;
    return $self->_execute('calling.queue.enter', %opts);
}

sub queue_leave {
    my ($self, %opts) = @_;
    return $self->_execute('calling.queue.leave', %opts);
}

sub refer {
    my ($self, %opts) = @_;
    return $self->_execute('calling.refer', %opts);
}

sub send_digits {
    my ($self, %opts) = @_;
    return $self->_execute('calling.send_digits', %opts);
}

# --- Action-based methods (control_id tracking) ---

sub play {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.play', 'SignalWire::Relay::Action::Play', %opts);
}

# --- Play convenience: typed wrappers over play() ---
#
# These restore the legacy call->play_tts(text => ...) ergonomics so
# callers don't hand-build the { type => "...", params => {...} } media
# shape. Each delegates to play() with the exact RELAY media object
# (see RELAY_IMPLEMENTATION_GUIDE.md "Media Objects"). Optional params
# are only included when the caller supplies them, so the wire shape
# carries no undef keys.

sub play_tts {
    my ($self, $text, %opts) = @_;
    my %tts = ( text => $text );
    $tts{language} = $opts{language} if defined $opts{language};
    $tts{gender}   = $opts{gender}   if defined $opts{gender};
    $tts{voice}    = $opts{voice}    if defined $opts{voice};
    my @play = ( play => [ { type => 'tts', params => \%tts } ] );
    push @play, ( volume => $opts{volume} ) if defined $opts{volume};
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub play_audio {
    my ($self, $url, %opts) = @_;
    my @play = ( play => [ { type => 'audio', params => { url => $url } } ] );
    push @play, ( volume => $opts{volume} ) if defined $opts{volume};
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub play_silence {
    my ($self, $duration, %opts) = @_;
    my @play = ( play => [ { type => 'silence', params => { duration => $duration } } ] );
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub play_ringtone {
    my ($self, $name, %opts) = @_;
    my %rt = ( name => $name );
    $rt{duration} = $opts{duration} if defined $opts{duration};
    my @play = ( play => [ { type => 'ringtone', params => \%rt } ] );
    push @play, ( volume => $opts{volume} ) if defined $opts{volume};
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub record {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.record', 'SignalWire::Relay::Action::Record', %opts);
}

sub detect {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.detect', 'SignalWire::Relay::Action::Detect', %opts);
}

# --- Detect convenience: typed wrappers over detect() ---
#
# Build the RELAY detect object { type => "...", params => {...} } and
# forward to detect(). The optional timeout is a sibling of `detect` in
# the calling.detect params, not inside the detect object — same as
# Python's Call.detect_*.

sub detect_digit {
    my ($self, %opts) = @_;
    my %params;
    $params{digits} = $opts{digits} if defined $opts{digits};
    my @args = ( detect => { type => 'digit', params => \%params } );
    push @args, ( timeout => $opts{timeout} ) if defined $opts{timeout};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->detect(@args);
}

sub detect_answering_machine {
    my ($self, %opts) = @_;
    my %params;
    # Only the AMD knobs the caller actually provided land in params; the
    # server fills the rest from its defaults.
    for my $key (qw(
        initial_timeout end_silence_timeout machine_voice_threshold
        machine_words_threshold detect_interruptions detect_message_end
    )) {
        $params{$key} = $opts{$key} if defined $opts{$key};
    }
    my @args = ( detect => { type => 'machine', params => \%params } );
    push @args, ( timeout => $opts{timeout} ) if defined $opts{timeout};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->detect(@args);
}

sub detect_fax {
    my ($self, %opts) = @_;
    my %params;
    $params{tone} = $opts{tone} if defined $opts{tone};
    my @args = ( detect => { type => 'fax', params => \%params } );
    push @args, ( timeout => $opts{timeout} ) if defined $opts{timeout};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->detect(@args);
}

sub collect {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.collect', 'SignalWire::Relay::Action::StandaloneCollect', %opts);
}

sub play_and_collect {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.play_and_collect', 'SignalWire::Relay::Action::Collect', %opts);
}

# --- Prompt convenience: typed media over play_and_collect() ---
#
# Play a TTS / audio prompt and collect input in one call. The `collect`
# hashref is passed through verbatim (see RELAY guide "Collect Object");
# only the play media is built from the typed args.

sub prompt_tts {
    my ($self, $text, $collect, %opts) = @_;
    my %tts = ( text => $text );
    $tts{language} = $opts{language} if defined $opts{language};
    $tts{gender}   = $opts{gender}   if defined $opts{gender};
    $tts{voice}    = $opts{voice}    if defined $opts{voice};
    my @args = (
        play    => [ { type => 'tts', params => \%tts } ],
        collect => $collect,
    );
    push @args, ( volume => $opts{volume} ) if defined $opts{volume};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play_and_collect(@args);
}

sub prompt_audio {
    my ($self, $url, $collect, %opts) = @_;
    my @args = (
        play    => [ { type => 'audio', params => { url => $url } } ],
        collect => $collect,
    );
    push @args, ( volume => $opts{volume} ) if defined $opts{volume};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play_and_collect(@args);
}

sub send_fax {
    my ($self, %opts) = @_;
    my $action = $self->_start_action('calling.send_fax', 'SignalWire::Relay::Action::Fax', %opts);
    return $action;
}

sub receive_fax {
    my ($self, %opts) = @_;
    my $control_id = _generate_uuid();
    my %params = ($self->_base_params, control_id => $control_id, %opts);

    my $action = SignalWire::Relay::Action::Fax->new(
        control_id => $control_id,
        call_id    => $self->call_id,
        node_id    => $self->node_id,
        _client    => $self->_client,
        _fax_type  => 'receive',
    );
    $self->_actions->{$control_id} = $action;

    my $client = $self->_client;
    if ($client) {
        my $result = $client->execute('calling.receive_fax', \%params);
        if (ref $result eq 'HASH' && $result->{code} && $result->{code} =~ /^(404|410)$/) {
            $action->_resolve(undef);
        }
    }

    return $action;
}

sub tap {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.tap', 'SignalWire::Relay::Action::Tap', %opts);
}

sub stream {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.stream', 'SignalWire::Relay::Action::Stream', %opts);
}

sub pay {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.pay', 'SignalWire::Relay::Action::Pay', %opts);
}

sub transcribe {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.transcribe', 'SignalWire::Relay::Action::Transcribe', %opts);
}

sub ai {
    my ($self, %opts) = @_;
    return $self->_start_action('calling.ai', 'SignalWire::Relay::Action::AI', %opts);
}

1;
