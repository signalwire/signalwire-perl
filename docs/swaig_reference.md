# FunctionResult Methods Reference

SWAIG (SignalWire AI Gateway) is the platform's AI tool-calling system -- it connects the AI's decisions to actions like call transfers, SMS, recordings, and API calls, with native access to the media stack. This document provides a complete reference for all methods available in the `SignalWire::SWAIG::FunctionResult` class. These methods provide convenient abstractions for SWAIG actions, eliminating the need to manually construct action JSON objects.

A SWAIG tool handler returns one of these objects. Most mutators return `$self`, so calls chain fluently. Throughout this reference, assume:

```perl
use SignalWire::SWAIG::FunctionResult;
```

## Core Methods

### Basic Construction & Control

#### `new($response)` / `new($response, post_process => 1)`
Creates a new result object with optional response text and post-processing behavior. The constructor is positional: a single string is the response. You may also pass named pairs.

```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new("Hello, I'll help you with that");
my $result = SignalWire::SWAIG::FunctionResult->new("Processing request...", post_process => 1);
```

#### `set_response($response)`
Sets or updates the response text that the AI will speak.

```perl
$result->set_response("I've updated your information");
```

#### `set_post_process($post_process)`
Controls whether the AI gets one more turn before executing actions.

```perl
$result->set_post_process(1);   # AI speaks response before executing actions
$result->set_post_process(0);   # actions execute immediately
```

---

## Action Methods

### Call Control Actions

#### `execute_swml($swml_content, transfer => 0)`
Execute SWML content with flexible input support and optional transfer behavior. Accepts a JSON string or a hashref.

```perl
# Raw SWML string
$result->execute_swml('{"version":"1.0.0","sections":{"main":[{"say":"Hello"}]}}');

# SWML hashref
my $swml = { version => '1.0.0', sections => { main => [ { say => 'Hello' } ] } };
$result->execute_swml($swml, transfer => 1);
```

#### `connect($destination, final => 1, from => $addr)`
Transfer/connect the call to another destination using SWML.

```perl
$result->connect('+15551234567', final => 1);                                  # permanent transfer
$result->connect('support@company.com', final => 0, from => '+15559876543');   # temporary transfer
```

#### `send_sms(to_number =>, from_number =>, body =>, media =>, tags =>, region =>)`
Send an SMS message to a PSTN phone number using SWML.

```perl
# Simple text message
$result->send_sms(
    to_number   => '+15551234567',
    from_number => '+15559876543',
    body        => 'Your order has been confirmed!',
);

# Media message with images
$result->send_sms(
    to_number   => '+15551234567',
    from_number => '+15559876543',
    media       => ['https://example.com/receipt.jpg', 'https://example.com/map.png'],
);

# Full featured message with tags and region
$result->send_sms(
    to_number   => '+15551234567',
    from_number => '+15559876543',
    body        => 'Order update with receipt attached',
    media       => ['https://example.com/receipt.pdf'],
    tags        => ['order', 'confirmation', 'customer'],
    region      => 'us',
);
```

**Parameters:**
- `to_number` (required): Phone number in E.164 format to send to
- `from_number` (required): Phone number in E.164 format to send from
- `body` (optional): Message text (required if no media)
- `media` (optional): Arrayref of URLs to send (required if no body)
- `tags` (optional): Arrayref of tags for UI searching
- `region` (optional): Region to originate message from

**Variables Set:**
- `send_sms_result`: "success" or "failed"

#### `pay(payment_connector_url =>, %options)`
Process payments using the SWML pay action with extensive customization.

