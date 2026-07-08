#!/usr/bin/env perl
# enumerate_surface.pl — emit a JSON snapshot of the Perl SDK's public API in
# the same shape as the porting-sdk's python_surface.json.
#
# Layer B symbol-level surface audit: walk lib/SignalWire/**/*.pm, extract
# every `package Foo::Bar;` block and the `sub name {` declarations within
# it, then translate Perl-native names to Python-reference names so
# diff_port_surface.py can line up the two surfaces without false positives.
#
# Translation rules (see the task spec):
#   * package SignalWire::Agent::AgentBase   -> module signalwire.core.agent_base,
#                                               class AgentBase
#   * sub foo                                 -> method foo (already snake_case)
#   * sub new                                 -> method __init__
#   * sub _foo                                -> skipped (Perl convention: private)
#   * AgentBase in Perl is one big class, but Python splits it across mixins
#     (prompt/tool/ai_config/auth/skill/web/state/serverless/mcp_server).
#     The translation table below routes each Perl sub to the right Python
#     home so the diff is meaningful instead of noise.
#
# Usage:
#   perl scripts/enumerate_surface.pl                      # write port_surface.json
#   perl scripts/enumerate_surface.pl --output surface.json
#   perl scripts/enumerate_surface.pl --stdout             # dump to stdout
use strict;
use warnings;
use JSON         ();
use File::Find   ();
use File::Spec   ();
use Getopt::Long ();
use FindBin      ();

# -------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------

my $REPO_ROOT = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
my $LIB_ROOT  = File::Spec->catdir( $REPO_ROOT, 'lib', 'SignalWire' );

my $output_path = File::Spec->catfile( $REPO_ROOT, 'port_surface.json' );
my $to_stdout   = 0;
Getopt::Long::GetOptions(
    'output=s' => \$output_path,
    'stdout'   => \$to_stdout,
) or die "usage: $0 [--output PATH] [--stdout]\n";

