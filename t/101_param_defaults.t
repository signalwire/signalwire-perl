#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# =============================================================================
# Parameter DEFAULTS and REQUIREDNESS are contract (porting-sdk
# ALLOWLIST_DISCIPLINE.md §10: ``required`` must not vary between ports).
#
# Every assertion here CALLS THE METHOD WITHOUT THE ARGUMENT and checks the
# behaviour that the reference's default produces. A test that passes the
# argument explicitly proves nothing about the default — it would pass just as
# happily against a port that has no default at all, which is exactly the
# vacuity this file exists to avoid.
#
# The mirror-image assertions are here too: where the REFERENCE requires an
# argument, omitting it must FAIL. A port that quietly invents a default there
# turns a caller's forgotten argument into silently wrong behaviour instead of
# an error.
# =============================================================================

use SignalWire::Agent::AgentBase;
use SignalWire::SWML::Service;
use SignalWire::Server::AgentServer;
use SignalWire::Contexts;
use SignalWire::Utils::UrlValidator;
use SignalWire::Skills::SkillManager;
use SignalWire::Skills::SkillBase;
use SignalWire::SWAIG::FunctionResult;
use SignalWire::POM::Section;
use SignalWire::Relay::Event;
use SignalWire::Relay::Client;

sub new_agent {
    return SignalWire::Agent::AgentBase->new(
        name  => 'defaults',
        route => '/defaults',
    );
}

sub new_service {
    return SignalWire::SWML::Service->new( name => 'svc', route => '/svc' );
}

# -------------------------------------------------------------------------
# Reference: create_simple_context(name: str = "default")
# -------------------------------------------------------------------------
subtest 'create_simple_context(name="default")' => sub {
    my $bare = SignalWire::Contexts::create_simple_context();
    is( $bare->name, 'default', 'omitted name yields the reference default' );

    my $named = SignalWire::Contexts::create_simple_context('billing');
    is( $named->name, 'billing', 'an explicit name still wins' );

    # The class-method spelling must resolve the SAME default.
    my $cls = SignalWire::Contexts->create_simple_context();
    is( $cls->name, 'default', 'class-method form defaults identically' );
};

# -------------------------------------------------------------------------
# Reference: validate_url(url, allow_private: bool = False)
# -------------------------------------------------------------------------
subtest 'validate_url(allow_private=False)' => sub {
    # A private address must be REJECTED when allow_private is omitted — that
    # is the security-relevant half of the default.
    ok( !SignalWire::Utils::UrlValidator::validate_url('http://127.0.0.1/x'),
        'omitted allow_private defaults to false -> private URL rejected' );

    ok( SignalWire::Utils::UrlValidator::validate_url( 'http://127.0.0.1/x', 1 ),
        'explicit allow_private=1 accepts the same URL' );
};

# -------------------------------------------------------------------------
# Reference: AgentServer.serve_static_files(directory, route="/")
# -------------------------------------------------------------------------
subtest 'serve_static_files(route="/")' => sub {
    my $server = SignalWire::Server::AgentServer->new;

    # Omitting the route must NOT die (it used to croak) and must register the
    # directory at the reference's "/" default.
    my $ok = eval { $server->serve_static_files('lib'); 1 };
    ok( $ok, 'route may be omitted' ) or diag($@);
    is_deeply( [ sort keys %{ $server->_static_routes } ],
        ['/'], 'omitted route registers at the reference default "/"' );
};

# -------------------------------------------------------------------------
# Reference: get_basic_auth_credentials(include_source: bool = False)
# -------------------------------------------------------------------------
subtest 'get_basic_auth_credentials(include_source=False)' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name                => 'svc',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );

    my @bare = $svc->get_basic_auth_credentials();
    is( scalar @bare, 2, 'omitted include_source returns the 2-element pair' );

    my @with = $svc->get_basic_auth_credentials(1);
    is( scalar @with, 3, 'explicit include_source=1 appends the source' );
};