```perl
# Simple payment setup
$result->pay(
    payment_connector_url => 'https://api.example.com/accept-payment',
    charge_amount         => '10.99',
    description           => 'Monthly subscription',
);

# Advanced payment with custom prompts (class-method helpers build the hashrefs)
my @welcome_actions = (
    SignalWire::SWAIG::FunctionResult->create_payment_action('Say', 'Welcome to our payment system'),
    SignalWire::SWAIG::FunctionResult->create_payment_action('Say', 'Please enter your credit card number'),
);
my $card_prompt = SignalWire::SWAIG::FunctionResult->create_payment_prompt(
    for_situation => 'payment-card-number',
    actions       => \@welcome_actions,
);

my @error_actions = (
    SignalWire::SWAIG::FunctionResult->create_payment_action('Say', 'Invalid card number, please try again'),
);
my $error_prompt = SignalWire::SWAIG::FunctionResult->create_payment_prompt(
    for_situation => 'payment-card-number',
    actions       => \@error_actions,
    error_type    => 'invalid-card-number timeout',
);

# Payment parameters
my @params = (
    SignalWire::SWAIG::FunctionResult->create_payment_parameter('customer_id', '12345'),
    SignalWire::SWAIG::FunctionResult->create_payment_parameter('order_id', 'ORD-789'),
);

# Full payment configuration
$result->pay(
    payment_connector_url => 'https://api.example.com/accept-payment',
    status_url            => 'https://api.example.com/payment-status',
    timeout               => 10,
    max_attempts          => 3,
    security_code         => 1,
    postal_code           => 0,
    token_type            => 'one-time',
    charge_amount         => '25.50',
    currency              => 'usd',
    language              => 'en-US',
    voice                 => 'polly.Sally',
    description           => 'Premium service upgrade',
    valid_card_types      => 'visa mastercard amex',
    parameters            => \@params,
    prompts               => [$card_prompt, $error_prompt],
);
```

**Core Parameters:**
- `payment_connector_url` (required): URL to process payment requests
- `input_method`: "dtmf" or "voice" (default: "dtmf")
- `payment_method`: "credit-card" (default: "credit-card")
- `timeout`: Seconds to wait for input (default: 5)
- `max_attempts`: Number of retry attempts (default: 1)

**Security & Validation:**
- `security_code`: Prompt for CVV (default: true)
- `postal_code`: Prompt for postal code or provide known code (default: true)
- `min_postal_code_length`: Minimum postal code digits (default: 0)
- `valid_card_types`: Space-separated card types (default: "visa mastercard amex")

**Payment Configuration:**
- `token_type`: "one-time" or "reusable" (default: "reusable")
- `charge_amount`: Amount as decimal string
- `currency`: Currency code (default: "usd")
- `description`: Payment description

**Customization:**
- `language`: Prompt language (default: "en-US")
- `voice`: TTS voice (default: "woman")
- `status_url`: URL for status notifications
- `parameters`: Additional name/value pairs for connector
- `prompts`: Custom prompt configurations

**Helper Methods for Payment Setup (class methods):**
```perl
use SignalWire::SWAIG::FunctionResult;
# Create a payment action
my $action = SignalWire::SWAIG::FunctionResult->create_payment_action('Say', 'Enter card number');

# Create a payment prompt
my $prompt = SignalWire::SWAIG::FunctionResult->create_payment_prompt(
    for_situation => 'payment-card-number',
    actions       => [$action],
    error_type    => 'invalid-card-number',
);

# Create a payment parameter
my $param = SignalWire::SWAIG::FunctionResult->create_payment_parameter('customer_id', '12345');
```

**Variables Set:**
- `pay_result`: "success", "too-many-failed-attempts", "payment-connector-error", etc.
- `pay_payment_results`: JSON with payment details including tokens and card info

#### `record_call(%options)`
Start background call recording using SWML. Unlike foreground recording, the script continues executing while recording happens in the background.

```perl
# Simple background recording
$result->record_call;

# Recording with custom settings
$result->record_call(
    control_id => 'support_call_001',
    stereo     => 1,
    format     => 'mp3',
    direction  => 'both',
    max_length => 300,   # 5 minutes max
);

# Recording with terminator and status webhook
$result->record_call(
    control_id          => 'customer_voicemail',
    format              => 'wav',
    direction           => 'speak',      # only record the customer's voice
    terminators         => '#',          # stop on '#' press
    beep                => 1,            # play a beep before recording
    initial_timeout     => 4.0,          # wait 4 seconds for speech
    end_silence_timeout => 3.0,          # stop after 3 seconds of silence
    status_url          => 'https://api.example.com/recording-status',
);
```

**Core Parameters:**
- `control_id` (optional): Identifier for this recording (for use with `stop_record_call`)
- `stereo`: Record in stereo (default: false)
- `format`: "wav", "mp3", or "mp4" (default: "wav")
- `direction`: "speak", "listen", or "both" (default: "both")

