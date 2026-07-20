package SignalWire::REST::PhoneCallHandler;
use strict;
use warnings;

# PhoneCallHandler - enum of `call_handler` values accepted by phone_numbers->update.
#
# Named `PhoneCallHandler` (not `CallHandler`) to stay consistent with the other
# SignalWire ports and to avoid colliding with any RELAY client callback type.
#
# Setting a phone number's `call_handler` + the handler-specific companion
# field routes inbound calls and auto-materializes the matching Fabric
# resource on the server. See the high-level helpers on
# SignalWire::REST::Namespaces::PhoneNumbers.
#
# Each constant is a plain scalar, so passing the constant directly into
# phone_numbers->update(..., call_handler => PhoneCallHandler::RELAY_SCRIPT)
# serializes to the wire value without any indirection.
#
#   Constant             Wire value            Companion field            Auto-materializes
#   -------------------- --------------------- -------------------------- --------------------
#   RELAY_SCRIPT         relay_script          call_relay_script_url      swml_webhook
#   LAML_WEBHOOKS        laml_webhooks         call_request_url           cxml_webhook
#   LAML_APPLICATION     laml_application      call_laml_application_id   cxml_application
#   AI_AGENT             ai_agent              call_ai_agent_id           ai_agent
#   CALL_FLOW            call_flow             call_flow_id               call_flow
#   RELAY_APPLICATION    relay_application     call_relay_application     relay_application
#   RELAY_TOPIC          relay_topic           call_relay_topic           (routes via RELAY)
#   RELAY_CONTEXT        relay_context         call_relay_context         (legacy, prefer topic)
#   RELAY_CONNECTOR      relay_connector       (connector config)         (internal)
#   VIDEO_ROOM           video_room            call_video_room_id         (routes to Video API)
#   DIALOGFLOW           dialogflow            call_dialogflow_agent_id   (none)
#
# Note: LAML_WEBHOOKS (wire value "laml_webhooks") produces a cXML handler,
# not a generic webhook. For SWML, use RELAY_SCRIPT.

use Exporter 'import';

use constant {
    RELAY_SCRIPT      => 'relay_script',
    LAML_WEBHOOKS     => 'laml_webhooks',
    LAML_APPLICATION  => 'laml_application',
    AI_AGENT          => 'ai_agent',
    CALL_FLOW         => 'call_flow',
    RELAY_APPLICATION => 'relay_application',
    RELAY_TOPIC       => 'relay_topic',
    RELAY_CONTEXT     => 'relay_context',
    RELAY_CONNECTOR   => 'relay_connector',
    VIDEO_ROOM        => 'video_room',
    DIALOGFLOW        => 'dialogflow',
};

our @EXPORT_OK = qw(
    RELAY_SCRIPT
    LAML_WEBHOOKS
    LAML_APPLICATION
    AI_AGENT
    CALL_FLOW
    RELAY_APPLICATION
    RELAY_TOPIC
    RELAY_CONTEXT
    RELAY_CONNECTOR
    VIDEO_ROOM
    DIALOGFLOW
);

our %EXPORT_TAGS = ( all => \@EXPORT_OK );

# values() - return all 11 wire values (authoritative list).
sub values {
    return (
        RELAY_SCRIPT,    LAML_WEBHOOKS,     LAML_APPLICATION, AI_AGENT,
        CALL_FLOW,       RELAY_APPLICATION, RELAY_TOPIC,      RELAY_CONTEXT,
        RELAY_CONNECTOR, VIDEO_ROOM,        DIALOGFLOW,
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::REST::PhoneCallHandler - enum of C<call_handler> values for phone_numbers->update

=head1 SYNOPSIS

    use SignalWire::REST::PhoneCallHandler qw(RELAY_SCRIPT AI_AGENT);

    $client->phone_numbers->update(
        $number_id,
        call_handler          => RELAY_SCRIPT,
        call_relay_script_url => 'https://example.com/swml',
    );

    # All wire values:
    my @all = SignalWire::REST::PhoneCallHandler::values();

=head1 DESCRIPTION

L<SignalWire::REST::PhoneCallHandler> is the closed set of C<call_handler>
values accepted by C<< phone_numbers->update >>. Setting a phone number's
C<call_handler> plus its handler-specific companion field routes inbound
calls and auto-materializes the matching Fabric resource on the server.

It is named C<PhoneCallHandler> (not C<CallHandler>) to stay consistent
with the other SignalWire ports and to avoid colliding with a RELAY client
callback type. Each constant is a plain scalar equal to its wire value, so
passing it directly to C<update> serializes without indirection.

=head1 CONSTANTS

Each constant maps to a wire value and pairs with a companion field:

=over 4

=item RELAY_SCRIPT

C<relay_script> -- companion C<call_relay_script_url>; auto-materializes an
C<swml_webhook>. Use this for SWML.

=item LAML_WEBHOOKS

C<laml_webhooks> -- companion C<call_request_url>; auto-materializes a
C<cxml_webhook> (a cXML handler, not a generic webhook).

=item LAML_APPLICATION

C<laml_application> -- companion C<call_laml_application_id>;
auto-materializes a C<cxml_application>.

=item AI_AGENT

C<ai_agent> -- companion C<call_ai_agent_id>; auto-materializes an
C<ai_agent>.

=item CALL_FLOW

C<call_flow> -- companion C<call_flow_id>; auto-materializes a C<call_flow>.

=item RELAY_APPLICATION

C<relay_application> -- companion C<call_relay_application>;
auto-materializes a C<relay_application>.

=item RELAY_TOPIC

C<relay_topic> -- companion C<call_relay_topic>; routes via RELAY.

=item RELAY_CONTEXT

C<relay_context> -- companion C<call_relay_context> (legacy; prefer
C<RELAY_TOPIC>).

=item RELAY_CONNECTOR

C<relay_connector> -- connector config (internal).

=item VIDEO_ROOM

C<video_room> -- companion C<call_video_room_id>; routes to the Video API.

=item DIALOGFLOW

C<dialogflow> -- companion C<call_dialogflow_agent_id>.

=back

The constants are exportable individually or via the C<:all> tag.

=head1 FUNCTIONS

=over 4

=item values()

Return the list of all 11 wire values (the authoritative list).

=back

=head1 SEE ALSO

L<SignalWire::REST::RestClient>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
