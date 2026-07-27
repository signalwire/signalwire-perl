package SignalWire::SWAIG::FunctionResult;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use JSON ();

has 'response' => (
    is      => 'rw',
    default => sub { '' },
);

has 'action' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { [] },
);

has 'post_process' => (
    is      => 'rw',
    default => sub { 0 },
);

# Mirror Python's `if value:` truthiness for the values that reach the wire as
# optional keys. The cross-port emission contract is byte-equality with
# Python's to_dict(), and Python treats an EMPTY dict/list as falsy (so an
# empty `params={}` is omitted) while Perl treats any ref as truthy. This
# helper bridges that gap: an empty hashref/arrayref is falsy, a non-empty one
# is truthy, and a plain scalar uses Perl's own truthiness (matching Python's
# str/number rules closely enough for the wire values in play).
sub _py_truthy {
    my ($v) = @_;
    return 0 unless defined $v;
    if ( ref $v eq 'HASH' ) {
        return scalar( keys %$v ) ? 1 : 0;
    }
    if ( ref $v eq 'ARRAY' ) {
        return scalar(@$v) ? 1 : 0;
    }
    return $v ? 1 : 0;
}

# Constructor: new(response => "text") or new("text") or new("text", post_process => 1)
around BUILDARGS => sub {
    my ( $orig, $class, @args ) = @_;
    if ( @args == 1 && !ref $args[0] ) {
        return $class->$orig( response => $args[0] );
    }
    if ( @args >= 1 && !ref $args[0] && $args[0] !~ /^(response|action|post_process)$/ ) {
        my $resp = shift @args;
        return $class->$orig( response => $resp, @args );
    }
    return $class->$orig(@args);
};

# --- Core methods ---

sub set_response ( $self, $response ) {
    $self->response($response);
    return $self;
}

sub set_post_process ( $self, $post_process ) {
    $self->post_process( $post_process ? 1 : 0 );
    return $self;
}

sub add_action ( $self, $name, $data ) {
    push @{ $self->action }, { $name => $data };
    return $self;
}

sub add_actions ( $self, $actions ) {
    push @{ $self->action }, @$actions;
    return $self;
}

# --- Call Control ---

sub connect ( $self, $destination, %opts ) {
    my $final = exists $opts{final} ? $opts{final} : 1;
    my $from  = $opts{from};

    my $connect_params = { to => $destination };
    $connect_params->{from} = $from if defined $from;

    my $swml_action = {
        SWML => {
            sections => {
                main => [ { connect => $connect_params } ],
            },
            version => '1.0.0',
        },
        transfer => $final ? 'true' : 'false',
    };

    push @{ $self->action }, $swml_action;
    return $self;
}

sub swml_transfer ( $self, $dest, $ai_response, %opts ) {
    my $final = exists $opts{final} ? $opts{final} : 1;

    my $swml_action = {
        SWML => {
            version  => '1.0.0',
            sections => {
                main => [
                    { set      => { ai_response => $ai_response } },
                    { transfer => { dest        => $dest } },
                ],
            },
        },
        transfer => $final ? 'true' : 'false',
    };

    push @{ $self->action }, $swml_action;
    return $self;
}

sub hangup ($self) {
    return $self->add_action( 'hangup', JSON::true );
}

sub hold ( $self, $timeout = undef ) {
    $timeout //= 300;
    $timeout = 0   if $timeout < 0;
    $timeout = 900 if $timeout > 900;
    return $self->add_action( 'hold', $timeout );
}

sub wait_for_user ( $self, %opts ) {
    my $enabled      = $opts{enabled};
    my $timeout      = $opts{timeout};
    my $answer_first = $opts{answer_first};

    my $value;
    if ($answer_first) {
        $value = 'answer_first';
    } elsif ( defined $timeout ) {
        $value = $timeout;
    } elsif ( defined $enabled ) {
        $value = $enabled ? JSON::true : JSON::false;
    } else {
        $value = JSON::true;
    }
    return $self->add_action( 'wait_for_user', $value );
}

sub stop ($self) {
    return $self->add_action( 'stop', JSON::true );
}