**Control Options:**
- `terminators`: Digits that stop recording when pressed
- `beep`: Play a beep before recording (default: false)
- `max_length`: Maximum recording length in seconds

**Timing Options:**
- `input_sensitivity`: Input sensitivity (default: 44.0)
- `initial_timeout`: Time to wait for speech start
- `end_silence_timeout`: Time to wait in silence before ending

**Webhook Options:**
- `status_url`: URL to send recording status events to

**Variables Set:**
- `record_call_result`: "success" or "failed"
- `record_call_url`: URL of recorded file (when recording completes)

#### `stop_record_call(control_id => $id)`
Stop an active background call recording using SWML.

```perl
# Stop the most recent recording
$result->stop_record_call;

# Stop a specific recording by ID
$result->stop_record_call(control_id => 'support_call_001');

# Chain to stop recording and provide feedback
$result->stop_record_call(control_id => 'customer_voicemail')
    ->say('Thank you, your message has been recorded');
```

**Parameters:**
- `control_id` (optional): Identifier for recording to stop. If not provided, stops the most recent recording.

**Variables Set:**
- `stop_record_call_result`: "success" or "failed"

#### `join_room($name)`
Join a RELAY room using SWML. RELAY rooms enable multi-party communication and collaboration features.

```perl
# Join a conference room
$result->join_room('support_team_room');

# Join a customer meeting room and announce
$result->join_room('customer_meeting_001')
    ->say('Welcome to the customer meeting room');

# Join a room and set metadata
$result->join_room('sales_conference')
    ->set_metadata({ participant_role => 'moderator', join_time => '2024-01-01T12:00:00Z' });
```

**Parameters:**
- `name` (required): The name of the room to join

**Variables Set:**
- `join_room_result`: "success" or "failed"

#### `sip_refer($to_uri)`
Send a SIP REFER for call transfer using SWML. SIP REFER is used for call transfer in SIP environments, allowing one endpoint to request another to initiate a new connection.

```perl
# Basic SIP refer to transfer the call
$result->sip_refer('sip:support@company.com');

# Transfer to a specific SIP address with domain
$result->sip_refer('sip:agent123@pbx.company.com:5060');

# Chain with an announcement
$result->say('Transferring your call to our specialist')
    ->sip_refer('sip:specialist@company.com');
```

**Parameters:**
- `to_uri` (required): The SIP URI to send the REFER to

**Variables Set:**
- `sip_refer_result`: "success" or "failed"

#### `join_conference($name, %options)`
Join an ad-hoc audio conference (RELAY and CXML calls) using SWML. Provides extensive configuration options for conference call management and recording.

```perl
# Simple conference join
$result->join_conference('my_conference');

# Basic conference with recording
$result->join_conference('daily_standup',
    record           => 'record-from-start',
    max_participants => 10,
);

# Advanced conference with callbacks and coaching
$result->join_conference('customer_support_conf',
    muted                     => 0,
    beep                      => 'onEnter',
    start_on_enter            => 1,
    end_on_exit               => 0,
    max_participants          => 50,
    record                    => 'record-from-start',
    region                    => 'us-east',
    trim                      => 'trim-silence',
    status_callback           => 'https://api.company.com/conference-events',
    status_callback_event     => 'start end join leave',
    recording_status_callback => 'https://api.company.com/recording-events',
);

# Chain with other actions
$result->say('Joining you to the team conference')
    ->join_conference('team_meeting')
    ->set_metadata({ meeting_type => 'team_sync', participant_role => 'attendee' });
```

**Core Parameters:**
- `name` (required): Name of conference to join
- `muted`: Join muted (default: false)
- `beep`: Beep configuration - "true", "false", "onEnter", "onExit" (default: "true")
- `start_on_enter`: Conference starts when this participant enters (default: true)
- `end_on_exit`: Conference ends when this participant exits (default: false)

**Capacity & Region:**
- `max_participants`: Maximum participants <= 250 (default: 250)
- `region`: Conference region for optimization
- `wait_url`: SWML URL for custom hold music

**Recording Options:**
- `record`: "do-not-record" or "record-from-start" (default: "do-not-record")
- `trim`: "trim-silence" or "do-not-trim" (default: "trim-silence")
- `recording_status_callback`: URL for recording status events
- `recording_status_callback_method`: "GET" or "POST" (default: "POST")
- `recording_status_callback_event`: (default: "completed")