# -------------------------------------------------------------------------
# Reference: FunctionResult.hold(timeout: int = 300),
#            enable_extensive_data(enabled: bool = True),
#            enable_functions_on_timeout(enabled: bool = True),
#            replace_in_history(text = True)
# -------------------------------------------------------------------------
subtest 'FunctionResult defaults land in the emitted action' => sub {
    my $held = SignalWire::SWAIG::FunctionResult->new->hold;
    is_deeply( $held->action->[0], { hold => 300 },
        'omitted timeout emits the reference default 300' );

    my $capped = SignalWire::SWAIG::FunctionResult->new->hold(1200);
    is_deeply( $capped->action->[0], { hold => 900 },
        'an explicit timeout is still clamped to the 900 ceiling' );

    my $ext = SignalWire::SWAIG::FunctionResult->new->enable_extensive_data;
    is_deeply( $ext->action->[0], { extensive_data => JSON::true() },
        'omitted enabled emits the reference default true' );

    my $fot = SignalWire::SWAIG::FunctionResult->new->enable_functions_on_timeout;
    is_deeply( $fot->action->[0],
        { functions_on_speaker_timeout => JSON::true() },
        'omitted enabled emits the reference default true' );

    my $rep = SignalWire::SWAIG::FunctionResult->new->replace_in_history;
    is_deeply( $rep->action->[0], { replace_in_history => JSON::true() },
        'omitted text emits the reference default true' );
};

