# Compatibility API

The Compatibility API provides a Twilio-compatible LAML surface at `/api/laml/2010-04-01`. All paths are scoped under `/Accounts/{AccountSid}`, where AccountSid is your project ID.

## Sub-Resources

| Accessor | Description |
|----------|-------------|
| `$client->compat->accounts` | Account/subproject management |
| `$client->compat->calls` | Call management + recordings + streams |
| `$client->compat->messages` | SMS/MMS management + media |
| `$client->compat->faxes` | Fax management + media |
| `$client->compat->conferences` | Conference management + participants + recordings + streams |
| `$client->compat->phone_numbers` | Incoming + available phone numbers |
| `$client->compat->applications` | Application management |
| `$client->compat->laml_bins` | cXML/LaML script management |
| `$client->compat->queues` | Queue management + members |
| `$client->compat->recordings` | Recording management |
| `$client->compat->transcriptions` | Transcription management |
| `$client->compat->tokens` | API token management |

## Accounts

```perl
# List accounts/subprojects
my $accounts = $client->compat->accounts->list;

# Create a subproject
my $sub = $client->compat->accounts->create(FriendlyName => 'My Subproject');

# Get/update an account
my $account = $client->compat->accounts->get('AC-sid');
$client->compat->accounts->update('AC-sid', FriendlyName => 'Updated');
```

## Calls

```perl
# List calls
my $calls = $client->compat->calls->list(From => '+15551234567');

# Create a call
my $call = $client->compat->calls->create(
    To   => '+15552222222',
    From => '+15551111111',
    Url  => 'https://example.com/twiml',
);

# Get / update / delete
$call = $client->compat->calls->get('CA-sid');
$client->compat->calls->update('CA-sid', Status => 'completed');
$client->compat->calls->delete('CA-sid');

# Start/update recording on a call
$client->compat->calls->start_recording('CA-sid', channels => 'dual');
$client->compat->calls->update_recording('CA-sid', 'RE-sid', Status => 'paused');

# Start/stop stream on a call
$client->compat->calls->start_stream('CA-sid', Url => 'wss://example.com/stream');
$client->compat->calls->stop_stream('CA-sid', 'ST-sid');
```

## Messages

```perl
# Send an SMS
my $msg = $client->compat->messages->create(
    To   => '+15552222222',
    From => '+15551111111',
    Body => 'Hello from SignalWire!',
);

# List / get / update / delete
my $messages = $client->compat->messages->list;
$msg = $client->compat->messages->get('SM-sid');
$client->compat->messages->update('SM-sid', Body => '');  # redact
$client->compat->messages->delete('SM-sid');

# Media sub-resources
my $media = $client->compat->messages->list_media('SM-sid');
my $item  = $client->compat->messages->get_media('SM-sid', 'ME-sid');
$client->compat->messages->delete_media('SM-sid', 'ME-sid');
```

## Faxes

```perl
# Send a fax
my $fax = $client->compat->faxes->create(
    MediaUrl => 'https://example.com/doc.pdf',
    To       => '+15552222222',
    From     => '+15551111111',
);

# List / get / cancel / delete
my $faxes = $client->compat->faxes->list;
$fax = $client->compat->faxes->get('FX-sid');
$client->compat->faxes->update('FX-sid', Status => 'canceled');
$client->compat->faxes->delete('FX-sid');

# Media sub-resources
my $media = $client->compat->faxes->list_media('FX-sid');
my $item  = $client->compat->faxes->get_media('FX-sid', 'ME-sid');
$client->compat->faxes->delete_media('FX-sid', 'ME-sid');
```

## Conferences

```perl
# List / get / update
my $conferences = $client->compat->conferences->list;
my $conf = $client->compat->conferences->get('CF-sid');
$client->compat->conferences->update('CF-sid', Status => 'completed');

# Participants
my $participants = $client->compat->conferences->list_participants('CF-sid');
my $p = $client->compat->conferences->get_participant('CF-sid', 'CA-sid');
$client->compat->conferences->update_participant('CF-sid', 'CA-sid', Muted => 1);
$client->compat->conferences->remove_participant('CF-sid', 'CA-sid');

# Conference recordings
my $recs = $client->compat->conferences->list_recordings('CF-sid');
my $rec  = $client->compat->conferences->get_recording('CF-sid', 'RE-sid');
$client->compat->conferences->update_recording('CF-sid', 'RE-sid', Status => 'stopped');
$client->compat->conferences->delete_recording('CF-sid', 'RE-sid');

# Conference streams
$client->compat->conferences->start_stream('CF-sid', Url => 'wss://example.com/stream');
$client->compat->conferences->stop_stream('CF-sid', 'ST-sid');
```

## Phone Numbers

```perl
# List purchased numbers
my $numbers = $client->compat->phone_numbers->list;

# Search available numbers
my $local     = $client->compat->phone_numbers->search_local('US', AreaCode => '512');
my $toll_free = $client->compat->phone_numbers->search_toll_free('US');
my $countries = $client->compat->phone_numbers->list_available_countries;

# Purchase / get / update / release
my $num = $client->compat->phone_numbers->purchase(PhoneNumber => '+15551234567');
$num = $client->compat->phone_numbers->get('PN-sid');
$client->compat->phone_numbers->update('PN-sid', VoiceUrl => 'https://example.com/voice');
$client->compat->phone_numbers->delete('PN-sid');

# Import external number
$client->compat->phone_numbers->import_number(PhoneNumber => '+15559999999');
```

## Applications

```perl
my $apps = $client->compat->applications->list;
my $app  = $client->compat->applications->create(
    FriendlyName => 'My App',
    VoiceUrl     => 'https://example.com/voice',
);
$app = $client->compat->applications->get('AP-sid');
$client->compat->applications->update('AP-sid', VoiceUrl => 'https://example.com/new-voice');
$client->compat->applications->delete('AP-sid');
```

## LaML Bins (cXML Scripts)

```perl
my $bins = $client->compat->laml_bins->list;
my $bin  = $client->compat->laml_bins->create(
    Name     => 'Greeting',
    Contents => '<Response><Say>Hello</Say></Response>',
);
$bin = $client->compat->laml_bins->get('LB-sid');
$client->compat->laml_bins->update('LB-sid', Contents => '<Response><Say>Updated</Say></Response>');
$client->compat->laml_bins->delete('LB-sid');
```

## Queues

```perl
my $queues = $client->compat->queues->list;
my $q = $client->compat->queues->create(FriendlyName => 'Support', MaxSize => 100);
$q = $client->compat->queues->get('QU-sid');
$client->compat->queues->update('QU-sid', MaxSize => 200);
$client->compat->queues->delete('QU-sid');

# Members
my $members = $client->compat->queues->list_members('QU-sid');
my $member  = $client->compat->queues->get_member('QU-sid', 'CA-sid');
$client->compat->queues->dequeue_member('QU-sid', 'CA-sid', Url => 'https://example.com/dequeue');
```

## Recordings & Transcriptions

```perl
# Recordings
my $recs = $client->compat->recordings->list;
my $rec  = $client->compat->recordings->get('RE-sid');
$client->compat->recordings->delete('RE-sid');

# Transcriptions
my $txns = $client->compat->transcriptions->list;
my $txn  = $client->compat->transcriptions->get('TR-sid');
$client->compat->transcriptions->delete('TR-sid');
```

## Tokens

```perl
my $token = $client->compat->tokens->create(name => 'my-token', permissions => ['calling', 'messaging']);
$client->compat->tokens->update('token-id', name => 'renamed');
$client->compat->tokens->delete('token-id');
```