# -------------------------------------------------------------------------
# Package -> Python module/class translation
# -------------------------------------------------------------------------
#
# For packages whose Perl-native layout matches a single Python module, this
# is a straight map. For AgentBase (a fat Moo class that Python splits into
# mixins) the mapping is per-method and handled below.
#
my %PACKAGE_TO_PY = (

    # Entry point (SignalWire.pm acts as the package-level loader)
    'SignalWire' => { module => 'signalwire', class => undef },

    # Core orchestration
    'SignalWire::Agent::AgentBase' =>
        { module => 'signalwire.core.agent_base', class => 'AgentBase' },
    'SignalWire::SWML::Service' =>
        { module => 'signalwire.core.swml_service', class => 'SWMLService' },
    'SignalWire::SWAIG::FunctionResult' =>
        { module => 'signalwire.core.function_result', class => 'FunctionResult' },

    # SWML/SWAIG standalone helper classes (Python reference factors these out
    # of the fat SWMLService). NOTE the reference renderer class is SwmlRenderer
    # (not SWMLRenderer), and the handler base class is SWMLVerbHandler.
    'SignalWire::SWAIG::SWAIGFunction' =>
        { module => 'signalwire.core.swaig_function', class => 'SWAIGFunction' },
    'SignalWire::SWML::SWMLBuilder' =>
        { module => 'signalwire.core.swml_builder', class => 'SWMLBuilder' },
    'SignalWire::SWML::SWMLHandler' =>
        { module => 'signalwire.core.swml_handler', class => 'SWMLVerbHandler' },
    'SignalWire::SWML::SWMLHandler::AIVerbHandler' =>
        { module => 'signalwire.core.swml_handler', class => 'AIVerbHandler' },
    'SignalWire::SWML::SWMLHandler::VerbHandlerRegistry' =>
        { module => 'signalwire.core.swml_handler', class => 'VerbHandlerRegistry' },
    'SignalWire::SWML::SWMLRenderer' =>
        { module => 'signalwire.core.swml_renderer', class => 'SwmlRenderer' },
    'SignalWire::Utils::SchemaUtils' =>
        { module => 'signalwire.utils.schema_utils', class => 'SchemaUtils' },
    'SignalWire::Utils::SchemaValidationError' =>
        { module => 'signalwire.utils.schema_utils', class => 'SchemaValidationError' },
    'SignalWire::DataMap' => { module => 'signalwire.core.data_map', class => 'DataMap' },
    'SignalWire::Security::SessionManager' =>
        { module => 'signalwire.core.security.session_manager', class => 'SessionManager' },
    'SignalWire::Security::WebhookValidator' =>
        { module => 'signalwire.core.security.webhook_validator', class => undef },
    'SignalWire::Security::WebhookMiddleware' =>
        { module => 'signalwire.core.security.webhook_middleware', class => undef },
    'SignalWire::Security::SecurityUtils' =>
        { module => 'signalwire.core.security.security_utils', class => undef },
    'SignalWire::Server::AgentServer' =>
        { module => 'signalwire.agent_server', class => 'AgentServer' },
    'SignalWire::Logging' => { module => 'signalwire.core.logging_config', class => undef },
    'SignalWire::Core::LoggingConfig' =>
        { module => 'signalwire.core.logging_config', class => undef },

    # Standalone core helpers (cluster A)
    'SignalWire::Core::PomBuilder' =>
        { module => 'signalwire.core.pom_builder', class => 'PomBuilder' },
    'SignalWire::Core::ConfigLoader' =>
        { module => 'signalwire.core.config_loader', class => 'ConfigLoader' },
    'SignalWire::Core::SecurityConfig' =>
        { module => 'signalwire.core.security_config', class => 'SecurityConfig' },
    'SignalWire::Core::AuthHandler' =>
        { module => 'signalwire.core.auth_handler', class => 'AuthHandler' },
    'SignalWire::Utils'               => { module => 'signalwire.utils', class => undef },
    'SignalWire::Utils::UrlValidator' =>
        { module => 'signalwire.utils.url_validator', class => undef },

    # Contexts (multiple classes in one .pm)
    'SignalWire::Contexts'          => { module => 'signalwire.core.contexts', class => undef },
    'SignalWire::Contexts::Context' => { module => 'signalwire.core.contexts', class => 'Context' },
    'SignalWire::Contexts::ContextBuilder' =>
        { module => 'signalwire.core.contexts', class => 'ContextBuilder' },
    'SignalWire::Contexts::GatherInfo' =>
        { module => 'signalwire.core.contexts', class => 'GatherInfo' },
    'SignalWire::Contexts::GatherQuestion' =>
        { module => 'signalwire.core.contexts', class => 'GatherQuestion' },
    'SignalWire::Contexts::Step' => { module => 'signalwire.core.contexts', class => 'Step' },

    # Skills
    'SignalWire::Skills::SkillBase' =>
        { module => 'signalwire.core.skill_base', class => 'SkillBase' },
    'SignalWire::Skills::SkillManager' =>
        { module => 'signalwire.core.skill_manager', class => 'SkillManager' },
    'SignalWire::Skills::SkillRegistry' =>
        { module => 'signalwire.skills.registry', class => 'SkillRegistry' },

    # Built-in skills: each Perl package maps to the equivalent
    # signalwire.skills.<name>.skill module + Skill class.
    'SignalWire::Skills::Builtin::Datetime' =>
        { module => 'signalwire.skills.datetime.skill', class => 'DateTimeSkill' },
    'SignalWire::Skills::Builtin::Math' =>
        { module => 'signalwire.skills.math.skill', class => 'MathSkill' },
    'SignalWire::Skills::Builtin::WebSearch' =>
        { module => 'signalwire.skills.web_search.skill', class => 'WebSearchSkill' },
    'SignalWire::Skills::Builtin::WikipediaSearch' =>
        { module => 'signalwire.skills.wikipedia_search.skill', class => 'WikipediaSearchSkill' },
    'SignalWire::Skills::Builtin::WeatherApi' =>
        { module => 'signalwire.skills.weather_api.skill', class => 'WeatherApiSkill' },
    'SignalWire::Skills::Builtin::Joke' =>
        { module => 'signalwire.skills.joke.skill', class => 'JokeSkill' },
    'SignalWire::Skills::Builtin::Spider' =>
        { module => 'signalwire.skills.spider.skill', class => 'SpiderSkill' },
    'SignalWire::Skills::Builtin::Datasphere' =>
        { module => 'signalwire.skills.datasphere.skill', class => 'DataSphereSkill' },
    'SignalWire::Skills::Builtin::DatasphereServerless' => {
        module => 'signalwire.skills.datasphere_serverless.skill',
        class  => 'DataSphereServerlessSkill'
    },
    'SignalWire::Skills::Builtin::ApiNinjasTrivia' =>
        { module => 'signalwire.skills.api_ninjas_trivia.skill', class => 'ApiNinjasTriviaSkill' },
    'SignalWire::Skills::Builtin::SwmlTransfer' =>
        { module => 'signalwire.skills.swml_transfer.skill', class => 'SWMLTransferSkill' },
    'SignalWire::Skills::Builtin::GoogleMaps' =>
        { module => 'signalwire.skills.google_maps.skill', class => 'GoogleMapsSkill' },
    'SignalWire::Skills::Builtin::PlayBackgroundFile' => {
        module => 'signalwire.skills.play_background_file.skill',
        class  => 'PlayBackgroundFileSkill'
    },
    'SignalWire::Skills::Builtin::InfoGatherer' =>
        { module => 'signalwire.skills.info_gatherer.skill', class => 'InfoGathererSkill' },
    'SignalWire::Skills::Builtin::ClaudeSkills' =>
        { module => 'signalwire.skills.claude_skills.skill', class => 'ClaudeSkillsSkill' },
    'SignalWire::Skills::Builtin::NativeVectorSearch' => {
        module => 'signalwire.skills.native_vector_search.skill',
        class  => 'NativeVectorSearchSkill'
    },

    # CustomSkills has no direct Python equivalent — it's a Perl-only harness
    # for loading user-supplied skill packages. Report it under the registry
    # namespace with a port-only class; it will surface in PORT_ADDITIONS.md.
    'SignalWire::Skills::Builtin::CustomSkills' =>
        { module => 'signalwire.skills.registry', class => 'CustomSkills' },

    # Agent internals (Python splits AgentBase into standalone core helpers)
    'SignalWire::Core::Agent::Prompt::Manager' =>
        { module => 'signalwire.core.agent.prompt.manager', class => 'PromptManager' },
    'SignalWire::Core::Agent::Tools::Registry' =>
        { module => 'signalwire.core.agent.tools.registry', class => 'ToolRegistry' },
    'SignalWire::Core::Agent::Tools::TypeInference' =>
        { module => 'signalwire.core.agent.tools.type_inference', class => undef },

    # Bedrock agent (extends AgentBase; only its OWN subs are enumerated)
    'SignalWire::Agents::Bedrock' =>
        { module => 'signalwire.agents.bedrock', class => 'BedrockAgent' },

    # Static file web service
    'SignalWire::Web::WebService' =>
        { module => 'signalwire.web.web_service', class => 'WebService' },

    # Prefabs
    'SignalWire::Prefabs::Concierge' =>
        { module => 'signalwire.prefabs.concierge', class => 'ConciergeAgent' },
    'SignalWire::Prefabs::FAQBot' =>
        { module => 'signalwire.prefabs.faq_bot', class => 'FAQBotAgent' },
    'SignalWire::Prefabs::InfoGatherer' =>
        { module => 'signalwire.prefabs.info_gatherer', class => 'InfoGathererAgent' },
    'SignalWire::Prefabs::Receptionist' =>
        { module => 'signalwire.prefabs.receptionist', class => 'ReceptionistAgent' },
    'SignalWire::Prefabs::Survey' =>
        { module => 'signalwire.prefabs.survey', class => 'SurveyAgent' },

    # RELAY client
    'SignalWire::Relay::Client'  => { module => 'signalwire.relay.client', class => 'RelayClient' },
    'SignalWire::Relay::Call'    => { module => 'signalwire.relay.call',   class => 'Call' },
    'SignalWire::Relay::Message' => { module => 'signalwire.relay.message', class => 'Message' },
    'SignalWire::Relay::Action'  => { module => 'signalwire.relay.call',    class => 'Action' },
    'SignalWire::Relay::Action::AI' => { module => 'signalwire.relay.call', class => 'AIAction' },
    'SignalWire::Relay::Action::Collect' =>
        { module => 'signalwire.relay.call', class => 'CollectAction' },
    'SignalWire::Relay::Action::StandaloneCollect' =>
        { module => 'signalwire.relay.call', class => 'StandaloneCollectAction' },
    'SignalWire::Relay::Action::Detect' =>
        { module => 'signalwire.relay.call', class => 'DetectAction' },
    'SignalWire::Relay::Action::Fax' => { module => 'signalwire.relay.call', class => 'FaxAction' },
    'SignalWire::Relay::Action::Pay' => { module => 'signalwire.relay.call', class => 'PayAction' },
    'SignalWire::Relay::Action::Play' =>
        { module => 'signalwire.relay.call', class => 'PlayAction' },
    'SignalWire::Relay::Action::Record' =>
        { module => 'signalwire.relay.call', class => 'RecordAction' },
    'SignalWire::Relay::Action::Stream' =>
        { module => 'signalwire.relay.call', class => 'StreamAction' },
    'SignalWire::Relay::Action::Tap' => { module => 'signalwire.relay.call', class => 'TapAction' },
    'SignalWire::Relay::Action::Transcribe' =>
        { module => 'signalwire.relay.call', class => 'TranscribeAction' },
    'SignalWire::Relay::Event' => { module => 'signalwire.relay.event', class => 'RelayEvent' },
    'SignalWire::Relay::Event::CallState' =>
        { module => 'signalwire.relay.event', class => 'CallStateEvent' },
    'SignalWire::Relay::Event::CallReceive' =>
        { module => 'signalwire.relay.event', class => 'CallReceiveEvent' },
    'SignalWire::Relay::Event::CallDial' =>
        { module => 'signalwire.relay.event', class => 'DialEvent' },
    'SignalWire::Relay::Event::CallConnect' =>
        { module => 'signalwire.relay.event', class => 'ConnectEvent' },
    'SignalWire::Relay::Event::CallPlay' =>
        { module => 'signalwire.relay.event', class => 'PlayEvent' },
    'SignalWire::Relay::Event::CallRecord' =>
        { module => 'signalwire.relay.event', class => 'RecordEvent' },
    'SignalWire::Relay::Event::CallCollect' =>
        { module => 'signalwire.relay.event', class => 'CollectEvent' },
    'SignalWire::Relay::Event::CallDetect' =>
        { module => 'signalwire.relay.event', class => 'DetectEvent' },
    'SignalWire::Relay::Event::CallFax' =>
        { module => 'signalwire.relay.event', class => 'FaxEvent' },
    'SignalWire::Relay::Event::CallTap' =>
        { module => 'signalwire.relay.event', class => 'TapEvent' },
    'SignalWire::Relay::Event::CallStream' =>
        { module => 'signalwire.relay.event', class => 'StreamEvent' },
    'SignalWire::Relay::Event::CallTranscribe' =>
        { module => 'signalwire.relay.event', class => 'TranscribeEvent' },
    'SignalWire::Relay::Event::CallPay' =>
        { module => 'signalwire.relay.event', class => 'PayEvent' },
    'SignalWire::Relay::Event::CallSendDigits' =>
        { module => 'signalwire.relay.event', class => 'SendDigitsEvent' },
    'SignalWire::Relay::Event::CallRefer' =>
        { module => 'signalwire.relay.event', class => 'ReferEvent' },
    'SignalWire::Relay::Event::Conference' =>
        { module => 'signalwire.relay.event', class => 'ConferenceEvent' },
    'SignalWire::Relay::Event::CallAI' =>
        { module => 'signalwire.relay.event', class => 'CallingErrorEvent' },
    'SignalWire::Relay::Event::CallDenoise' =>
        { module => 'signalwire.relay.event', class => 'DenoiseEvent' },
    'SignalWire::Relay::Event::CallEcho' =>
        { module => 'signalwire.relay.event', class => 'EchoEvent' },
    'SignalWire::Relay::Event::CallHold' =>
        { module => 'signalwire.relay.event', class => 'HoldEvent' },
    'SignalWire::Relay::Event::CallQueue' =>
        { module => 'signalwire.relay.event', class => 'QueueEvent' },
    'SignalWire::Relay::Event::MessageReceive' =>
        { module => 'signalwire.relay.event', class => 'MessageReceiveEvent' },
    'SignalWire::Relay::Event::MessageState' =>
        { module => 'signalwire.relay.event', class => 'MessageStateEvent' },

    # Perl-only events: CallDisconnect, Conference subtypes, Authorization,
    # plain Disconnect. Routed to relay.event so they surface in PORT_ADDITIONS.
    'SignalWire::Relay::Event::CallDisconnect' =>
        { module => 'signalwire.relay.event', class => 'CallDisconnectEvent' },
    'SignalWire::Relay::Event::AuthorizationState' =>
        { module => 'signalwire.relay.event', class => 'AuthorizationStateEvent' },
    'SignalWire::Relay::Event::Disconnect' =>
        { module => 'signalwire.relay.event', class => 'DisconnectEvent' },
    'SignalWire::Relay::Constants' => { module => 'signalwire.relay.client', class => 'Constants' },
    'SignalWire::Relay::Client::RelayError' =>
        { module => 'signalwire.relay.client', class => 'RelayError' },

    # REST client
    'SignalWire::REST::RestClient' => { module => 'signalwire.rest.client', class => 'RestClient' },
    'SignalWire::REST::HttpClient' => { module => 'signalwire.rest._base',  class => 'HttpClient' },
    'SignalWire::REST::HttpClient::Error' =>
        { module => 'signalwire.rest._base', class => 'SignalWireRestError' },
    'SignalWire::REST::Namespaces::Base' =>
        { module => 'signalwire.rest._base', class => 'BaseResource' },
    'SignalWire::REST::Namespaces::CrudResource' =>
        { module => 'signalwire.rest._base', class => 'CrudResource' },

    # PhoneCallHandler is the `call_handler` value enum used by
    # phone_numbers->update / the set_* helpers. In the REST-generated oracle
    # layout it lives as a TYPE under the relay-rest generated types module.
    'SignalWire::REST::PhoneCallHandler' => {
        module => 'signalwire.rest.namespaces.relay_rest_types_generated',
        class  => 'PhoneCallHandler'
    },
    'SignalWire::REST::Pagination' => { module => 'signalwire.rest._pagination', class => undef },
    'SignalWire::REST::Pagination::PaginatedIterator' =>
        { module => 'signalwire.rest._pagination', class => 'PaginatedIterator' },

    # REST: simple namespaces
    'SignalWire::REST::Namespaces::Calling' =>
        { module => 'signalwire.rest.namespaces.calling', class => 'CallingNamespace' },
    'SignalWire::REST::Namespaces::Chat' =>
        { module => 'signalwire.rest.namespaces.chat', class => 'ChatResource' },
    'SignalWire::REST::Namespaces::PubSub' =>
        { module => 'signalwire.rest.namespaces.pubsub', class => 'PubSubResource' },
    'SignalWire::REST::Namespaces::PhoneNumbers' =>
        { module => 'signalwire.rest.namespaces.phone_numbers', class => 'PhoneNumbersResource' },
    'SignalWire::REST::Namespaces::Datasphere' =>
        { module => 'signalwire.rest.namespaces.datasphere', class => 'DatasphereNamespace' },
    'SignalWire::REST::Namespaces::Datasphere::Documents' =>
        { module => 'signalwire.rest.namespaces.datasphere', class => 'DatasphereDocuments' },
    'SignalWire::REST::Namespaces::Project' =>
        { module => 'signalwire.rest.namespaces.project', class => 'ProjectNamespace' },
    'SignalWire::REST::Namespaces::Project::Tokens' =>
        { module => 'signalwire.rest.namespaces.project', class => 'ProjectTokens' },

    # REST: multi-package Resources.pm splits into several namespaces
    'SignalWire::REST::Namespaces::Resources' =>
        { module => 'signalwire.rest._base', class => undef },
    'SignalWire::REST::Namespaces::Addresses' =>
        { module => 'signalwire.rest.namespaces.addresses', class => 'AddressesResource' },
    'SignalWire::REST::Namespaces::Queues' =>
        { module => 'signalwire.rest.namespaces.queues', class => 'QueuesResource' },
    'SignalWire::REST::Namespaces::Recordings' =>
        { module => 'signalwire.rest.namespaces.recordings', class => 'RecordingsResource' },
    'SignalWire::REST::Namespaces::NumberGroups' =>
        { module => 'signalwire.rest.namespaces.number_groups', class => 'NumberGroupsResource' },
    'SignalWire::REST::Namespaces::VerifiedCallers' => {
        module => 'signalwire.rest.namespaces.verified_callers',
        class  => 'VerifiedCallersResource'
    },
    'SignalWire::REST::Namespaces::SipProfile' =>
        { module => 'signalwire.rest.namespaces.sip_profile', class => 'SipProfileResource' },
    'SignalWire::REST::Namespaces::Lookup' =>
        { module => 'signalwire.rest.namespaces.lookup', class => 'LookupResource' },
    'SignalWire::REST::Namespaces::ShortCodes' =>
        { module => 'signalwire.rest.namespaces.short_codes', class => 'ShortCodesResource' },
    'SignalWire::REST::Namespaces::ImportedNumbers' => {
        module => 'signalwire.rest.namespaces.imported_numbers',
        class  => 'ImportedNumbersResource'
    },
    'SignalWire::REST::Namespaces::MFA' =>
        { module => 'signalwire.rest.namespaces.mfa', class => 'MfaResource' },

    # REST: Logs.pm — multi-package
    'SignalWire::REST::Namespaces::Logs' =>
        { module => 'signalwire.rest.namespaces.logs', class => 'LogsNamespace' },
    'SignalWire::REST::Namespaces::Logs::Messages' =>
        { module => 'signalwire.rest.namespaces.logs', class => 'MessageLogs' },
    'SignalWire::REST::Namespaces::Logs::Voice' =>
        { module => 'signalwire.rest.namespaces.logs', class => 'VoiceLogs' },
    'SignalWire::REST::Namespaces::Logs::Fax' =>
        { module => 'signalwire.rest.namespaces.logs', class => 'FaxLogs' },
    'SignalWire::REST::Namespaces::Logs::Conferences' =>
        { module => 'signalwire.rest.namespaces.logs', class => 'ConferenceLogs' },

    # REST: Registry.pm — multi-package
    'SignalWire::REST::Namespaces::Registry' =>
        { module => 'signalwire.rest.namespaces.registry', class => 'RegistryNamespace' },
    'SignalWire::REST::Namespaces::Registry::Brands' =>
        { module => 'signalwire.rest.namespaces.registry', class => 'RegistryBrands' },
    'SignalWire::REST::Namespaces::Registry::Campaigns' =>
        { module => 'signalwire.rest.namespaces.registry', class => 'RegistryCampaigns' },
    'SignalWire::REST::Namespaces::Registry::Orders' =>
        { module => 'signalwire.rest.namespaces.registry', class => 'RegistryOrders' },
    'SignalWire::REST::Namespaces::Registry::Numbers' =>
        { module => 'signalwire.rest.namespaces.registry', class => 'RegistryNumbers' },

    # REST: Compat.pm — multi-package
    'SignalWire::REST::Namespaces::Compat' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatNamespace' },
    'SignalWire::REST::Namespaces::Compat::Accounts' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatAccounts' },
    'SignalWire::REST::Namespaces::Compat::Calls' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatCalls' },
    'SignalWire::REST::Namespaces::Compat::Messages' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatMessages' },
    'SignalWire::REST::Namespaces::Compat::Faxes' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatFaxes' },
    'SignalWire::REST::Namespaces::Compat::Conferences' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatConferences' },
    'SignalWire::REST::Namespaces::Compat::PhoneNumbers' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatPhoneNumbers' },
    'SignalWire::REST::Namespaces::Compat::Applications' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatApplications' },
    'SignalWire::REST::Namespaces::Compat::LamlBins' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatLamlBins' },
    'SignalWire::REST::Namespaces::Compat::Queues' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatQueues' },
    'SignalWire::REST::Namespaces::Compat::Recordings' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatRecordings' },
    'SignalWire::REST::Namespaces::Compat::Transcriptions' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatTranscriptions' },
    'SignalWire::REST::Namespaces::Compat::Tokens' =>
        { module => 'signalwire.rest.namespaces.compat', class => 'CompatTokens' },

    # REST: Fabric.pm — multi-package (Python surface under rest.namespaces.fabric)
    'SignalWire::REST::Namespaces::Fabric' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'FabricNamespace' },
    'SignalWire::REST::Namespaces::Fabric::Addresses' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'FabricAddresses' },
    'SignalWire::REST::Namespaces::Fabric::Subscribers' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'SubscribersResource' },
    'SignalWire::REST::Namespaces::Fabric::Tokens' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'FabricTokens' },
    'SignalWire::REST::Namespaces::Fabric::GenericResources' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'GenericResources' },
    'SignalWire::REST::Namespaces::Fabric::SwmlWebhooks' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'SwmlWebhooksResource' },

    # Other Fabric::* subpackages are helpers that have no 1:1 Python
    # equivalent; they'll land in PORT_ADDITIONS.md under rest.namespaces.fabric.
    'SignalWire::REST::Namespaces::Fabric::Resource' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'FabricResource' },
    'SignalWire::REST::Namespaces::Fabric::AutoMaterializedWebhook' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'AutoMaterializedWebhook' },
    'SignalWire::REST::Namespaces::Fabric::CxmlWebhooks' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'CxmlWebhooksResource' },
    'SignalWire::REST::Namespaces::Fabric::ResourcePUT' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'FabricResourcePUT' },
    'SignalWire::REST::Namespaces::Fabric::CallFlows' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'CallFlowsResource' },
    'SignalWire::REST::Namespaces::Fabric::ConferenceRooms' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'ConferenceRoomsResource' },
    'SignalWire::REST::Namespaces::Fabric::CxmlApplications' =>
        { module => 'signalwire.rest.namespaces.fabric', class => 'CxmlApplicationsResource' },

    # REST: Video.pm — multi-package
    'SignalWire::REST::Namespaces::Video' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoNamespace' },
    'SignalWire::REST::Namespaces::Video::Rooms' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoRooms' },
    'SignalWire::REST::Namespaces::Video::RoomTokens' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoRoomTokens' },
    'SignalWire::REST::Namespaces::Video::RoomSessions' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoRoomSessions' },
    'SignalWire::REST::Namespaces::Video::RoomRecordings' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoRoomRecordings' },
    'SignalWire::REST::Namespaces::Video::Conferences' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoConferences' },
    'SignalWire::REST::Namespaces::Video::ConferenceTokens' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoConferenceTokens' },
    'SignalWire::REST::Namespaces::Video::Streams' =>
        { module => 'signalwire.rest.namespaces.video', class => 'VideoStreams' },

    # SWML
    'SignalWire::SWML::Document' =>
        { module => 'signalwire.core.swml_builder', class => 'SWMLBuilder' },
    'SignalWire::SWML::Schema' =>
        { module => 'signalwire.utils.schema_utils', class => 'SchemaUtils' },

    # POM — typed Prompt Object Model. Python lives in ``signalwire.pom.pom``;
    # Perl mirrors the same shape under ``SignalWire::POM::*`` and projects
    # both classes back to the canonical Python paths.
    'SignalWire::POM::PromptObjectModel' =>
        { module => 'signalwire.pom.pom', class => 'PromptObjectModel' },
    'SignalWire::POM::Section' => { module => 'signalwire.pom.pom', class => 'Section' },
);