**Status & Coaching:**
- `coach`: SWML Call ID or CXML CallSid for coaching features
- `status_callback`: URL for conference status events
- `status_callback_method`: "GET" or "POST" (default: "POST")
- `status_callback_event`: Events to report

**Control Flow:**
- `result`: Switch on return value (object or array for conditional logic)

**Variables Set:**
- `join_conference_result`: "completed", "answered", "no-answer", "failed", or "canceled"

#### `tap($uri, %options)`
Start a background call tap using SWML. Media is streamed over WebSocket or RTP to a customer-controlled URI for real-time monitoring and analysis.

```perl
# Simple WebSocket tap
$result->tap('wss://example.com/tap');

# RTP tap with custom settings
$result->tap('rtp://192.168.1.100:5004',
    control_id => 'monitoring_tap_001',
    direction  => 'both',
    codec      => 'PCMA',
    rtp_ptime  => 30,
);

# Advanced tap with status callbacks
$result->tap('wss://monitoring.company.com/audio-stream',
    control_id => 'compliance_tap',
    direction  => 'speak',   # only what the party says
    status_url => 'https://api.company.com/tap-status',
)->set_metadata({ tap_purpose => 'compliance', session_id => 'sess_123' });
```

**Core Parameters:**
- `uri` (required): Destination of the tap media stream (`ws://`, `wss://`, or `rtp://IP:port`)
- `control_id`: Identifier for this tap to use with `stop_tap` (optional)

**Audio Configuration:**
- `direction`: "speak", "hear", or "both" (default: "both")
- `codec`: "PCMU" or "PCMA" (default: "PCMU")
- `rtp_ptime`: RTP packetization time in milliseconds (default: 20)

**Status & Monitoring:**
- `status_url`: URL for tap status change requests

**Variables Set:**
- `tap_uri`, `tap_result`, `tap_control_id`, `tap_rtp_src_addr`, `tap_rtp_src_port`, `tap_ptime`, `tap_codec`, `tap_rate`

#### `stop_tap(control_id => $id)`
Stop an active tap stream using SWML.

```perl
# Stop the most recent tap
$result->stop_tap;

# Stop a specific tap by ID
$result->stop_tap(control_id => 'monitoring_tap_001');

# Chain to stop tap and provide feedback
$result->stop_tap(control_id => 'compliance_tap')
    ->say('Audio monitoring has been stopped')
    ->update_global_data({ tap_active => JSON::false });
```

**Parameters:**
- `control_id` (optional): ID of the tap to stop. If not set, the last tap started is stopped.

**Variables Set:**
- `stop_tap_result`: "success" or "failed"

#### `hangup()`
Terminate the call immediately.

```perl
$result->hangup;
```

---

### Call Flow Control

#### `hold($timeout)`
Put the call on hold with a timeout (clamped to 0..900 seconds; default 300).

```perl
$result->hold(60);    # hold for 1 minute
$result->hold(600);   # hold for 10 minutes
```

#### `wait_for_user(enabled =>, timeout =>, answer_first =>)`
Control how the agent waits for user input with flexible named parameters.

```perl
$result->wait_for_user(enabled => 1);          # wait indefinitely
$result->wait_for_user(timeout => 30);         # wait 30 seconds
$result->wait_for_user(answer_first => 1);     # special answer_first mode
$result->wait_for_user(enabled => 0);          # disable waiting
```

#### `stop()`
Stop agent execution completely.

```perl
$result->stop;
```

---

### Speech & Audio Control

#### `say($text)`
Make the agent speak specific text immediately.

```perl
$result->say('Please hold while I look that up for you');
```

#### `play_background_file($filename, wait => 0)`
Play an audio file in the background with attention control.

```perl
$result->play_background_file('hold_music.wav');                 # AI tries to get attention
$result->play_background_file('announcement.mp3', wait => 1);    # AI suppresses attention
```

#### `stop_background_file()`
Stop the currently playing background audio.

```perl
$result->stop_background_file;
```

---

### Speech Recognition Settings

#### `set_end_of_speech_timeout($milliseconds)`
Set the silence timeout after speech detection for finalizing recognition.