# --- State & Data ---

sub update_global_data ( $self, $data ) {
    return $self->add_action( 'set_global_data', $data );
}

sub remove_global_data ( $self, $keys ) {
    return $self->add_action( 'unset_global_data', $keys );
}

sub set_metadata ( $self, $data ) {
    return $self->add_action( 'set_meta_data', $data );
}

sub remove_metadata ( $self, $keys ) {
    return $self->add_action( 'unset_meta_data', $keys );
}

sub swml_user_event ( $self, $event_data ) {
    my $swml_action = {
        sections => {
            main => [
                {
                    user_event => { event => $event_data },
                }
            ],
        },
        version => '1.0.0',
    };
    return $self->add_action( 'SWML', $swml_action );
}

sub swml_change_step ( $self, $step_name ) {
    return $self->add_action( 'change_step', $step_name );
}

sub swml_change_context ( $self, $context_name ) {
    return $self->add_action( 'change_context', $context_name );
}

sub switch_context ( $self, %opts ) {
    my $system_prompt = $opts{system_prompt};
    my $user_prompt   = $opts{user_prompt};
    my $consolidate   = $opts{consolidate};
    my $full_reset    = $opts{full_reset};

    if ( $system_prompt && !$user_prompt && !$consolidate && !$full_reset ) {
        return $self->add_action( 'context_switch', $system_prompt );
    }

    my %ctx;
    $ctx{system_prompt} = $system_prompt if $system_prompt;
    $ctx{user_prompt}   = $user_prompt   if $user_prompt;
    $ctx{consolidate}   = JSON::true     if $consolidate;
    $ctx{full_reset}    = JSON::true     if $full_reset;
    return $self->add_action( 'context_switch', \%ctx );
}

sub replace_in_history ( $self, $text = undef ) {
    $text //= JSON::true;
    return $self->add_action( 'replace_in_history', $text );
}

# --- Media ---

sub say ( $self, $text ) {
    return $self->add_action( 'say', $text );
}

sub play_background_file ( $self, $filename, %opts ) {
    my $wait = $opts{wait};
    if ($wait) {
        return $self->add_action( 'playback_bg', { file => $filename, wait => JSON::true } );
    }
    return $self->add_action( 'playback_bg', $filename );
}

sub stop_background_file ($self) {
    return $self->add_action( 'stop_playback_bg', JSON::true );
}

sub record_call ( $self, %opts ) {

    # Defaults mirror the Python reference's argument defaults.
    my $control_id          = $opts{control_id};
    my $stereo              = $opts{stereo}    // 0;
    my $format              = $opts{format}    // 'wav';
    my $direction           = $opts{direction} // 'both';
    my $terminators         = $opts{terminators};
    my $beep                = $opts{beep} // 0;
    my $input_sensitivity   = exists $opts{input_sensitivity} ? $opts{input_sensitivity} : 44.0;
    my $initial_timeout     = $opts{initial_timeout};
    my $end_silence_timeout = $opts{end_silence_timeout};
    my $max_length          = $opts{max_length};
    my $status_url          = $opts{status_url};

    die "format must be 'wav', 'mp3', or 'mp4'"
        unless $format eq 'wav' || $format eq 'mp3' || $format eq 'mp4';
    die "direction must be 'speak', 'listen', or 'both'"
        unless $direction eq 'speak' || $direction eq 'listen' || $direction eq 'both';

    # Always-on keys: stereo/format/direction/beep/input_sensitivity are
    # emitted UNCONDITIONALLY (Python builds them into record_params before
    # any conditional), so beep=false and input_sensitivity=44.0 ship even
    # at their defaults. beep/stereo are JSON booleans; input_sensitivity
    # is a JSON number.
    my %params = (
        stereo            => $stereo ? JSON::true : JSON::false,
        format            => $format,
        direction         => $direction,
        beep              => $beep ? JSON::true : JSON::false,
        input_sensitivity => $input_sensitivity + 0,
    );

    # Conditional keys. control_id/terminators/status_url use Python's
    # truthiness gate (`if x:`); the three numeric timeouts use the
    # `is not None` gate, so a literal 0 still emits — `defined` mirrors that.
    $params{control_id}          = $control_id              if $control_id;
    $params{terminators}         = $terminators             if $terminators;
    $params{initial_timeout}     = $initial_timeout + 0     if defined $initial_timeout;
    $params{end_silence_timeout} = $end_silence_timeout + 0 if defined $end_silence_timeout;
    $params{max_length}          = $max_length + 0          if defined $max_length;
    $params{status_url}          = $status_url              if $status_url;

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { record_call => \%params } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub stop_record_call ( $self, %opts ) {
    my $control_id = $opts{control_id};
    my %params;
    $params{control_id} = $control_id if $control_id;

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { stop_record_call => \%params } ] },
    };
    return $self->execute_swml($swml_doc);
}