# -------------------------------------------------------------------------
# Generated REST resource-tree projection (item B).
#
# The REST resource + client-tree surface is GENERATED (scripts/generate_rest.py
# emits lib/SignalWire/REST/Namespaces/Generated/*.pm — one package per resource
# class, one container per namespace group, plus the ReadResource/FabricResource
# bases and the ResourceTree role). Each generated package
# `SignalWire::REST::Namespaces::Generated::<Name>` projects VERBATIM onto the
# Python oracle module `signalwire.rest.namespaces.<ns>_resources_generated.<Name>`
# (the 6 containers onto `signalwire.rest.namespaces._client_tree_generated`).
#
# Perl's generated classes inherit CRUD from the hand base
# (Namespaces::CrudResource) + the generated ReadResource/FabricResource bases; the
# oracle records each class's SURFACE as its own declared methods PLUS a fixed base
# contribution. So we project each generated class's own subs and add the
# base-provided methods the oracle SURFACE lists on the subclass:
#
#   base=Base            -> (nothing; every method is spelled out inline)
#   base=CrudResource    -> create, update  (delete inherited but omitted on the
#                                             surface — the "delete-recording
#                                             asymmetry"; present in the signature
#                                             oracle, projected there, not here)
#   base=FabricResource  -> create, update  (delete NOT projected — same asymmetry)
#   base=ReadResource    -> (nothing on surface; get/list inherited but omitted)
#
# Mirrors php's/go's generated projection. GEN-FRESH keeps the emitted classes in
# sync with the specs; diff_port_surface keeps THIS table in sync with the oracle
# (a missing/renamed class fails the surface diff loudly).
my %GENERATED_PROJECTION = (
    'Addresses'             => { ns => 'relay_rest',   base => 'Base' },
    'AiAgents'              => { ns => 'fabric',       base => 'FabricResource' },
    'CallFlows'             => { ns => 'fabric',       base => 'FabricResource' },
    'Calling'               => { ns => 'calling',      base => 'Base' },
    'Chat'                  => { ns => 'chat',         base => 'Base' },
    'ConferenceLogs'        => { ns => 'logs',         base => 'Base' },
    'ConferenceRooms'       => { ns => 'fabric',       base => 'FabricResource' },
    'CxmlApplications'      => { ns => 'fabric',       base => 'Base' },
    'CxmlScripts'           => { ns => 'fabric',       base => 'FabricResource' },
    'CxmlWebhooks'          => { ns => 'fabric',       base => 'FabricResource' },
    'DatasphereDocuments'   => { ns => 'datasphere',   base => 'CrudResource' },
    'DatasphereNamespace'   => { ns => '_client_tree', base => 'Base' },
    'FabricAddresses'       => { ns => 'fabric',       base => 'ReadResource' },
    'FabricNamespace'       => { ns => '_client_tree', base => 'Base' },
    'FabricTokens'          => { ns => 'fabric',       base => 'Base' },
    'FaxLogs'               => { ns => 'fax',          base => 'ReadResource' },
    'FreeswitchConnectors'  => { ns => 'fabric',       base => 'FabricResource' },
    'GenericResources'      => { ns => 'fabric',       base => 'Base' },
    'ImportedNumbers'       => { ns => 'relay_rest',   base => 'Base' },
    'LogsNamespace'         => { ns => '_client_tree', base => 'Base' },
    'Lookup'                => { ns => 'relay_rest',   base => 'Base' },
    'MessageLogs'           => { ns => 'message',      base => 'ReadResource' },
    'Mfa'                   => { ns => 'relay_rest',   base => 'Base' },
    'NumberGroups'          => { ns => 'relay_rest',   base => 'CrudResource' },
    'PhoneNumbers'          => { ns => 'relay_rest',   base => 'CrudResource' },
    'ProjectNamespace'      => { ns => '_client_tree', base => 'Base' },
    'ProjectTokens'         => { ns => 'project',      base => 'Base' },
    'PubSub'                => { ns => 'pubsub',       base => 'Base' },
    'Queues'                => { ns => 'relay_rest',   base => 'CrudResource' },
    'Recordings'            => { ns => 'relay_rest',   base => 'Base' },
    'RegistryBrands'        => { ns => 'relay_rest',   base => 'Base' },
    'RegistryCampaigns'     => { ns => 'relay_rest',   base => 'Base' },
    'RegistryNamespace'     => { ns => '_client_tree', base => 'Base' },
    'RegistryNumbers'       => { ns => 'relay_rest',   base => 'Base' },
    'RegistryOrders'        => { ns => 'relay_rest',   base => 'Base' },
    'RelayApplications'     => { ns => 'fabric',       base => 'FabricResource' },
    'ShortCodes'            => { ns => 'relay_rest',   base => 'Base' },
    'SipEndpoints'          => { ns => 'fabric',       base => 'FabricResource' },
    'SipGateways'           => { ns => 'fabric',       base => 'FabricResource' },
    'SipProfile'            => { ns => 'relay_rest',   base => 'Base' },
    'Subscribers'           => { ns => 'fabric',       base => 'FabricResource' },
    'SwmlScripts'           => { ns => 'fabric',       base => 'FabricResource' },
    'SwmlWebhooks'          => { ns => 'fabric',       base => 'FabricResource' },
    'VerifiedCallers'       => { ns => 'relay_rest',   base => 'CrudResource' },
    'VideoConferenceTokens' => { ns => 'video',        base => 'Base' },
    'VideoConferences'      => { ns => 'video',        base => 'CrudResource' },
    'VideoNamespace'        => { ns => '_client_tree', base => 'Base' },
    'VideoRoomRecordings'   => { ns => 'video',        base => 'Base' },
    'VideoRoomSessions'     => { ns => 'video',        base => 'ReadResource' },
    'VideoRoomTokens'       => { ns => 'video',        base => 'Base' },
    'VideoRooms'            => { ns => 'video',        base => 'CrudResource' },
    'VideoStreams'          => { ns => 'video',        base => 'Base' },
    'VoiceLogs'             => { ns => 'voice',        base => 'ReadResource' },
);

