# All Namespaces

Reference for every namespace beyond Fabric, Calling, and Compat (which have their own pages).

## Phone Numbers

```perl
# List your phone numbers
my $numbers = $client->phone_numbers->list;
$numbers    = $client->phone_numbers->list(name => 'Main');

# Search available numbers to purchase
my $available = $client->phone_numbers->search(area_code => '512', number_type => 'local');

# Purchase a number
my $number = $client->phone_numbers->create(number => '+15551234567');

# Get / update / release
$number = $client->phone_numbers->get('pn-uuid');
$client->phone_numbers->update('pn-uuid', name => 'Support Line');
$client->phone_numbers->delete('pn-uuid');
```

Phone numbers also expose typed binding helpers (`set_swml_webhook`, `set_ai_agent`,
and friends) -- see [phone-binding.md](phone-binding.md).

## Addresses

```perl
my $addresses = $client->addresses->list;
my $address   = $client->addresses->create(
    friendly_name => 'Office',
    street        => '123 Main St',
    city          => 'Austin',
    region        => 'TX',
);
$address = $client->addresses->get('addr-uuid');
$client->addresses->delete('addr-uuid');
```

## Queues

```perl
my $queues = $client->queues->list;
my $queue  = $client->queues->create(name => 'Support');
$queue     = $client->queues->get('q-uuid');
$client->queues->update('q-uuid', name => 'VIP Support');
$client->queues->delete('q-uuid');

# Members
my $members     = $client->queues->list_members('q-uuid');
my $next_member = $client->queues->get_next_member('q-uuid');
my $member      = $client->queues->get_member('q-uuid', 'member-uuid');
```

## Recordings

```perl
my $recordings = $client->recordings->list;
my $recording  = $client->recordings->get('rec-uuid');
$client->recordings->delete('rec-uuid');
```

## Number Groups

```perl
my $groups = $client->number_groups->list;
my $group  = $client->number_groups->create(name => 'Marketing');
$group     = $client->number_groups->get('ng-uuid');
$client->number_groups->update('ng-uuid', name => 'Sales');
$client->number_groups->delete('ng-uuid');

# Memberships
my $memberships = $client->number_groups->list_memberships('ng-uuid');
$client->number_groups->add_membership('ng-uuid', phone_number_id => 'pn-uuid');
my $membership = $client->number_groups->get_membership('mem-uuid');
$client->number_groups->delete_membership('mem-uuid');
```

## Verified Caller IDs

```perl
my $callers = $client->verified_callers->list;
my $caller  = $client->verified_callers->create(phone_number => '+15551234567', name => 'Office');
$caller     = $client->verified_callers->get('vc-uuid');
$client->verified_callers->update('vc-uuid', name => 'Main Office');
$client->verified_callers->delete('vc-uuid');

# Verification flow
$client->verified_callers->redial_verification('vc-uuid');
$client->verified_callers->submit_verification('vc-uuid', verification_code => '123456');
```

## SIP Profile

Singleton resource -- no ID needed:

```perl
my $profile = $client->sip_profile->get;
$client->sip_profile->update(default_codecs => ['PCMU', 'PCMA']);
```

## Phone Number Lookup

```perl
my $info = $client->lookup->phone_number('+15551234567');
$info     = $client->lookup->phone_number('+15551234567', include => 'carrier,cnam');
```

Note: carrier and CNAM lookups are billable.

## Short Codes

```perl
my $codes = $client->short_codes->list;
my $code  = $client->short_codes->get('sc-uuid');
$client->short_codes->update('sc-uuid', name => 'Alerts');
```

## Imported Phone Numbers

```perl
$client->imported_numbers->create(number => '+15559999999', carrier => 'external');
```

## MFA (Multi-Factor Authentication)

```perl
# Request a verification code via SMS
my $result = $client->mfa->sms(
    to      => '+15551234567',
    from    => '+15559876543',
    message => 'Your code is {code}',
);
my $request_id = $result->{id};

# Or via phone call
$result = $client->mfa->call(
    to   => '+15551234567',
    from => '+15559876543',
);

# Verify the code
$result = $client->mfa->verify($request_id, token => '123456');
```

## 10DLC Campaign Registry

```perl
# Brands
my $brands = $client->registry->brands->list;
my $brand  = $client->registry->brands->create(name => 'My Brand', ein => '12-3456789');
$brand     = $client->registry->brands->get('brand-uuid');

# Campaigns under a brand
my $campaigns = $client->registry->brands->list_campaigns('brand-uuid');
my $campaign  = $client->registry->brands->create_campaign('brand-uuid', description => 'Alerts');

# Campaign management
$campaign = $client->registry->campaigns->get('camp-uuid');
$client->registry->campaigns->update('camp-uuid', description => 'Updated alerts');

# Number assignments
my $numbers = $client->registry->campaigns->list_numbers('camp-uuid');
my $orders  = $client->registry->campaigns->list_orders('camp-uuid');
my $order   = $client->registry->campaigns->create_order('camp-uuid', phone_number_ids => ['pn-1']);
$order      = $client->registry->orders->get('order-uuid');
$client->registry->numbers->delete('number-assignment-uuid');
```

