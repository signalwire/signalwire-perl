#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Core::PomBuilder;

subtest 'construction' => sub {
    my $b = SignalWire::Core::PomBuilder->new;
    ok( $b, 'builder created' );
    isa_ok( $b->pom, 'SignalWire::POM::PromptObjectModel', 'pom attribute' );
    ok( !$b->has_section('Nope'), 'no sections yet' );
};

subtest 'add_section + has_section + get_section' => sub {
    my $b   = SignalWire::Core::PomBuilder->new;
    my $ret = $b->add_section( 'Role', body => 'You are helpful.' );
    is( $ret, $b, 'add_section returns self for chaining' );
    ok( $b->has_section('Role'),     'section present' );
    ok( !$b->has_section('Missing'), 'absent section reported absent' );

    my $sec = $b->get_section('Role');
    ok( $sec, 'get_section returns the section' );
    is( $sec->title,                'Role',             'section title' );
    is( $sec->body,                 'You are helpful.', 'section body' );
    is( $b->get_section('Missing'), undef,              'get_section undef when absent' );
};

subtest 'add_section with bullets and subsections' => sub {
    my $b = SignalWire::Core::PomBuilder->new;
    $b->add_section(
        'Guidelines',
        bullets     => [ 'Be concise', 'Be kind' ],
        subsections => [ { title => 'Tone', body => 'Warm.' } ],
    );
    my $sec = $b->get_section('Guidelines');
    is_deeply( $sec->bullets, [ 'Be concise', 'Be kind' ], 'bullets set' );
    is( scalar @{ $sec->subsections }, 1,       'one subsection' );
    is( $sec->subsections->[0]->title, 'Tone',  'subsection title' );
    is( $sec->subsections->[0]->body,  'Warm.', 'subsection body' );
};

subtest 'add_to_section appends body and bullets (auto-vivifies)' => sub {
    my $b = SignalWire::Core::PomBuilder->new;

    # auto-vivification: section does not exist yet
    $b->add_to_section( 'Notes', body => 'First.' );
    ok( $b->has_section('Notes'), 'section auto-created' );
    is( $b->get_section('Notes')->body, 'First.', 'body set' );

    # append body separated by blank line
    $b->add_to_section( 'Notes', body => 'Second.' );
    is( $b->get_section('Notes')->body, "First.\n\nSecond.", 'body appended with blank line' );

    # single bullet and list of bullets
    $b->add_to_section( 'Notes', bullet  => 'one' );
    $b->add_to_section( 'Notes', bullets => [ 'two', 'three' ] );
    is_deeply(
        $b->get_section('Notes')->bullets,
        [ 'one', 'two', 'three' ],
        'bullet + bullets appended'
    );
};

subtest 'add_subsection auto-vivifies parent' => sub {
    my $b   = SignalWire::Core::PomBuilder->new;
    my $ret = $b->add_subsection( 'Parent', 'Child', body => 'kid' );
    is( $ret, $b, 'add_subsection returns self' );
    ok( $b->has_section('Parent'), 'parent auto-created' );
    my $parent = $b->get_section('Parent');
    is( scalar @{ $parent->subsections }, 1,       'child added' );
    is( $parent->subsections->[0]->title, 'Child', 'child title' );
};

subtest 'render_markdown / render_xml / to_dict / to_json' => sub {
    my $b = SignalWire::Core::PomBuilder->new;
    $b->add_section( 'Role', body => 'Helpful.' );

    my $md = $b->render_markdown;
    like( $md, qr/Role/,      'markdown contains title' );
    like( $md, qr/Helpful\./, 'markdown contains body' );

    my $xml = $b->render_xml;
    like( $xml, qr/<prompt>/,            'xml has prompt root' );
    like( $xml, qr{<title>Role</title>}, 'xml has title element' );

    my $dict = $b->to_dict;
    is( ref $dict,         'ARRAY', 'to_dict is an arrayref' );
    is( $dict->[0]{title}, 'Role',  'to_dict section title' );

    my $json = $b->to_json;
    ok( !ref $json, 'to_json returns a string' );
    like( $json, qr/"title"/, 'json has title key' );
    like( $json, qr/Role/,    'json has Role' );
};

subtest 'from_sections rebuilds the section index' => sub {
    my $sections = [
        { title => 'Greeting', body    => 'Hi there.' },
        { title => 'Rules',    bullets => ['Be nice'] },
    ];
    my $b = SignalWire::Core::PomBuilder->from_sections($sections);
    isa_ok( $b, 'SignalWire::Core::PomBuilder', 'from_sections returns a builder' );
    ok( $b->has_section('Greeting'), 'first section indexed' );
    ok( $b->has_section('Rules'),    'second section indexed' );
    is( $b->get_section('Greeting')->body, 'Hi there.', 'body round-tripped' );
};

done_testing;