# Base-provided methods the oracle SURFACE lists on a generated subclass.
my %GENERATED_BASE_SURFACE = (
    'Base'           => [],
    'CrudResource'   => [ 'create', 'update' ],
    'FabricResource' => [ 'create', 'update' ],
    'ReadResource'   => [],
);

# -------------------------------------------------------------------------
# Generated read-side TYPE modules (item D / A-H) — path-routed.
#
# generate_rest.py emits one method-less Moo data package per components/schemas
# object into lib/.../Generated/Types/<Sub>/<TypeName>.pm. The type leaf recurs
# across namespaces (DataMap / Document / Section / Types_StatusCodes_*), so we
# route each such file by its <Sub> PATH segment to the oracle
# signalwire.rest.namespaces.<ns>_types_generated module — path routing WINS over
# any name-keyed package map (a bare-leaf map would cross-contaminate with the SDK
# builder classes of the same name). Each type surfaces as a method-less class
# (Moo `has` accessors are not `sub` decls, so parse_file records zero subs).
# Scoped strictly to the Types/<Sub>/ subtree so no other package leaks.
my %TYPE_SUBDIR_NS = (
    'RelayRest'    => 'relay_rest',
    'Fabric'       => 'fabric',
    'Calling'      => 'calling',
    'Video'        => 'video',
    'Datasphere'   => 'datasphere',
    'Logs'         => 'logs',
    'Message'      => 'message',
    'Voice'        => 'voice',
    'Fax'          => 'fax',
    'Project'      => 'project',
    'Chat'         => 'chat',
    'PubSub'       => 'pubsub',
    'SwmlWebhooks' => 'swml_webhooks',
);

# -------------------------------------------------------------------------
# AgentBase method -> Python module/class router.
#
# In the Python SDK, AgentBase inherits from many mixins. Each mixin owns a
# slice of the public API. The Perl port flattens all of this into one
# SignalWire::Agent::AgentBase package, so at enumeration time we must
# re-project each method onto its Python home. This is the only way the
# diff tool can reason about surface parity.
# -------------------------------------------------------------------------
my %AGENTBASE_METHOD_TO_PY = (

    # Stays on AgentBase itself
    'new' => { module => 'signalwire.core.agent_base', class => 'AgentBase', method => '__init__' },
    'get_name' =>
        { module => 'signalwire.core.agent_base', class => 'AgentBase', method => 'get_name' },
    'get_full_url' =>
        { module => 'signalwire.core.agent_base', class => 'AgentBase', method => 'get_full_url' },
    'set_web_hook_url' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'set_web_hook_url'
    },
    'set_post_prompt_url' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'set_post_prompt_url'
    },
    'add_pre_answer_verb' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'add_pre_answer_verb'
    },
    'add_post_answer_verb' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'add_post_answer_verb'
    },
    'add_post_ai_verb' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'add_post_ai_verb'
    },
    'clear_pre_answer_verbs' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'clear_pre_answer_verbs'
    },
    'clear_post_answer_verbs' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'clear_post_answer_verbs'
    },
    'clear_post_ai_verbs' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'clear_post_ai_verbs'
    },
    'add_swaig_query_params' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'add_swaig_query_params'
    },
    'clear_swaig_query_params' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'clear_swaig_query_params'
    },
    'on_summary' =>
        { module => 'signalwire.core.agent_base', class => 'AgentBase', method => 'on_summary' },
    'on_debug_event' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'on_debug_event'
    },
    'enable_sip_routing' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'enable_sip_routing'
    },
    'register_sip_username' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'register_sip_username'
    },
    'auto_map_sip_usernames' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'auto_map_sip_usernames'
    },
    'add_answer_verb' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'add_answer_verb'
    },

    # PromptMixin
    'set_prompt_text' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'set_prompt_text'
    },
    'set_post_prompt' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'set_post_prompt'
    },
    'prompt_add_section' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'prompt_add_section'
    },
    'prompt_add_subsection' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'prompt_add_subsection'
    },
    'prompt_add_to_section' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'prompt_add_to_section'
    },
    'prompt_has_section' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'prompt_has_section'
    },
    'get_prompt' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'get_prompt'
    },
    'define_contexts' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'define_contexts'
    },
    'reset_contexts' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'reset_contexts'
    },
    'contexts' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'contexts'
    },

    # ToolMixin
    'define_tool' => {
        module => 'signalwire.core.mixins.tool_mixin',
        class  => 'ToolMixin',
        method => 'define_tool'
    },
    'register_swaig_function' => {
        module => 'signalwire.core.mixins.tool_mixin',
        class  => 'ToolMixin',
        method => 'register_swaig_function'
    },
    'define_tools' => {
        module => 'signalwire.core.mixins.tool_mixin',
        class  => 'ToolMixin',
        method => 'define_tools'
    },
    'on_function_call' => {
        module => 'signalwire.core.mixins.tool_mixin',
        class  => 'ToolMixin',
        method => 'on_function_call'
    },

    # AIConfigMixin
    'add_hint' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_hint'
    },
    'add_hints' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_hints'
    },
    'add_pattern_hint' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_pattern_hint'
    },
    'add_language' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_language'
    },
    'set_languages' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_languages'
    },
    'get_language_params' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'get_language_params'
    },
    'set_language_params' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_language_params'
    },
    'add_pronunciation' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_pronunciation'
    },
    'set_pronunciations' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_pronunciations'
    },
    'set_param' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_param'
    },
    'set_params' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_params'
    },
    'set_global_data' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_global_data'
    },
    'update_global_data' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'update_global_data'
    },
    'set_native_functions' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_native_functions'
    },
    'set_internal_fillers' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_internal_fillers'
    },
    'add_internal_filler' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_internal_filler'
    },
    'enable_debug_events' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'enable_debug_events'
    },
    'add_function_include' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_function_include'
    },
    'set_function_includes' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_function_includes'
    },
    'set_prompt_llm_params' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_prompt_llm_params'
    },
    'set_post_prompt_llm_params' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_post_prompt_llm_params'
    },
    'set_multilingual' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'set_multilingual'
    },
    'add_mcp_server' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'add_mcp_server'
    },
    'enable_mcp_server' => {
        module => 'signalwire.core.mixins.ai_config_mixin',
        class  => 'AIConfigMixin',
        method => 'enable_mcp_server'
    },

    # AgentBase-own methods (reference declares these directly on AgentBase,
    # not a mixin): SIP routing + name/answer helpers.
    'get_name' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'get_name'
    },
    'add_answer_verb' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'add_answer_verb'
    },
    'enable_sip_routing' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'enable_sip_routing'
    },
    'register_sip_username' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'register_sip_username'
    },
    'auto_map_sip_usernames' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'auto_map_sip_usernames'
    },

    # StateMixin: token validation lives on AgentBase in Perl.
    'validate_tool_token' => {
        module => 'signalwire.core.mixins.state_mixin',
        class  => 'StateMixin',
        method => 'validate_tool_token'
    },

    # ServerlessMixin: serverless request dispatch folded onto AgentBase.
    'handle_serverless_request' => {
        module => 'signalwire.core.mixins.serverless_mixin',
        class  => 'ServerlessMixin',
        method => 'handle_serverless_request'
    },

    # PromptMixin: post-prompt getter + POM setter (Perl exposes on AgentBase).
    'get_post_prompt' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'get_post_prompt'
    },
    'set_prompt_pom' => {
        module => 'signalwire.core.mixins.prompt_mixin',
        class  => 'PromptMixin',
        method => 'set_prompt_pom'
    },

    # SkillMixin
    'add_skill' => {
        module => 'signalwire.core.mixins.skill_mixin',
        class  => 'SkillMixin',
        method => 'add_skill'
    },
    'remove_skill' => {
        module => 'signalwire.core.mixins.skill_mixin',
        class  => 'SkillMixin',
        method => 'remove_skill'
    },
    'list_skills' => {
        module => 'signalwire.core.mixins.skill_mixin',
        class  => 'SkillMixin',
        method => 'list_skills'
    },
    'has_skill' => {
        module => 'signalwire.core.mixins.skill_mixin',
        class  => 'SkillMixin',
        method => 'has_skill'
    },

    # WebMixin
    'run' => { module => 'signalwire.core.mixins.web_mixin', class => 'WebMixin', method => 'run' },
    'serve' =>
        { module => 'signalwire.core.mixins.web_mixin', class => 'WebMixin', method => 'serve' },
    'manual_set_proxy_url' => {
        module => 'signalwire.core.mixins.web_mixin',
        class  => 'WebMixin',
        method => 'manual_set_proxy_url'
    },
    'set_dynamic_config_callback' => {
        module => 'signalwire.core.mixins.web_mixin',
        class  => 'WebMixin',
        method => 'set_dynamic_config_callback'
    },

    # SWMLService (extract_sip_username lives here in Python)
    'extract_sip_username' => {
        module => 'signalwire.core.swml_service',
        class  => 'SWMLService',
        method => 'extract_sip_username'
    },

    # Port-only on AgentBase — will land in PORT_ADDITIONS.md
    'render_swml' =>
        { module => 'signalwire.core.agent_base', class => 'AgentBase', method => 'render_swml' },
    'psgi_app' =>
        { module => 'signalwire.core.agent_base', class => 'AgentBase', method => 'psgi_app' },
    'set_answer_config' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'set_answer_config'
    },
    'list_tool_names' => {
        module => 'signalwire.core.agent_base',
        class  => 'AgentBase',
        method => 'list_tool_names'
    },
);