## Datasphere

```perl
# Documents
my $docs = $client->datasphere->documents->list;
my $doc  = $client->datasphere->documents->create(
    url  => 'https://example.com/doc.pdf',
    tags => ['support'],
);
$doc = $client->datasphere->documents->get('doc-uuid');
$client->datasphere->documents->update('doc-uuid', tags => ['support', 'billing']);
$client->datasphere->documents->delete('doc-uuid');

# Semantic search
my $results = $client->datasphere->documents->search(
    query_string => 'How do I reset my password?',
    tags         => ['support'],
    count        => 5,
);

# Chunks
my $chunks = $client->datasphere->documents->list_chunks('doc-uuid');
my $chunk  = $client->datasphere->documents->get_chunk('doc-uuid', 'chunk-uuid');
$client->datasphere->documents->delete_chunk('doc-uuid', 'chunk-uuid');
```

## Video

```perl
# Rooms
my $rooms = $client->video->rooms->list;
my $room  = $client->video->rooms->create(name => 'standup', max_members => 10);
$room     = $client->video->rooms->get('room-uuid');
$client->video->rooms->update('room-uuid', max_members => 20);
$client->video->rooms->delete('room-uuid');
$client->video->rooms->list_streams('room-uuid');
$client->video->rooms->create_stream('room-uuid', url => 'rtmp://example.com/live');

# Room tokens
my $token = $client->video->room_tokens->create(room_name => 'standup', user_name => 'alice');

# Room sessions
my $sessions = $client->video->room_sessions->list(room_name => 'standup');
my $session  = $client->video->room_sessions->get('session-uuid');
my $events   = $client->video->room_sessions->list_events('session-uuid');
my $members  = $client->video->room_sessions->list_members('session-uuid');
my $recs     = $client->video->room_sessions->list_recordings('session-uuid');

# Room recordings
my $recordings = $client->video->room_recordings->list;
my $rec        = $client->video->room_recordings->get('rec-uuid');
$client->video->room_recordings->delete('rec-uuid');
$events = $client->video->room_recordings->list_events('rec-uuid');

# Conferences
my $confs = $client->video->conferences->list;
my $conf  = $client->video->conferences->create(name => 'all-hands', quality => '720p');
$conf     = $client->video->conferences->get('conf-uuid');
$client->video->conferences->update('conf-uuid', quality => '1080p');
$client->video->conferences->delete('conf-uuid');
my $tokens = $client->video->conferences->list_conference_tokens('conf-uuid');
$client->video->conferences->list_streams('conf-uuid');
$client->video->conferences->create_stream('conf-uuid', url => 'rtmp://example.com/live');

# Conference tokens
$token = $client->video->conference_tokens->get('token-uuid');
$client->video->conference_tokens->reset('token-uuid');

# Streams
my $stream = $client->video->streams->get('stream-uuid');
$client->video->streams->update('stream-uuid', url => 'rtmp://example.com/new');
$client->video->streams->delete('stream-uuid');
```

## Logs

All log endpoints are read-only.

```perl
# Message logs
my $logs = $client->logs->messages->list(include_deleted => 1);
my $log  = $client->logs->messages->get('log-uuid');

# Voice logs (with events)
$logs = $client->logs->voice->list;
$log  = $client->logs->voice->get('log-uuid');
my $events = $client->logs->voice->list_events('log-uuid');

# Fax logs
$logs = $client->logs->fax->list;
$log  = $client->logs->fax->get('log-uuid');

# Conference logs
$logs = $client->logs->conferences->list;
```

## Project Tokens

Reached via the `project_ns` accessor (the constructor already uses `project` for credentials):

```perl
my $token = $client->project_ns->tokens->create(
    name        => 'ci-token',
    permissions => ['calling', 'messaging', 'numbers'],
);
$client->project_ns->tokens->update('token-uuid', name => 'renamed-token');
$client->project_ns->tokens->delete('token-uuid');
```

## PubSub Tokens

```perl
my $token = $client->pubsub->create_token(
    ttl       => 60,
    channels  => [{ name => 'updates', read => 1, write => 0 }],
    member_id => 'user-123',
);
```

## Chat Tokens

```perl
my $token = $client->chat->create_token(
    ttl       => 60,
    channels  => [{ name => 'support', read => 1, write => 1 }],
    member_id => 'user-123',
);
```