# --- Speech & AI ---

sub add_dynamic_hints ( $self, $hints ) {
    return $self->add_action( 'add_dynamic_hints', $hints );
}

sub clear_dynamic_hints ($self) {
    push @{ $self->action }, { clear_dynamic_hints => {} };
    return $self;
}

sub set_end_of_speech_timeout ( $self, $ms ) {
    return $self->add_action( 'end_of_speech_timeout', $ms );
}

sub set_speech_event_timeout ( $self, $ms ) {
    return $self->add_action( 'speech_event_timeout', $ms );
}

sub toggle_functions ( $self, $toggles ) {
    return $self->add_action( 'toggle_functions', $toggles );
}

sub enable_functions_on_timeout ( $self, $enabled = undef ) {
    $enabled //= 1;
    return $self->add_action( 'functions_on_speaker_timeout', $enabled ? JSON::true : JSON::false );
}

sub enable_extensive_data ( $self, $enabled = undef ) {
    $enabled //= 1;
    return $self->add_action( 'extensive_data', $enabled ? JSON::true : JSON::false );
}

sub update_settings ( $self, $settings ) {
    return $self->add_action( 'settings', $settings );
}

# --- Advanced ---

sub execute_swml ( $self, $swml_content, %opts ) {
    my $transfer = $opts{transfer} // 0;

    my $swml_data;
    if ( ref $swml_content eq 'HASH' ) {

        # Deep-copy to avoid mutating caller's data
        $swml_data = JSON::decode_json( JSON::encode_json($swml_content) );
    } elsif ( !ref $swml_content ) {

        # String - try parsing as JSON
        eval { $swml_data = JSON::decode_json($swml_content); };
        if ($@) {
            $swml_data = { raw_swml => $swml_content };
        }
    } else {
        die "swml_content must be a string or hashref";
    }

    if ($transfer) {
        $swml_data->{transfer} = 'true';
    }

    return $self->add_action( 'SWML', $swml_data );
}