```perl
$result->set_end_of_speech_timeout(2000);   # 2 seconds of silence
```

#### `set_speech_event_timeout($milliseconds)`
Set the timeout since the last speech event - better for noisy environments.

```perl
$result->set_speech_event_timeout(3000);    # 3 seconds since last speech event
```

---

### Data Management

#### `update_global_data($data)`
Update global agent data variables.

```perl
$result->update_global_data({ user_name => 'John', step => 2 });
```

#### `remove_global_data($keys)`
Remove global data variables by key(s).

```perl
$result->remove_global_data('temporary_data');           # single key
$result->remove_global_data(['step', 'temp_value']);     # multiple keys
```

#### `set_metadata($data)`
Set metadata scoped to the current function's meta_data_token.

```perl
$result->set_metadata({ session_id => 'abc123', user_tier => 'premium' });
```

#### `remove_metadata($keys)`
Remove metadata from the current function's scope.

```perl
$result->remove_metadata('temp_session_data');           # single key
$result->remove_metadata(['cache_key', 'temp_flag']);    # multiple keys
```

---

### Function & Behavior Control

#### `toggle_functions($function_toggles)`
Enable/disable specific SWAIG functions dynamically.

```perl
$result->toggle_functions([
    { function => 'transfer_call', active => JSON::false },
    { function => 'lookup_info',   active => JSON::true },
]);
```

#### `enable_functions_on_timeout($enabled)`
Control whether functions can be called on speaker timeout.

```perl
$result->enable_functions_on_timeout(1);
$result->enable_functions_on_timeout(0);
```

#### `enable_extensive_data($enabled)`
Send full data to the LLM for this turn only, then use a smaller replacement.

```perl
$result->enable_extensive_data(1);   # send extensive data this turn
$result->enable_extensive_data(0);   # use normal data
```

#### `replace_in_history($text)`
Remove or replace the tool_call + tool_result pair from the LLM's conversation history after the first send. This is useful when a function call is an implementation detail that would confuse the model if it remained visible in context.

When called with a string, the tool_call/tool_result pair is replaced with an assistant message containing that text. When called with no argument (or a true value), the pair is removed entirely — the LLM will never see that the function was called.

```perl
use SignalWire::SWAIG::FunctionResult;
# Remove entirely — LLM won't see this function was called
my $result = SignalWire::SWAIG::FunctionResult->new('Done.');
$result->replace_in_history;

# Replace with a friendly assistant message instead of tool artifacts
my $result = SignalWire::SWAIG::FunctionResult->new('Profile saved.');
$result->replace_in_history("I've saved your profile information.");

# Practical example: a data-collection tool that shouldn't clutter history
$agent->define_tool(
    name        => 'save_answer',
    description => 'Save the user\'s answer',
    parameters  => {
        type       => 'object',
        properties => { answer => { type => 'string', description => 'The answer to save' } },
    },
    handler => sub {
        my ($args, $raw_data) = @_;
        my $answer = $args->{answer};
        my $result = SignalWire::SWAIG::FunctionResult->new("Answer recorded: $answer");
        $result->replace_in_history;   # keep history clean
        return $result;
    },
);
```

**When to use:**
- Functions that are implementation details (saving data, logging, internal state changes)
- Functions called frequently that would bloat conversation history
- Situations where tool artifacts confuse the model's reasoning (especially with reasoning models at low effort settings)