# Package-scoped overrides for specific (package, sub) → (module, class, method)
# mappings. Used when the default (which preserves the sub's name and class
# membership) needs to be rerouted, e.g. Perl helpers that live in a different
# Python home, or when Perl had to rename to avoid a builtin.
my %METHOD_OVERRIDES = (

    # SWAIGFunction: Perl `call` is the callable-protocol analog of the Python
    # reference's __call__ dunder (mirrors Ruby's call -> __call__ mapping).
    # The SWMLBuilder verb-dispatch dunder __getattr__ is already named for its
    # Python reference symbol (recorded verbatim by the parser), so it needs no
    # rename here; the entry below is kept explicit for the audit trail.
    'SignalWire::SWAIG::SWAIGFunction' => {
        'call' => {
            module => 'signalwire.core.swaig_function',
            class  => 'SWAIGFunction',
            method => '__call__'
        },
    },
    'SignalWire::SWML::SWMLBuilder' => {
        '__getattr__' => {
            module => 'signalwire.core.swml_builder',
            class  => 'SWMLBuilder',
            method => '__getattr__'
        },
    },

    # Relay Call: Perl `pass` maps to the reference's reserved-word-escaped
    # `pass_` (Python renamed `pass` -> `pass_`); Perl `to_string` is the
    # Perl-idiom human-readable rep the reference exposes as `__repr__`.
    'SignalWire::Relay::Call' => {
        'pass' => {
            module => 'signalwire.relay.call',
            class  => 'Call',
            method => 'pass_'
        },
        'to_string' => {
            module => 'signalwire.relay.call',
            class  => 'Call',
            method => '__repr__'
        },
    },

    # SWMLService auth methods come from AuthMixin in Python.
    'SignalWire::SWML::Service' => {
        'validate_basic_auth' => {
            module => 'signalwire.core.mixins.auth_mixin',
            class  => 'AuthMixin',
            method => 'validate_basic_auth'
        },
        'get_basic_auth_credentials' => {
            module => 'signalwire.core.mixins.auth_mixin',
            class  => 'AuthMixin',
            method => 'get_basic_auth_credentials'
        },

        # WebMixin methods folded onto Perl's SWML::Service (Python composes
        # them onto AgentBase via WebMixin). Route to the reference's WebMixin.
        'get_app' => {
            module => 'signalwire.core.mixins.web_mixin',
            class  => 'WebMixin',
            method => 'get_app'
        },
        'enable_debug_routes' => {
            module => 'signalwire.core.mixins.web_mixin',
            class  => 'WebMixin',
            method => 'enable_debug_routes'
        },
        'setup_graceful_shutdown' => {
            module => 'signalwire.core.mixins.web_mixin',
            class  => 'WebMixin',
            method => 'setup_graceful_shutdown'
        },

        # ToolMixin methods that live on Perl's SWML::Service (Python hosts
        # them on ToolMixin). Route to the reference's ToolMixin so they don't
        # surface as SWMLService extras.
        'define_tool' => {
            module => 'signalwire.core.mixins.tool_mixin',
            class  => 'ToolMixin',
            method => 'define_tool'
        },
        'define_tools' => {
            module => 'signalwire.core.mixins.tool_mixin',
            class  => 'ToolMixin',
            method => 'define_tools'
        },
        'on_function_call' => {
            module => 'signalwire.core.mixins.tool_mixin',
            class  => 'ToolMixin',
            method => 'on_function_call'
        },
        'register_swaig_function' => {
            module => 'signalwire.core.mixins.tool_mixin',
            class  => 'ToolMixin',
            method => 'register_swaig_function'
        },
    },

    # BedrockAgent: Perl has no __repr__ dunder — `to_string` is the
    # Perl-idiom human-readable rep the reference exposes as `__repr__`
    # (same idiom as Relay::Call above). Route it onto BedrockAgent.__repr__.
    'SignalWire::Agents::Bedrock' => {
        'to_string' => {
            module => 'signalwire.agents.bedrock',
            class  => 'BedrockAgent',
            method => '__repr__'
        },
    },

    # Perl renamed `delete` to `delete_<resource>` because `delete` is a
    # core builtin keyword. Translate back to the Python name `delete`.
    'SignalWire::REST::Namespaces::Recordings' => {
        'delete_recording' => {
            module => 'signalwire.rest.namespaces.recordings',
            class  => 'RecordingsResource',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Fabric::GenericResources' => {
        'delete_resource' => {
            module => 'signalwire.rest.namespaces.fabric',
            class  => 'GenericResources',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Compat::PhoneNumbers' => {
        'delete_number' => {
            module => 'signalwire.rest.namespaces.compat',
            class  => 'CompatPhoneNumbers',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Compat::Recordings' => {
        'delete_recording' => {
            module => 'signalwire.rest.namespaces.compat',
            class  => 'CompatRecordings',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Compat::Tokens' => {
        'delete_token' => {
            module => 'signalwire.rest.namespaces.compat',
            class  => 'CompatTokens',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Compat::Transcriptions' => {
        'delete_transcription' => {
            module => 'signalwire.rest.namespaces.compat',
            class  => 'CompatTranscriptions',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Project::Tokens' => {
        'delete_token' => {
            module => 'signalwire.rest.namespaces.project',
            class  => 'ProjectTokens',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Registry::Numbers' => {
        'delete_number' => {
            module => 'signalwire.rest.namespaces.registry',
            class  => 'RegistryNumbers',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Video::RoomRecordings' => {
        'delete_recording' => {
            module => 'signalwire.rest.namespaces.video',
            class  => 'VideoRoomRecordings',
            method => 'delete'
        },
    },
    'SignalWire::REST::Namespaces::Video::Streams' => {
        'delete_stream' => {
            module => 'signalwire.rest.namespaces.video',
            class  => 'VideoStreams',
            method => 'delete'
        },
    },

    # CrudResource base class's delete_resource maps to the Python `delete`. In the
    # oracle's base decomposition list/get live on ReadResource (the parent), and
    # CrudResource itself only adds create/update/delete. The Perl hand CrudResource
    # carries list+get inline (it does not extend a separate ReadResource base), so
    # reproject those two onto ReadResource to match the oracle's per-class surface.
    'SignalWire::REST::Namespaces::CrudResource' => {
        'delete_resource' =>
            { module => 'signalwire.rest._base', class => 'CrudResource', method => 'delete' },
        'list' => { module => 'signalwire.rest._base', class => 'ReadResource', method => 'list' },
        'get'  => { module => 'signalwire.rest._base', class => 'ReadResource', method => 'get' },
    },
    'SignalWire::REST::HttpClient' => {
        'delete_request' =>
            { module => 'signalwire.rest._base', class => 'HttpClient', method => 'delete' },
    },

    # Perl uses `to_hash` where Python uses `to_dict`. Python hash-like
    # APIs are dicts; the Perl convention is hashref, hence the name. For
    # surface parity, translate back to the Python name.
    'SignalWire::Contexts::Context' => {
        'to_hash' =>
            { module => 'signalwire.core.contexts', class => 'Context', method => 'to_dict' },
    },
    'SignalWire::Contexts::ContextBuilder' => {
        'to_hash' => {
            module => 'signalwire.core.contexts',
            class  => 'ContextBuilder',
            method => 'to_dict'
        },
    },
    'SignalWire::Contexts::GatherInfo' => {
        'to_hash' =>
            { module => 'signalwire.core.contexts', class => 'GatherInfo', method => 'to_dict' },
    },
    'SignalWire::Contexts::GatherQuestion' => {
        'to_hash' => {
            module => 'signalwire.core.contexts',
            class  => 'GatherQuestion',
            method => 'to_dict'
        },
    },
    'SignalWire::Contexts::Step' => {
        'to_hash' => { module => 'signalwire.core.contexts', class => 'Step', method => 'to_dict' },
    },
    'SignalWire::SWAIG::FunctionResult' => {
        'to_hash' => {
            module => 'signalwire.core.function_result',
            class  => 'FunctionResult',
            method => 'to_dict'
        },
    },

    # POM Section/PromptObjectModel: same to_hash -> to_dict rename as the
    # Contexts/FunctionResult families above; the underlying serialised
    # shape is identical between languages.
    'SignalWire::POM::Section' => {
        'to_hash' => { module => 'signalwire.pom.pom', class => 'Section', method => 'to_dict' },
    },
    'SignalWire::POM::PromptObjectModel' => {
        'to_hash' =>
            { module => 'signalwire.pom.pom', class => 'PromptObjectModel', method => 'to_dict' },
    },

    # SWML::Service auth methods come from AuthMixin in Python (declared
    # above); ContextBuilder validate is an AgentBase-internal helper not
    # surfaced in Python.

    # Logging helpers: Perl exports debug/info/warn/error as package-level
    # functions; in Python they come via get_logger() -> logger.debug etc.
    # The Perl module also has get_logger, so keep debug/info/warn/error
    # recorded under logging_config where they currently are (they'll
    # surface as port additions, which is fine).
);

# Force implicit __init__ for packages whose Python equivalent records
# __init__ on the class (Python AST sees an explicit `def __init__`), but
# whose Perl class extends another Moo class so our is_moo_root detector
# doesn't flag them. This list was derived from which Python classes
# expose __init__ in python_surface.json.
my %FORCE_IMPLICIT_INIT = map { $_ => 1 } (

    # AgentBase: the reference records AgentBase.__init__; Perl's AgentBase
    # extends SWML::Service (not a Moo root) and builds via BUILD, so force
    # the implicit __init__ (routed to agent_base.AgentBase.__init__ via the
    # AGENTBASE_METHOD_TO_PY{new} entry).
    'SignalWire::Agent::AgentBase',

    # REST core
    'SignalWire::REST::RestClient',
    'SignalWire::REST::HttpClient',
    'SignalWire::REST::HttpClient::Error',
    'SignalWire::REST::Namespaces::Base',

    # REST namespaces whose top-level class or resource declares __init__
    'SignalWire::REST::Namespaces::Calling',
    'SignalWire::REST::Namespaces::Chat',
    'SignalWire::REST::Namespaces::PubSub',
    'SignalWire::REST::Namespaces::PhoneNumbers',
    'SignalWire::REST::Namespaces::Addresses',
    'SignalWire::REST::Namespaces::Queues',
    'SignalWire::REST::Namespaces::Recordings',
    'SignalWire::REST::Namespaces::NumberGroups',
    'SignalWire::REST::Namespaces::VerifiedCallers',
    'SignalWire::REST::Namespaces::SipProfile',
    'SignalWire::REST::Namespaces::Lookup',
    'SignalWire::REST::Namespaces::ShortCodes',
    'SignalWire::REST::Namespaces::ImportedNumbers',
    'SignalWire::REST::Namespaces::MFA',
    'SignalWire::REST::Namespaces::Logs',
    'SignalWire::REST::Namespaces::Registry',
    'SignalWire::REST::Namespaces::Compat',
    'SignalWire::REST::Namespaces::Compat::Accounts',
    'SignalWire::REST::Namespaces::Compat::PhoneNumbers',
    'SignalWire::REST::Namespaces::Fabric',
    'SignalWire::REST::Namespaces::Fabric::Tokens',
    'SignalWire::REST::Namespaces::Datasphere',
    'SignalWire::REST::Namespaces::Datasphere::Documents',
    'SignalWire::REST::Namespaces::Video',
    'SignalWire::REST::Namespaces::Project',
    'SignalWire::REST::Namespaces::Project::Tokens',
    'SignalWire::REST::Pagination::PaginatedIterator',

    # Server / security / skills
    'SignalWire::Server::AgentServer',
    'SignalWire::Security::SessionManager',
    'SignalWire::Security::WebhookValidator',
    'SignalWire::Security::WebhookMiddleware',
    'SignalWire::Skills::SkillBase',
    'SignalWire::Skills::SkillManager',
    'SignalWire::Skills::SkillRegistry',

    # SWML
    'SignalWire::SWML::Document',    # SWMLBuilder in Python
    'SignalWire::SWML::Service',
    'SignalWire::SWML::Schema',      # SchemaUtils in Python

    # Prefabs (Python records __init__ on each prefab agent)
    'SignalWire::Prefabs::Concierge',
    'SignalWire::Prefabs::FAQBot',
    'SignalWire::Prefabs::InfoGatherer',
    'SignalWire::Prefabs::Receptionist',
    'SignalWire::Prefabs::Survey',

    # BedrockAgent extends AgentBase (not a Moo root), but the reference
    # records BedrockAgent.__init__ — force the implicit constructor.
    'SignalWire::Agents::Bedrock',

    # Skills that Python declares __init__ on the top-level Skill class
    # (GoogleMaps, WebSearch have __init__ on the INNER helper class, not
    # the skill itself — don't list those here).
    'SignalWire::Skills::Builtin::ApiNinjasTrivia',
    'SignalWire::Skills::Builtin::PlayBackgroundFile',
    'SignalWire::Skills::Builtin::Spider',
    'SignalWire::Skills::Builtin::WeatherApi',

    # Relay Action subclasses: Python declares __init__ on each concrete
    # action (it wires the event-type + terminal-state tuple through super).
    # Perl's subclasses `extends` the base Action (so is_moo_root is false),
    # but the CAPABILITY (a constructor with the action's identity) is present
    # — force the implicit __init__ so each concrete action compares equal to
    # the reference. The abstract base SignalWire::Relay::Action is skipped.
    'SignalWire::Relay::Action::AI',
    'SignalWire::Relay::Action::Collect',
    'SignalWire::Relay::Action::StandaloneCollect',
    'SignalWire::Relay::Action::Detect',
    'SignalWire::Relay::Action::Fax',
    'SignalWire::Relay::Action::Pay',
    'SignalWire::Relay::Action::Play',
    'SignalWire::Relay::Action::Record',
    'SignalWire::Relay::Action::Stream',
    'SignalWire::Relay::Action::Tap',
    'SignalWire::Relay::Action::Transcribe',
);

# Suppress implicit __init__ emission. Relay::Event subclasses and the
# Constants holder are dataclasses in Python: they don't expose __init__
# as a public method. Matching that keeps the diff meaningful.
my %SKIP_IMPLICIT_INIT = map { $_ => 1 } (
    'SignalWire::Relay::Constants',

    # SWML helper classes whose Python reference class does NOT expose an
    # __init__ in the surface oracle: SwmlRenderer (staticmethod-only) and the
    # base SWMLVerbHandler ABC. SWMLBuilder / SchemaUtils DO have __init__ in
    # the oracle, so they are NOT skipped. AIVerbHandler extends the base (not
    # is_moo_root) so it already gets no implicit __init__.
    'SignalWire::SWML::SWMLRenderer',
    'SignalWire::SWML::SWMLHandler',

    # Relay::Event and every Relay::Event::Foo subclass
    'SignalWire::Relay::Event',
    'SignalWire::Relay::Event::CallState',
    'SignalWire::Relay::Event::CallReceive',
    'SignalWire::Relay::Event::CallDial',
    'SignalWire::Relay::Event::CallConnect',
    'SignalWire::Relay::Event::CallDisconnect',
    'SignalWire::Relay::Event::CallPlay',
    'SignalWire::Relay::Event::CallRecord',
    'SignalWire::Relay::Event::CallCollect',
    'SignalWire::Relay::Event::CallDetect',
    'SignalWire::Relay::Event::CallFax',
    'SignalWire::Relay::Event::CallTap',
    'SignalWire::Relay::Event::CallStream',
    'SignalWire::Relay::Event::CallTranscribe',
    'SignalWire::Relay::Event::CallPay',
    'SignalWire::Relay::Event::CallSendDigits',
    'SignalWire::Relay::Event::CallRefer',
    'SignalWire::Relay::Event::Conference',
    'SignalWire::Relay::Event::CallAI',
    'SignalWire::Relay::Event::MessageReceive',
    'SignalWire::Relay::Event::MessageState',
    'SignalWire::Relay::Event::AuthorizationState',
    'SignalWire::Relay::Event::Disconnect',

    # CLI-only container packages with no instantiable class contract
    # (we don't emit them here, but listed for future use).
);

# Subs to always skip: private helpers, Moo plumbing, __PACKAGE__ accessors.
my %SKIP_SUB = map { $_ => 1 } qw(
    BUILD
    BUILDARGS
    DEMOLISH
    DESTROY
    import
    AUTOLOAD
);

# Filenames to exclude from the walk.
my %SKIP_FILE = ();

# -------------------------------------------------------------------------
# Parser — one pass per file, tracking current package.
# -------------------------------------------------------------------------
sub parse_file {
    my ($path) = @_;

    # Whole-file line-by-line parse; the handle is read across the loop below
    # and explicitly closed once the file is consumed (close $fh, ~45 lines on).
    # See RequireBriefOpen exemption rationale in .perlcriticrc.
    open my $fh, '<', $path or die "open $path: $!";
    my @packages;    # list of { name => ..., subs => [...], _seen => {...} }
    my $current;
    while ( my $line = <$fh> ) {
        if ( $line =~ /^\s*package\s+([A-Za-z_][\w:]*)\s*;/ ) {
            my $pkg = $1;
            $current = {
                name        => $pkg,
                subs        => [],
                _seen       => {},
                uses_moo    => 0,
                has_extends => 0,
            };
            push @packages, $current;
            next;
        }

        # Detect `use Moo;` / `use Moo::Role;`
        if ( $line =~ /^\s*use\s+Moo(?:::Role)?\b/ ) {
            $current->{uses_moo} = 1 if $current;
            next;
        }

        # Detect `extends 'Foo';` (Moo inheritance)
        if ( $line =~ /^\s*extends\s+['"\(]/ ) {
            $current->{has_extends} = 1 if $current;

            # fall through — no 'next' needed, but nothing else to match
        }

        # Only match sub definitions at column 0. Indented subs are almost
        # always inside string heredocs/POD examples or nested coderefs, not
        # package-level public API. This keeps false positives out.
        if ( $line =~ /^sub\s+([A-Za-z_]\w*)\b/ ) {
            my $sub_name = $1;
            next unless $current;    # sub before any package — ignore
                                     # Perl convention: leading underscore = private. Dunder
                                     # methods (e.g. __iter__, __next__, __init__) are public
                                     # protocol hooks and should be emitted.
            next if $sub_name =~ /^_/ && !( $sub_name =~ /^__\w+__$/ );
            next if $SKIP_SUB{$sub_name};
            next if $current->{_seen}{$sub_name}++;                       # de-dup overloaded defs
            push @{ $current->{subs} }, $sub_name;
        }
    }
    close $fh;

    # A Moo "root" class uses Moo directly with no `extends`. Those classes
    # own their own __init__ and should emit it; subclasses/roles inherit it
    # and shouldn't repeat it in the surface.
    for my $p (@packages) {
        $p->{is_moo_root} = ( $p->{uses_moo} && !$p->{has_extends} ) ? 1 : 0;
    }
    return \@packages;
}

# -------------------------------------------------------------------------
# Projection — walk the files, project each (package, sub) into Python-shape
# surface buckets.
# -------------------------------------------------------------------------
sub collect_surface {
    my ($lib_root) = @_;
    my %modules;    # module => { classes => { CLS => [...] }, functions => [...] }

    my $ensure = sub {
        my ($mod) = @_;
        $modules{$mod} //= { classes => {}, functions => [] };
        return $modules{$mod};
    };
    my $record_class_method = sub {
        my ( $mod, $class, $method ) = @_;
        my $bucket = $ensure->($mod);
        $bucket->{classes}{$class} //= [];
        my %seen = map { $_ => 1 } @{ $bucket->{classes}{$class} };
        push @{ $bucket->{classes}{$class} }, $method unless $seen{$method};
    };
    my $record_function = sub {
        my ( $mod, $fn ) = @_;
        my $bucket = $ensure->($mod);
        my %seen   = map { $_ => 1 } @{ $bucket->{functions} };
        push @{ $bucket->{functions} }, $fn unless $seen{$fn};
    };
    my $record_class_only = sub {
        my ( $mod, $class ) = @_;
        my $bucket = $ensure->($mod);
        $bucket->{classes}{$class} //= [];
    };

    my @pm_files;
    File::Find::find(
        {
            wanted   => sub { push @pm_files, $File::Find::name if /\.pm$/ },
            no_chdir => 1,
        },
        $lib_root
    );

    # SignalWire.pm at the lib root
    my $top = File::Spec->catfile( File::Spec->catdir( $lib_root, '..' ), 'SignalWire.pm' );
    push @pm_files, $top if -f $top;

    for my $file ( sort @pm_files ) {
        next if $SKIP_FILE{$file};
        my $packages = parse_file($file);
        for my $pkg (@$packages) {
            my $pkg_name = $pkg->{name};

            # --- Generated read-side TYPE modules (item D / A-H) — path-routed ---
            # A package under Generated::Types::<Sub>:: routes by its <Sub> path
            # segment to signalwire.rest.namespaces.<ns>_types_generated, recorded
            # as a method-less class (its `has` accessors are not `sub` decls).
            if ( $pkg_name =~ /^SignalWire::REST::Namespaces::Generated::Types::(\w+)::(\w+)$/ ) {
                my ( $sub, $tname ) = ( $1, $2 );
                my $ns = $TYPE_SUBDIR_NS{$sub};
                if ( !$ns ) {
                    warn "enumerate_surface: generated type package $pkg_name has "
                        . "no Types subdir mapping\n";
                    next;
                }
                my $tmod = "signalwire.rest.namespaces.${ns}_types_generated";
                $record_class_only->( $tmod, $tname );
                next;
            }

            # --- Generated SWAIG read-side payloads (item D1) — path-routed ---
            # generate_swaig_payloads.py emits method-less Moo data packages under
            # lib/.../SWAIG/Generated/<Sub>/<Name>.pm, one <Sub> per oracle module.
            # Route by the <Sub> path segment; scoped to SWAIG::Generated:: so the
            # hand SWAIG SDK classes (FunctionResult/ParameterSchema) are not
            # misrouted.
            if ( $pkg_name =~ /^SignalWire::SWAIG::Generated::(\w+)::(\w+)$/ ) {
                my ( $sub, $tname ) = ( $1, $2 );
                my %swaig_sub_mod = (
                    'PostPrompt'   => 'signalwire.core.post_prompt_generated',
                    'SwaigRequest' => 'signalwire.core.swaig_request_generated',
                    'SwaigActions' => 'signalwire.core.swaig_actions_generated',
                );
                my $smod = $swaig_sub_mod{$sub};
                if ( !$smod ) {
                    warn "enumerate_surface: generated SWAIG package $pkg_name has "
                        . "no subdir mapping\n";
                    next;
                }
                $record_class_only->( $smod, $tname );
                next;
            }

            # --- Generated RELAY protocol wire types (item I) — path-routed ---
            # generate_relay_protocol.py emits one method-less Moo data package per
            # relay-protocol/*.{params,result}.json object into
            # lib/.../Relay/Generated/<Name>.pm. Route to
            # signalwire.relay.protocol_types_generated as a method-less class.
            # Scoped to Relay::Generated:: so the hand Relay SDK classes one level
            # up (Call/Client/CallState/Event/…) are never misrouted.
            if ( $pkg_name =~ /^SignalWire::Relay::Generated::(\w+)$/ ) {
                my $tname = $1;
                $record_class_only->( 'signalwire.relay.protocol_types_generated', $tname );
                next;
            }

            # --- Generated SWML-verb CONFIG types (item D2) — path-routed ---
            # generate_swml_verbs.py emits one method-less Moo data package per
            # schema.json $defs object into lib/.../SWML/Generated/<Name>.pm. Route
            # every such package to signalwire.core.swml_verbs_generated as a
            # method-less class (125 of the 155 recur as REST wire types; the
            # gen-type leaf fold collapses the cross-module duplicates on both
            # sides). Scoped to the SWML::Generated:: package space only.
            if ( $pkg_name =~ /^SignalWire::SWML::Generated::(\w+)$/ ) {
                my $tname = $1;
                $record_class_only->( 'signalwire.core.swml_verbs_generated', $tname );
                next;
            }

            # --- Generated REST resource-tree projection (item B) ---
            # Packages under SignalWire::REST::Namespaces::Generated::<Name> project
            # onto the oracle's <ns>_resources_generated / _client_tree_generated /
            # _base modules. Handle them here (they are deliberately NOT in
            # %PACKAGE_TO_PY — the projection is table-driven per generated class).
            if ( $pkg_name =~ /^SignalWire::REST::Namespaces::Generated::(\w+)$/ ) {
                my $gname = $1;

                # ResourceTree is a Moo::Role the RestClient composes — it exposes
                # no oracle surface of its own (its accessors ARE the resource
                # classes, projected below); skip it.
                next if $gname eq 'ResourceTree';

                # The two generated bases map onto signalwire.rest._base. The Perl
                # Generated::ReadResource (list/get) == oracle _base.ReadResource;
                # the Perl Generated::FabricResource carries list_addresses, which
                # the oracle houses on _base.CrudWithAddresses (FabricResource itself
                # is an empty marker subclass).
                if ( $gname eq 'ReadResource' ) {
                    $record_class_only->( 'signalwire.rest._base', 'ReadResource' );
                    for my $s ( @{ $pkg->{subs} } ) {
                        $record_class_method->( 'signalwire.rest._base', 'ReadResource', $s );
                    }
                    next;
                }
                if ( $gname eq 'FabricResource' ) {
                    $record_class_only->( 'signalwire.rest._base', 'FabricResource' );
                    for my $s ( @{ $pkg->{subs} } ) {
                        $record_class_method->( 'signalwire.rest._base', 'CrudWithAddresses', $s );
                    }
                    next;
                }

                my $proj = $GENERATED_PROJECTION{$gname};
                if ( !$proj ) {
                    warn "enumerate_surface: generated package $pkg_name has no projection entry\n";
                    next;
                }
                my $gmod =
                    $proj->{ns} eq '_client_tree'
                    ? 'signalwire.rest.namespaces._client_tree_generated'
                    : "signalwire.rest.namespaces.$proj->{ns}_resources_generated";

                $record_class_only->( $gmod, $gname );
                $record_class_method->( $gmod, $gname, '__init__' );
                for my $s ( @{ $pkg->{subs} } ) {
                    $record_class_method->( $gmod, $gname, $s );
                }
                for my $bm ( @{ $GENERATED_BASE_SURFACE{ $proj->{base} } // [] } ) {
                    $record_class_method->( $gmod, $gname, $bm );
                }
                next;
            }

            my $info = $PACKAGE_TO_PY{$pkg_name};
            if ( !$info ) {
                warn "enumerate_surface: package $pkg_name not in translation map (file: $file)\n";
                next;
            }
            my $mod   = $info->{module};
            my $class = $info->{class};

            # Record the class even if there are no subs, to keep the shape
            # consistent with Python's output for empty-class definitions.
            $record_class_only->( $mod, $class ) if defined $class;

            # Emit implicit `__init__` only when the Perl class is a Moo root
            # (use Moo; with no extends) — that matches Python's AST-based
            # enumerator which records `__init__` on the class that defines
            # it, not on subclasses that inherit it. Packages opting in via
            # %FORCE_IMPLICIT_INIT get one too.
            if ( defined $class && !$SKIP_IMPLICIT_INIT{$pkg_name} ) {
                my $has_explicit_new = grep { $_ eq 'new' } @{ $pkg->{subs} };
                my $should_emit_init = 0;
                if ( !$has_explicit_new ) {
                    if ( $FORCE_IMPLICIT_INIT{$pkg_name} ) {
                        $should_emit_init = 1;
                    } elsif ( $pkg->{is_moo_root} ) {
                        $should_emit_init = 1;
                    }
                }
                if ($should_emit_init) {
                    if ( $pkg_name eq 'SignalWire::Agent::AgentBase' ) {
                        my $r = $AGENTBASE_METHOD_TO_PY{new};
                        $record_class_method->( $r->{module}, $r->{class}, $r->{method} ) if $r;
                    } else {
                        $record_class_method->( $mod, $class, '__init__' );
                    }
                }
            }

            for my $sub ( @{ $pkg->{subs} } ) {

                # Special-case routing for AgentBase flat class.
                if ( $pkg_name eq 'SignalWire::Agent::AgentBase' ) {
                    my $route = $AGENTBASE_METHOD_TO_PY{$sub};
                    if ($route) {
                        $record_class_method->(
                            $route->{module}, $route->{class}, $route->{method}
                        );
                    } else {
                        warn
"enumerate_surface: AgentBase sub '$sub' has no routing entry; recording on AgentBase\n";
                        $record_class_method->( 'signalwire.core.agent_base', 'AgentBase', $sub );
                    }
                    next;
                }

                # Per-package overrides
                if ( my $ov = $METHOD_OVERRIDES{$pkg_name}{$sub} ) {
                    $record_class_method->( $ov->{module}, $ov->{class}, $ov->{method} );
                    next;
                }

                # Default: project onto declared (module, class)
                my $method = ( $sub eq 'new' ) ? '__init__' : $sub;
                if ( defined $class ) {
                    $record_class_method->( $mod, $class, $method );
                } else {

                    # Module-level (no class)
                    $record_function->( $mod, $method );
                }
            }
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: RELAY action control methods projected onto concrete actions.
    # The reference no longer factors the controls into abstract mixin bases;
    # it projects them directly onto each concrete action (PlayAction: stop,
    # pause, resume, volume; RecordAction: stop, pause, resume; CollectAction:
    # + volume + start_input_timers; the rest: stop). Perl flattens the
    # hierarchy: every concrete action `extends SignalWire::Relay::Action`,
    # which defines `stop` — so `stop` is a real INHERITED method the static
    # per-package parser doesn't see on the subclass. Project the inherited
    # `stop` onto every concrete *Action class (real capability, not invented
    # surface — RULES §2 idiom-via-enumerator). pause/resume/volume are defined
    # on the concrete subclasses themselves, so the parser already records
    # them; StandaloneCollect inherits its controls from Collect (handled in
    # the inherited-members block below).
    {
        my $RELAY_CALL   = 'signalwire.relay.call';
        my $call_classes = $modules{$RELAY_CALL}{classes} // {};
        for my $cls ( keys %$call_classes ) {
            next unless $cls =~ /\wAction\z/;    # concrete *Action (not bare Action)
            next if $cls eq 'Action';
            my %seen = map { $_ => 1 } @{ $call_classes->{$cls} };
            next if $seen{stop};
            push @{ $call_classes->{$cls} }, 'stop';
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: RELAY event surface.
    #   (a) `from_payload` is a class-method constructor DECLARED ONCE on the
    #       base SignalWire::Relay::Event and INHERITED by every typed event
    #       subclass. The Python reference records from_payload on every event
    #       class (RelayEvent + all *Event subclasses). The static parser only
    #       sees the literal `sub from_payload` on the base package, so project
    #       it onto every event class the enumerator recorded. Real inherited
    #       capability (RULES §2 idiom-via-enumerator), not invented surface.
    #   (b) `parse_event` is declared as a `sub` in the base Event package, so
    #       the parser attributed it to the RelayEvent class; the reference
    #       exposes it as a MODULE-level function. Move it from the class method
    #       list onto the module functions[] (module free-function form).
    {
        my $RELAY_EVENT = 'signalwire.relay.event';
        my $ev          = $modules{$RELAY_EVENT};
        if ($ev) {

            # (b) parse_event: class-method -> module function.
            for my $cls ( keys %{ $ev->{classes} } ) {
                my @kept = grep { $_ ne 'parse_event' } @{ $ev->{classes}{$cls} };
                if ( @kept != @{ $ev->{classes}{$cls} } ) {
                    $ev->{classes}{$cls} = \@kept;
                    push @{ $ev->{functions} }, 'parse_event'
                        unless grep { $_ eq 'parse_event' } @{ $ev->{functions} };
                }
            }

            # (a) from_payload: project onto every event class.
            for my $cls ( keys %{ $ev->{classes} } ) {
                next unless $cls =~ /Event\z/ || $cls eq 'RelayEvent';
                my %seen = map { $_ => 1 } @{ $ev->{classes}{$cls} };
                next if $seen{from_payload};
                $seen{from_payload} = 1;
                $ev->{classes}{$cls} = [ keys %seen ];
            }
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: RELAY call surface — inherited/attribute members the static
    # parser can't see.
    #   (a) StandaloneCollectAction inherits start_input_timers from its parent
    #       CollectAction (Perl `extends Collect`); the reference records it on
    #       StandaloneCollectAction too. Project the inherited method.
    #   (b) Message.result is a Moo `has 'result'` ATTRIBUTE accessor (a real
    #       method), which the parser — matching only `sub` — misses. The
    #       reference exposes it as a @property `result`. Project it.
    {
        my $cc = $modules{'signalwire.relay.call'}{classes} // {};
        if (   $cc->{CollectAction}
            && ( grep { $_ eq 'start_input_timers' } @{ $cc->{CollectAction} } )
            && $cc->{StandaloneCollectAction}
            && !( grep { $_ eq 'start_input_timers' } @{ $cc->{StandaloneCollectAction} } ) )
        {
            push @{ $cc->{StandaloneCollectAction} }, 'start_input_timers';
        }
        my $mc = $modules{'signalwire.relay.message'}{classes} // {};
        if ( $mc->{Message}
            && !( grep { $_ eq 'result' } @{ $mc->{Message} } ) )
        {
            push @{ $mc->{Message} }, 'result';
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: SWMLService.__getattr__. Perl's SWML::Service implements the
    # dynamic-verb dispatch via `sub AUTOLOAD` (the direct analog of Python's
    # __getattr__ — both intercept unknown-method calls to install schema
    # verbs). AUTOLOAD is in the parser's SKIP_SUB set (it is a Perl special
    # sub, not a normal method name), so project the reference's __getattr__
    # onto SWMLService explicitly. Real capability (RULES §2), not invented.
    {
        my $sc = $modules{'signalwire.core.swml_service'}{classes} // {};
        if ( $sc->{SWMLService}
            && !( grep { $_ eq '__getattr__' } @{ $sc->{SWMLService} } ) )
        {
            push @{ $sc->{SWMLService} }, '__getattr__';
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: SkillBase-inherited methods on concrete built-in skills.
    # The static parser records only `sub`s literally declared in each skill
    # package, so methods inherited from SignalWire::Skills::SkillBase
    # (get_hints, get_prompt_sections, get_instance_key, cleanup, ...) are
    # invisible even though the CAPABILITY is genuinely present at runtime.
    # The Python reference records each skill's inherited methods, so without
    # this projection those appear as omissions. Project onto each
    # `<name>.skill` module's `*Skill` class exactly the base methods the
    # reference declares for THAT skill (union; a method already declared on
    # the concrete Perl class is a no-op). Real inherited capability
    # (RULES §2 idiom-via-enumerator), not invented surface.
    {
        my %SKILL_INHERITED_PROJECTION = (
            DateTimeSkill             => [ 'get_hints', 'get_prompt_sections' ],
            JokeSkill                 => [ 'get_hints', 'get_prompt_sections' ],
            MathSkill                 => [ 'get_hints', 'get_prompt_sections' ],
            GoogleMapsSkill           => ['get_prompt_sections'],
            DataSphereSkill           => [ 'cleanup', 'get_instance_key', 'get_prompt_sections' ],
            DataSphereServerlessSkill => [ 'get_instance_key', 'get_prompt_sections' ],
            SWMLTransferSkill         => [ 'get_instance_key', 'get_prompt_sections' ],
            WebSearchSkill            => [ 'get_hints', 'get_instance_key', 'get_prompt_sections' ],
            WikipediaSearchSkill      => [ 'get_hints', 'get_prompt_sections' ],
            ApiNinjasTriviaSkill      => ['get_instance_key'],
            PlayBackgroundFileSkill   => ['get_instance_key'],
            ClaudeSkillsSkill         => ['get_instance_key'],
            InfoGathererSkill         => ['get_instance_key'],
            SpiderSkill               => [ 'cleanup', 'get_instance_key' ],
            NativeVectorSearchSkill   => [ 'cleanup', 'get_instance_key', 'get_prompt_sections' ],
        );
        for my $mod ( keys %modules ) {
            next unless $mod =~ /^signalwire\.skills\.[^.]+\.skill$/;
            my $classes = $modules{$mod}{classes} // {};
            for my $cls ( keys %$classes ) {
                my $projection = $SKILL_INHERITED_PROJECTION{$cls} or next;
                my %seen       = map { $_ => 1 } @{ $classes->{$cls} };
                for my $method (@$projection) {
                    next if $seen{$method};
                    push @{ $classes->{$cls} }, $method;
                    $seen{$method} = 1;
                }
            }
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: multi-home method DONORS. The Python reference declares some
    # methods on MORE THAN ONE class (a base + a mixin) that Perl implements
    # once. Perl's single `sub` lands on its default home; COPY it onto the
    # additional reference class(es) so the surface compares equal. Each
    # copied method is a genuine capability already present on the source —
    # this is idiom-via-enumerator (RULES §2), not invented surface. The
    # concrete methods (serve/stop/as_router/... on SWMLService; get_basic_
    # auth_credentials on SWMLService) are real Perl subs; the mixin copies
    # reflect that AgentBase composes them via the reference's mixins.
    {
        my %DONORS = (

            # SWMLService -> WebMixin: web-facing service controls.
            'signalwire.core.mixins.web_mixin.WebMixin' => {
                from    => 'signalwire.core.swml_service.SWMLService',
                methods => [
                    'as_router',            'serve',
                    'manual_set_proxy_url', 'on_request',
                    'on_swml_request',      'register_routing_callback',
                ],
            },

            # SWMLService -> AuthMixin: basic-auth credential accessor (the
            # reference declares it on BOTH). It is redirected to AuthMixin by
            # a METHOD_OVERRIDE above; donate it back onto SWMLService too.
            'signalwire.core.swml_service.SWMLService' => {
                from    => 'signalwire.core.mixins.auth_mixin.AuthMixin',
                methods => ['get_basic_auth_credentials'],
            },
        );
        for my $target ( keys %DONORS ) {
            my ( $tmod, $tcls ) = $target =~ /^(.+)\.([^.]+)$/;
            my $spec = $DONORS{$target};
            my ( $smod, $scls ) = $spec->{from} =~ /^(.+)\.([^.]+)$/;
            my $src  = $modules{$smod}{classes}{$scls} // [];
            my %have = map { $_ => 1 } @$src;
            my $tgt  = $modules{$tmod}{classes}{$tcls} //= [];
            my %seen = map { $_ => 1 } @$tgt;
            for my $m ( @{ $spec->{methods} } ) {
                next unless $have{$m};
                next if $seen{$m};
                push @$tgt, $m;
                $seen{$m} = 1;
            }
        }
    }

    # -----------------------------------------------------------------
    # Reconcile: module-level FREE FUNCTIONS the reference exposes at module
    # scope but Perl implements as package subs on a class-ish package.
    #   * SignalWire::DataMap::create_simple_api_tool / create_expression_tool
    #     -> signalwire.core.data_map module functions (factory helpers).
    #   * SignalWire::list_skills -> signalwire.list_skills (top-level).
    # The parser records these on the DataMap/SignalWire class buckets; move
    # them to the reference module's functions[] (free-function form).
    {
        # SignalWire::list_skills already surfaces as a module function
        # (SignalWire routes with class => undef, so its subs land in
        # functions[]); only DataMap's factory helpers need moving off the
        # DataMap class bucket onto the module's functions[].
        my %FREE_FN = (
            'signalwire.core.data_map' => {
                class   => 'DataMap',
                methods => [ 'create_simple_api_tool', 'create_expression_tool' ],
            },
        );
        for my $mod ( keys %FREE_FN ) {
            my $spec    = $FREE_FN{$mod};
            my $classes = $modules{$mod}{classes} // {};
            my $cls     = $spec->{class};
            next unless $classes->{$cls};
            my %move  = map  { $_ => 1 } @{ $spec->{methods} };
            my @kept  = grep { !$move{$_} } @{ $classes->{$cls} };
            my @moved = grep { $move{$_} } @{ $classes->{$cls} };
            next unless @moved;
            $classes->{$cls} = \@kept;
            delete $classes->{$cls} unless @kept;
            my %seen = map { $_ => 1 } @{ $modules{$mod}{functions} };

            for my $fn (@moved) {
                push @{ $modules{$mod}{functions} }, $fn unless $seen{$fn};
            }
        }
    }

    # Normalise: sort method arrays and function arrays.
    for my $mod ( keys %modules ) {
        my $bucket = $modules{$mod};
        for my $c ( keys %{ $bucket->{classes} } ) {
            my @m = sort @{ $bucket->{classes}{$c} };
            $bucket->{classes}{$c} = \@m;
        }
        my @f = sort @{ $bucket->{functions} };
        $bucket->{functions} = \@f;
    }

    return \%modules;
}

# -------------------------------------------------------------------------
# git sha for provenance (optional)
# -------------------------------------------------------------------------
sub git_sha {
    my $out = eval { `git -C '$REPO_ROOT' rev-parse HEAD 2>/dev/null` };
    return 'N/A' unless defined $out;
    chomp $out;
    return $out || 'N/A';
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------
my $modules = collect_surface($LIB_ROOT);

my $snapshot = {
    version        => '1',
    generated_from => 'signalwire-perl @ ' . git_sha(),
    perl_version   => sprintf( '%vd', $^V ),
    modules        => $modules,
};

my $json = JSON->new->utf8->canonical->pretty->encode($snapshot);

if ($to_stdout) {
    print $json;
} else {
    open my $fh, '>', $output_path or die "open $output_path: $!";
    print {$fh} $json;
    close $fh;
    print STDERR "wrote $output_path\n";
}