# join_conference — join an ad-hoc audio conference (RELAY + CXML) via
# SWML. Full parity with the Python reference
# (core/function_result.py join_conference): 19 params (name + 18
# optional), 7 inline validations with EXACT Python ValueError messages,
# and simple-form (all defaults -> bare conference NAME string) vs
# full-object emission (every NON-DEFAULT param under its snake_case wire
# key). The closed sets are mirrored in SignalWire::SWAIG::JoinConference
# (BEEP/RECORD/TRIM/METHOD), but the `die` guards here are the single
# source of truth at runtime — they reproduce Python's f-string list
# rendering ("beep must be one of ['true', 'false', 'onEnter', 'onExit']").
sub join_conference ( $self, $name, %opts ) {

    # Defaults — exactly the Python reference's argument defaults.
    my $muted                            = $opts{muted} // 0;
    my $beep                             = $opts{beep}  // 'true';
    my $start_on_enter                   = exists $opts{start_on_enter} ? $opts{start_on_enter} : 1;
    my $end_on_exit                      = $opts{end_on_exit} // 0;
    my $wait_url                         = $opts{wait_url};
    my $max_participants                 = $opts{max_participants} // 250;
    my $record                           = $opts{record}           // 'do-not-record';
    my $region                           = $opts{region};
    my $trim                             = $opts{trim} // 'trim-silence';
    my $coach                            = $opts{coach};
    my $status_callback_event            = $opts{status_callback_event};
    my $status_callback                  = $opts{status_callback};
    my $status_callback_method           = $opts{status_callback_method} // 'POST';
    my $recording_status_callback        = $opts{recording_status_callback};
    my $recording_status_callback_method = $opts{recording_status_callback_method} // 'POST';
    my $recording_status_callback_event  = $opts{recording_status_callback_event}  // 'completed';
    my $result                           = $opts{result};

    # --- Validations (match Python's exact ValueError messages) ---

    # beep ∈ {true, false, onEnter, onExit}
    die "beep must be one of ['true', 'false', 'onEnter', 'onExit']"
        unless $beep eq 'true'
        || $beep eq 'false'
        || $beep eq 'onEnter'
        || $beep eq 'onExit';

    # 0 < max_participants <= 250
    die "max_participants must be a positive integer <= 250"
        unless $max_participants > 0 && $max_participants <= 250;

    # record ∈ {do-not-record, record-from-start}
    die "record must be one of ['do-not-record', 'record-from-start']"
        unless $record eq 'do-not-record' || $record eq 'record-from-start';

    # trim ∈ {trim-silence, do-not-trim}
    die "trim must be one of ['trim-silence', 'do-not-trim']"
        unless $trim eq 'trim-silence' || $trim eq 'do-not-trim';

    # status_callback_method ∈ {GET, POST}
    die "status_callback_method must be one of ['GET', 'POST']"
        unless $status_callback_method eq 'GET' || $status_callback_method eq 'POST';

    # recording_status_callback_method ∈ {GET, POST}
    die "recording_status_callback_method must be one of ['GET', 'POST']"
        unless $recording_status_callback_method eq 'GET'
        || $recording_status_callback_method eq 'POST';

    # name not empty after trimming whitespace
    my $trimmed = defined $name ? $name : '';
    $trimmed =~ s/^\s+//;
    $trimmed =~ s/\s+$//;
    die "name cannot be empty" if $trimmed eq '';

    # --- Build the join_conference payload ---

    my $join_params;
    if (  !$muted
        && $beep eq 'true'
        && $start_on_enter
        && !$end_on_exit
        && !defined $wait_url
        && $max_participants == 250
        && $record eq 'do-not-record'
        && !defined $region
        && $trim eq 'trim-silence'
        && !defined $coach
        && !defined $status_callback_event
        && !defined $status_callback
        && $status_callback_method eq 'POST'
        && !defined $recording_status_callback
        && $recording_status_callback_method eq 'POST'
        && $recording_status_callback_event eq 'completed'
        && !defined $result )
    {
        # Simple form — just the conference name as a bare string.
        $join_params = $name;
    } else {

        # Full-object form: name + every NON-DEFAULT param under its
        # snake_case wire key. Each key is emitted only when ≠ default.
        $join_params                   = { name => $name };
        $join_params->{muted}          = JSON::true  if $muted;
        $join_params->{beep}           = $beep       if $beep ne 'true';
        $join_params->{start_on_enter} = JSON::false if !$start_on_enter;
        $join_params->{end_on_exit}    = JSON::true  if $end_on_exit;

        # The six Optional[str] params use Python's truthiness emission
        # gate (`if wait_url:`), i.e. omit when undef OR empty string,
        # while emitting the literal "0" (Python treats "" / None as falsy
        # but "0" as truthy for str). `defined && length` reproduces that.
        $join_params->{wait_url}         = $wait_url if defined $wait_url && length $wait_url;
        $join_params->{max_participants} = $max_participants if $max_participants != 250;
        $join_params->{record}           = $record           if $record ne 'do-not-record';
        $join_params->{region}           = $region           if defined $region && length $region;
        $join_params->{trim}             = $trim             if $trim ne 'trim-silence';
        $join_params->{coach}            = $coach            if defined $coach && length $coach;
        $join_params->{status_callback_event} = $status_callback_event
            if defined $status_callback_event && length $status_callback_event;
        $join_params->{status_callback} = $status_callback
            if defined $status_callback && length $status_callback;
        $join_params->{status_callback_method} = $status_callback_method
            if $status_callback_method ne 'POST';
        $join_params->{recording_status_callback} = $recording_status_callback
            if defined $recording_status_callback && length $recording_status_callback;
        $join_params->{recording_status_callback_method} = $recording_status_callback_method
            if $recording_status_callback_method ne 'POST';
        $join_params->{recording_status_callback_event} = $recording_status_callback_event
            if $recording_status_callback_event ne 'completed';
        $join_params->{result} = $result if defined $result;
    }

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { join_conference => $join_params } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub join_room ( $self, $name ) {
    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { join_room => { name => $name } } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub sip_refer ( $self, $to_uri ) {
    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { sip_refer => { to_uri => $to_uri } } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub tap ( $self, $uri, %opts ) {
    my $control_id = $opts{control_id};
    my $direction  = $opts{direction} // 'both';
    my $codec      = $opts{codec}     // 'PCMU';
    my $rtp_ptime  = $opts{rtp_ptime} // 20;
    my $status_url = $opts{status_url};

    die "direction must be 'speak', 'hear', or 'both'"
        unless $direction eq 'speak' || $direction eq 'hear' || $direction eq 'both';
    die "codec must be 'PCMU' or 'PCMA'"
        unless $codec eq 'PCMU' || $codec eq 'PCMA';

    # Python: `if rtp_ptime <= 0: raise ValueError(...)`.
    die "rtp_ptime must be a positive integer" if $rtp_ptime <= 0;

    my %params = ( uri => $uri );

    # Conditional keys — each emitted only when it differs from its default,
    # matching Python's per-key gating.
    $params{control_id} = $control_id    if $control_id;
    $params{direction}  = $direction     if $direction ne 'both';
    $params{codec}      = $codec         if $codec ne 'PCMU';
    $params{rtp_ptime}  = $rtp_ptime + 0 if $rtp_ptime != 20;
    $params{status_url} = $status_url    if $status_url;

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { tap => \%params } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub stop_tap ( $self, %opts ) {
    my $control_id = $opts{control_id};
    my %params;
    $params{control_id} = $control_id if $control_id;

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { stop_tap => \%params } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub send_sms ( $self, %opts ) {
    my $to_number   = $opts{to_number}   // die "to_number is required";
    my $from_number = $opts{from_number} // die "from_number is required";
    my $body        = $opts{body};
    my $media       = $opts{media};
    my $tags        = $opts{tags};
    my $region      = $opts{region};

    die "Either body or media must be provided" unless $body || $media;

    my %sms_params = (
        to_number   => $to_number,
        from_number => $from_number,
    );
    $sms_params{body} = $body if $body;

    # Python gates media/tags with `if media:` / `if tags:` — an EMPTY list is
    # falsy and omitted. A Perl arrayref is truthy even when empty, so use the
    # Python-truthiness helper (an empty [] must not reach the wire).
    $sms_params{media}  = $media  if _py_truthy($media);
    $sms_params{tags}   = $tags   if _py_truthy($tags);
    $sms_params{region} = $region if $region;

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { send_sms => \%sms_params } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub pay ( $self, %opts ) {
    my $connector_url = $opts{payment_connector_url} // die "payment_connector_url required";
    my $input_method  = $opts{input_method}          // 'dtmf';
    my $timeout       = $opts{timeout}               // 5;
    my $max_attempts  = $opts{max_attempts}          // 1;
    my $ai_response   = $opts{ai_response}
        // 'The payment status is ${pay_result}, do not mention anything else about collecting payment if successful.';

    # min_postal_code_length is an always-on key in Python
    # (str(min_postal_code_length), default "0"); emit it as a string too.
    my $min_postal_code_length = $opts{min_postal_code_length} // 0;

    my %pay_params = (
        payment_connector_url  => $connector_url,
        input                  => $input_method,
        payment_method         => $opts{payment_method} // 'credit-card',
        timeout                => "$timeout",
        max_attempts           => "$max_attempts",
        security_code          => ( ( $opts{security_code} // 1 ) ? 'true' : 'false' ),
        min_postal_code_length => "$min_postal_code_length",
        token_type             => $opts{token_type}       // 'reusable',
        currency               => $opts{currency}         // 'usd',
        language               => $opts{language}         // 'en-US',
        voice                  => $opts{voice}            // 'woman',
        valid_card_types       => $opts{valid_card_types} // 'visa mastercard amex',
    );

    my $postal = $opts{postal_code} // 1;
    if ( ref $postal || $postal =~ /^[01]$/ ) {
        $pay_params{postal_code} = $postal ? 'true' : 'false';
    } else {
        $pay_params{postal_code} = $postal;
    }

    $pay_params{status_url}    = $opts{status_url}    if $opts{status_url};
    $pay_params{charge_amount} = $opts{charge_amount} if $opts{charge_amount};
    $pay_params{description}   = $opts{description}   if $opts{description};

    # Python gates parameters/prompts with `if parameters:` / `if prompts:` — an
    # EMPTY list is falsy and omitted. Mirror that (a Perl [] is truthy).
    $pay_params{parameters} = $opts{parameters} if _py_truthy( $opts{parameters} );
    $pay_params{prompts}    = $opts{prompts}    if _py_truthy( $opts{prompts} );

    my $swml_doc = {
        version  => '1.0.0',
        sections => {
            main => [ { set => { ai_response => $ai_response } }, { pay => \%pay_params }, ],
        },
    };
    return $self->execute_swml($swml_doc);
}

# --- RPC ---

sub execute_rpc ( $self, %opts ) {
    my $method  = $opts{method} // die "method is required";
    my $params  = $opts{params};
    my $call_id = $opts{call_id};
    my $node_id = $opts{node_id};

    my %rpc_params = ( method => $method );
    $rpc_params{call_id} = $call_id if $call_id;
    $rpc_params{node_id} = $node_id if $node_id;

    # Python gates this with `if params:`, where an EMPTY dict {} is falsy and
    # therefore OMITTED (rpc_ai_unhold passes params={}, which never reaches the
    # wire). A Perl hashref is truthy even when empty, so mirror Python's
    # truthiness: emit params only when it's a NON-EMPTY hashref/arrayref (or a
    # defined non-ref scalar). Without this, ai_unhold would ship `params: {}`.
    $rpc_params{params} = $params if _py_truthy($params);

    my $swml_doc = {
        version  => '1.0.0',
        sections => { main => [ { execute_rpc => \%rpc_params } ] },
    };
    return $self->execute_swml($swml_doc);
}

sub rpc_dial ( $self, %opts ) {
    my $to_number   = $opts{to_number}   // die "to_number is required";
    my $from_number = $opts{from_number} // die "from_number is required";
    my $dest_swml   = $opts{dest_swml}   // die "dest_swml is required";
    my $device_type = $opts{device_type} // 'phone';

    return $self->execute_rpc(
        method => 'dial',
        params => {
            devices => {
                type   => $device_type,
                params => {
                    to_number   => $to_number,
                    from_number => $from_number,
                },
            },
            dest_swml => $dest_swml,
        },
    );
}

sub rpc_ai_message ( $self, %opts ) {
    my $call_id      = $opts{call_id}      // die "call_id is required";
    my $message_text = $opts{message_text} // die "message_text is required";
    my $role         = $opts{role}         // 'system';

    return $self->execute_rpc(
        method  => 'ai_message',
        call_id => $call_id,
        params  => {
            role         => $role,
            message_text => $message_text,
        },
    );
}

sub rpc_ai_unhold ( $self, %opts ) {
    my $call_id = $opts{call_id} // die "call_id is required";

    return $self->execute_rpc(
        method  => 'ai_unhold',
        call_id => $call_id,
        params  => {},
    );
}

sub simulate_user_input ( $self, $text ) {
    return $self->add_action( 'user_input', $text );
}

# --- Payment helpers (class methods) ---

sub create_payment_prompt ( $class_or_self, %opts ) {
    my $for_situation = $opts{for_situation} // die "for_situation is required";
    my $actions       = $opts{actions}       // die "actions is required";
    my $card_type     = $opts{card_type};
    my $error_type    = $opts{error_type};

    my %prompt = (
        for     => $for_situation,
        actions => $actions,
    );
    $prompt{card_type}  = $card_type  if $card_type;
    $prompt{error_type} = $error_type if $error_type;

    return \%prompt;
}

sub create_payment_action ( $class_or_self, $action_type, $phrase ) {
    return { type => $action_type, phrase => $phrase };
}

sub create_payment_parameter ( $class_or_self, $name, $value ) {
    return { name => $name, value => $value };
}

# --- Serialization ---

sub to_hash ($self) {
    my %result;

    $result{response} = $self->response if length $self->response;

    if ( @{ $self->action } ) {
        $result{action}       = $self->action;
        $result{post_process} = JSON::true if $self->post_process;
    }

    # Ensure at least one of response or action
    if ( !keys %result ) {
        $result{response} = 'Action completed.';
    }

    return \%result;
}

sub to_json ($self) {
    return JSON::encode_json( $self->to_hash );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWAIG::FunctionResult - build SWAIG function responses and actions

=head1 SYNOPSIS

    use SignalWire::SWAIG::FunctionResult;

    # Plain spoken response:
    my $result = SignalWire::SWAIG::FunctionResult->new('Order placed.');

    # Response plus call-control actions (chainable, fluent style):
    my $result = SignalWire::SWAIG::FunctionResult->new
        ->set_response('Connecting you now.')
        ->connect('+15551234567', final => 1);

    my $payload = $result->to_hash;   # ready for JSON emission
    my $json    = $result->to_json;

=head1 DESCRIPTION

L<SignalWire::SWAIG::FunctionResult> is the Perl port of
C<signalwire.core.function_result.FunctionResult>. A SWAIG function
handler returns one of these to tell the agent what to say and which
call-control actions to perform. The action list is serialised to the
wire shape the SignalWire AI engine expects.

Most mutators return C<$self> so calls chain fluently. The constructor
accepts either C<< new(response => $text) >>, the positional shorthand
C<< new($text) >>, or C<< new($text, post_process => 1) >>.

The class-method payment helpers (C<create_payment_prompt>,
C<create_payment_action>, C<create_payment_parameter>) may be invoked as
class or instance methods — they build plain hashrefs and hold no state.

=head1 METHODS

The surface mirrors the Python reference; see that documentation for the
authoritative per-argument contract. Grouped by area:

=head2 Core

C<set_response>, C<set_post_process>, C<add_action>, C<add_actions>.

=head2 Call control

C<connect>, C<swml_transfer>, C<hangup>, C<hold>, C<wait_for_user>,
C<stop>, C<join_conference>, C<join_room>, C<sip_refer>, C<send_sms>,
C<pay>.

=head2 State and data

C<update_global_data>, C<remove_global_data>, C<set_metadata>,
C<remove_metadata>, C<swml_user_event>, C<swml_change_step>,
C<swml_change_context>, C<switch_context>, C<replace_in_history>.

=head2 Media

C<say>, C<play_background_file>, C<stop_background_file>, C<record_call>,
C<stop_record_call>, C<tap>, C<stop_tap>.

=head2 Speech and AI

C<add_dynamic_hints>, C<clear_dynamic_hints>, C<set_end_of_speech_timeout>,
C<set_speech_event_timeout>, C<toggle_functions>,
C<enable_functions_on_timeout>, C<enable_extensive_data>,
C<update_settings>, C<simulate_user_input>.

=head2 Advanced / RPC

C<execute_swml>, C<execute_rpc>, C<rpc_dial>, C<rpc_ai_message>,
C<rpc_ai_unhold>.

=head2 Serialization

C<to_hash> (the Python C<to_dict> equivalent) and C<to_json>.

=head1 SEE ALSO

L<SignalWire::SWAIG::RecordCall>, L<SignalWire::SWAIG::Tap>, and
L<SignalWire::SWAIG::JoinConference> for the typed closed sets accepted by
C<record_call>, C<tap>, and C<join_conference>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