**Note:** For structured data collection, consider using [gather_info mode](contexts_guide.md#gather-info-mode) instead, which produces zero tool artifacts by design and doesn't require `replace_in_history`.

---

### Agent Settings & Configuration

#### `update_settings($settings)`
Update agent runtime settings with validation.

```perl
# AI model settings
$result->update_settings({
    temperature         => 0.7,
    'max-tokens'        => 2048,
    'frequency-penalty' => -0.5,
});

# Speech recognition settings
$result->update_settings({
    confidence         => 0.8,
    'barge-confidence' => 0.7,
});
```

**Supported Settings:**
- `frequency-penalty`: Float (-2.0 to 2.0)
- `presence-penalty`: Float (-2.0 to 2.0)
- `max-tokens`: Integer (0 to 4096)
- `top-p`: Float (0.0 to 1.0)
- `confidence`: Float (0.0 to 1.0)
- `barge-confidence`: Float (0.0 to 1.0)
- `temperature`: Float (0.0 to 2.0, clamped to 1.5)

#### `switch_context(system_prompt =>, user_prompt =>, consolidate =>, full_reset =>)`
Change the agent context/prompt during the conversation.

```perl
# Simple context switch
$result->switch_context(system_prompt => 'You are now a technical support agent');

# Advanced context switch
$result->switch_context(
    system_prompt => 'You are a billing specialist',
    user_prompt   => 'The user needs help with their invoice',
    consolidate   => 1,
);
```

#### `swml_change_context($context_name)` / `swml_change_step($step_name)`
Navigate the contexts/steps flow by name (see the [Contexts Guide](contexts_guide.md)).

```perl
$result->swml_change_context('support');
$result->swml_change_step('verify_identity');
```

#### `simulate_user_input($text)`
Queue simulated user input for testing or flow control.

```perl
$result->simulate_user_input("Yes, I'd like to speak to billing");
```

---

## Low-Level Methods

### Manual Action Construction

#### `add_action($name, $data)`
Add a single action manually (for custom actions not covered by helper methods).

```perl
$result->add_action('custom_action', { param => 'value' });
```

#### `add_actions($actions)`
Add multiple actions at once.

```perl
$result->add_actions([
    { say  => 'Hello' },
    { hold => 300 },
]);
```

### Output Generation

#### `to_hash()`
Convert the result to a hashref for JSON serialization. (`to_json()` returns the encoded string.)

```perl
my $result_hash = $result->to_hash;
# Returns: { response => '...', action => [...], post_process => 1 }
```

---

## Method Chaining

All mutators return `$self` to enable fluent method chaining:

```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new('Processing your request', post_process => 1)
    ->update_global_data({ status => 'processing' })
    ->play_background_file('processing.wav', wait => 1)
    ->set_end_of_speech_timeout(2500);

# Complex chaining example
my $result = SignalWire::SWAIG::FunctionResult->new('Let me transfer you to billing')
    ->set_metadata({ transfer_reason => 'billing_inquiry' })
    ->update_global_data({ last_action => 'transfer_to_billing' })
    ->connect('+15551234567', final => 1);
```

---

## Method Summary

- **Call control**: `connect()`, `swml_transfer()`, `hangup()`, `hold()`, `wait_for_user()`, `stop()`, `join_conference()`, `join_room()`, `sip_refer()`, `send_sms()`, `pay()`
- **Media**: `say()`, `play_background_file()`, `stop_background_file()`, `record_call()`, `stop_record_call()`, `tap()`, `stop_tap()`
- **State and data**: `update_global_data()`, `remove_global_data()`, `set_metadata()`, `remove_metadata()`, `switch_context()`, `swml_change_context()`, `swml_change_step()`, `swml_user_event()`, `replace_in_history()`
- **Speech and AI**: `add_dynamic_hints()`, `clear_dynamic_hints()`, `set_end_of_speech_timeout()`, `set_speech_event_timeout()`, `toggle_functions()`, `enable_functions_on_timeout()`, `enable_extensive_data()`, `update_settings()`, `simulate_user_input()`
- **Advanced / RPC**: `execute_swml()`, `execute_rpc()`, `rpc_dial()`, `rpc_ai_message()`, `rpc_ai_unhold()`
- **Class-method helpers**: `create_payment_prompt()`, `create_payment_action()`, `create_payment_parameter()`
- **Serialization**: `to_hash()`, `to_json()`

## Best Practices

1. **Use `post_process => 1`** when you want the AI to speak before executing actions
2. **Chain methods** for cleaner, more readable code
3. **Use specific methods** instead of manual action construction when available
4. **Handle errors gracefully** - methods may `die` for invalid inputs
5. **Validate settings** - `update_settings()` relies on server-side validation

---

## Post Data Reference

The raw data passed to a SWAIG handler is its second argument (`my ($args, $raw_data) = @_;`). Its structure differs between webhook functions and DataMap functions.

### Base Keys (All Functions)

| Key | Type | Description |
|-----|------|-------------|
| `app_name` | string | Name of the AI application |
| `function` | string | Name of the SWAIG function being called |
| `call_id` | string | Unique UUID of the current call session |
| `ai_session_id` | string | Unique UUID of the AI session |
| `caller_id_name` | string | Caller ID name (if available) |
| `caller_id_num` | string | Caller ID number (if available) |
| `channel_active` | boolean | Whether the channel is currently up |
| `channel_offhook` | boolean | Whether the channel is off-hook |
| `channel_ready` | boolean | Whether the AI session is ready |
| `argument` | object | Parsed function arguments |
| `argument_desc` | object | Function argument schema/description |
| `purpose` | string | Description of what the function does |
| `content_type` | string | Always `"text/swaig"` |
| `version` | string | SWAIG protocol version |
| `global_data` | object | Application-level global data (when set) |
| `conversation_id` | string | Conversation identifier (when tracking enabled) |
| `project_id` | string | SignalWire project ID |
| `space_id` | string | SignalWire space ID |

### Webhook-Only Keys

These keys are only present for traditional webhook SWAIG functions:

| Key | Type | Description | Present When |
|-----|------|-------------|--------------|
| `meta_data_token` | string | Token for metadata access | Function has metadata token |
| `meta_data` | object | Function-level metadata | Function has metadata token |
| `SWMLVars` | object | SWML variables | `swaig_post_swml_vars` parameter set |
| `SWMLCall` | object | SWML call state | `swaig_post_swml_vars` parameter set |
| `call_log` | array | Processed conversation history | `swaig_post_conversation` is true |
| `raw_call_log` | array | Raw conversation history | `swaig_post_conversation` is true |

**Metadata scoping**: Functions sharing the same `meta_data_token` share access to the same metadata. If no token is specified, scope defaults to function name/URL.

**Conversation history**: `call_log` may shrink after conversation resets (consolidation), while `raw_call_log` preserves full history. Both include timing data (latency, utterance_latency, audio_latency).

### DataMap-Specific Keys

| Key | Type | Description |
|-----|------|-------------|
| `prompt_vars` | object | Template variables built from call context, SWML vars, and global_data |
| `args` | object | First parsed argument object for easy template access |
| `input` | object | Copy of entire post data for variable expansion |

### prompt_vars Contents

| Key | Source | Description |
|-----|--------|-------------|
| `call_direction` | Call direction | `"inbound"` or `"outbound"` |
| `caller_id_name` | Channel variable | Caller's name |
| `caller_id_number` | Channel variable | Caller's number |
| `local_date` | System time | Current date in local timezone |
| `local_time` | System time | Current time with timezone |
| `time_of_day` | Derived from hour | `"morning"`, `"afternoon"`, or `"evening"` |
| `supported_languages` | App config | Available languages |
| `default_language` | App config | Primary language |

All keys from `global_data` are also merged into `prompt_vars`, with global_data taking precedence.

### SWML Parameters Controlling Post Data

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `swaig_allow_swml` | boolean | true | Allow functions to execute SWML actions |
| `swaig_allow_settings` | boolean | true | Allow functions to modify AI settings |
| `swaig_post_conversation` | boolean | false | Include conversation history in post data |
| `swaig_set_global_data` | boolean | true | Allow functions to modify global_data |
| `swaig_post_swml_vars` | boolean/array | false | Include SWML variables in post data |

### Variable Expansion in DataMap

DataMap processing supports template expansion with access to:

- Nested object access via dot notation: `${user.name}`
- Array access: `${items[0].value}`
- Encoding functions: `${enc:url:variable}`
- Built-in functions: `@{strftime %Y-%m-%d}`, `@{expr 2+2}`

---

## Related Documentation

- **[API Reference](api_reference.md)** - Complete AgentBase and FunctionResult API reference
- **[Contexts Guide](contexts_guide.md)** - Using `swml_change_context()` and `swml_change_step()`
- **[DataMap Guide](datamap_guide.md)** - Using FunctionResult with DataMap outputs
- **[Agent Guide](agent_guide.md)** - General agent development guide

### Example Files

- [`examples/simple_agent.pl`](../examples/simple_agent.pl) - Basic SWAIG function usage
- [`examples/datamap_demo.pl`](../examples/datamap_demo.pl) - DataMap tools alongside a regular SWAIG function