# -------------------------------------------------------------------------
# Reference: Section.render_markdown(level: int = 2),
#            Section.render_xml(indent: int = 0)
# -------------------------------------------------------------------------
subtest 'Section render defaults' => sub {
    my $sec = SignalWire::POM::Section->new( title => 'T', body => 'B' );

    my $md = $sec->render_markdown;
    like( $md, qr/^\#\# T/m,
        'omitted level renders at the reference default heading depth 2' );

    my $md3 = $sec->render_markdown(3);
    like( $md3, qr/^\#\#\# T/m, 'an explicit level still applies' );

    my $xml = $sec->render_xml;
    like( $xml, qr/^<section>/m,
        'omitted indent renders at the reference default column 0' );

    my $xml2 = $sec->render_xml(2);
    like( $xml2, qr/^ {4}<section>/m, 'an explicit indent still applies' );
};

# -------------------------------------------------------------------------
# Reference: register_routing_callback(callback_fn, path="/sip")
#
# The callback comes FIRST and the path is OPTIONAL. This port previously took
# them in the opposite order with the path mandatory.
# -------------------------------------------------------------------------
subtest 'register_routing_callback(callback_fn, path="/sip")' => sub {
    my $svc = new_service();
    my $cb  = sub { return };

    $svc->register_routing_callback($cb);
    is_deeply( [ sort keys %{ $svc->routing_callbacks } ],
        ['/sip'], 'omitted path registers at the reference default "/sip"' );
    is( $svc->routing_callbacks->{'/sip'}, $cb,
        'the FIRST argument is the callback' );

    my $svc2 = new_service();
    $svc2->register_routing_callback( $cb, 'voice' );
    is_deeply( [ sort keys %{ $svc2->routing_callbacks } ],
        ['/voice'], 'an explicit path still applies (and is normalised)' );
};

# -------------------------------------------------------------------------
# Reference: SkillManager.load_skill(skill_name, skill_class=None, params=None)
# -------------------------------------------------------------------------
subtest 'load_skill(skill_class=None, params=None)' => sub {
    my $mgr = SignalWire::Skills::SkillManager->new( agent => new_agent() );

    # Both optional arguments omitted: the call must reach the registry lookup
    # (and report the miss) rather than dying on a missing argument.
    my ( $ok, $err ) = $mgr->load_skill('no_such_skill');
    ok( !$ok, 'omitting skill_class falls through to the registry lookup' );
    like( $err, qr/not found in registry/, 'and reports the registry miss' );
};

# -------------------------------------------------------------------------
# Reference: the subclass-override hooks take OPTIONAL arguments.
#   AgentBase.on_summary(summary, raw_data=None)
#   SWMLService.on_request(request_data=None, callback_path=None)
#   SWMLService.on_swml_request(request_data=None, callback_path=None,
#                               request=None)
#   ToolMixin.on_function_call(name, args, raw_data=None)
#   AgentBase.add_answer_verb(config=None)
#   PromptMixin.define_contexts(contexts=None)
# -------------------------------------------------------------------------
subtest 'optional hook parameters may be omitted' => sub {
    my $agent = new_agent();
    my $svc   = new_service();

    ok( eval { $agent->on_summary('s');            1 }, 'on_summary(raw_data omitted)' )      or diag($@);
    ok( eval { $svc->on_request();                 1 }, 'on_request(both omitted)' )          or diag($@);
    ok( eval { $svc->on_swml_request();            1 }, 'on_swml_request(all omitted)' )      or diag($@);
    ok( eval { $svc->on_function_call( 'f', {} );  1 }, 'on_function_call(raw_data omitted)' ) or diag($@);
    ok( eval { $agent->add_answer_verb();          1 }, 'add_answer_verb(config omitted)' )   or diag($@);
    ok( eval { $agent->define_contexts();          1 }, 'define_contexts(contexts omitted)' ) or diag($@);

    # add_answer_verb's omitted config must produce the empty-config answer
    # verb, not a crash and not a phantom value.
    is_deeply( $agent->answer_config, {},
        'omitted config yields an empty answer config' );
};

# -------------------------------------------------------------------------
# Reference: prompt_add_section(title, body="", ...) /
#            prompt_add_subsection(parent_title, title, body="", ...)
# -------------------------------------------------------------------------
subtest 'prompt_add_section / prompt_add_subsection body="" default' => sub {
    my $agent = new_agent();
    $agent->prompt_add_section('Only Title');

    my ($sec) = grep { $_->{title} eq 'Only Title' } @{ $agent->pom_sections };
    ok( $sec, 'section added with body omitted' );
    ok( !exists $sec->{body},
        'an empty default body is not emitted (reference Section.to_dict '
            . 'writes body only when non-empty)' );

    $agent->prompt_add_subsection( 'Only Title', 'Sub' );
    my ($sub) = grep { $_->{title} eq 'Sub' } @{ $sec->{subsections} || [] };
    ok( $sub, 'subsection added with body omitted' );
    is( $sub->{body}, '', 'omitted subsection body defaults to the empty string' );
};

# =========================================================================
# THE MIRROR IMAGE — parameters the REFERENCE requires must NOT be defaulted.
#
# Each of these carried an invented default; omitting the argument silently
# produced an empty payload instead of an error. They are asserted to FAIL now,
# which is the only way to keep an invented default from creeping back.
# =========================================================================
subtest 'reference-REQUIRED parameters have no invented default' => sub {
    # Each of these asserts the ARITY error specifically. A bare ``!eval`` is
    # not enough — several of these methods can die for unrelated reasons, and
    # a test that only checks "it died" would stay green against a port that
    # re-invented the default. (Caught by mutation-testing this file.)
    for my $cls (
        [ 'SignalWire::Relay::Event',             'RelayEvent' ],
        [ 'SignalWire::Relay::Event::CallRecord', 'RecordEvent' ],
        [ 'SignalWire::Relay::Event::CallQueue',  'QueueEvent' ],
        )
    {
        my ( $pkg, $label ) = @$cls;
        ok( !eval { $pkg->from_payload(); 1 },
            "$label.from_payload requires payload" );
        like( $@, qr/Too few arguments/,
            "...and it is an ARITY error ($label)" );
    }

    my $client = SignalWire::Relay::Client->new(
        project => 'p',
        token   => 't',
        host    => 'example.signalwire.com',
    );
    # Assert on the ARITY error specifically. A bare ``!eval`` is vacuous here:
    # with no live websocket ``execute`` dies for an unrelated reason too, so a
    # port that re-invented ``$params //= {}`` would still "fail" and the test
    # would pass while proving nothing. (Caught by mutation-testing this file.)
    ok( !eval { $client->execute('calling.answer'); 1 },
        'RelayClient.execute requires params' );
    like( $@, qr/Too few arguments/,
        '...and it is an ARITY error, not an incidental connection failure' );

    my $svc = new_service();
    ok( !eval { $svc->handle_request( 'GET', 'http://x/' ); 1 },
        'SWMLService.handle_request requires headers' );
    like( $@, qr/Too few arguments/,
        '...and it is an ARITY error (handle_request)' );

    # ...while the parameters the reference DOES default still work omitted,
    # so the mirror assertions above are not just "everything dies".
    ok( eval { SignalWire::Relay::Event->from_payload( {} ); 1 },
        'from_payload accepts an explicit payload' );
    ok( eval { $svc->handle_request( 'GET', 'http://x/', {} ); 1 },
        'handle_request accepts headers with body omitted (body IS optional)' );
};

subtest 'SkillBase.get_skill_data requires raw_data' => sub {
    # SkillBase is abstract (``_skill_namespace`` dies without a skill_name),
    # so exercise the inherited method through a concrete subclass.
    require SignalWire::Skills::Builtin::InfoGatherer;
    my $skill = SignalWire::Skills::Builtin::InfoGatherer->new(
        agent  => new_agent(),
        params => {},
    );

    ok( !eval { $skill->get_skill_data(); 1 },
        'get_skill_data requires raw_data (no invented {} default)' );
    like( $@, qr/Too few arguments/,
        '...and it is an ARITY error (get_skill_data)' );
    is_deeply( $skill->get_skill_data( {} ), {},
        'get_skill_data accepts an explicit payload' );
    is_deeply(
        $skill->get_skill_data(
            { global_data => { $skill->_skill_namespace => { seen => 1 } } }
        ),
        { seen => 1 },
        'and reads the skill namespace out of the supplied payload'
    );
};

done_testing();
