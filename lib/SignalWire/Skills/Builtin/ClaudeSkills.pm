package SignalWire::Skills::Builtin::ClaudeSkills;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use feature 'signatures';
no warnings 'experimental::signatures';
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
use SignalWire::Skills::SkillDiscovery ();
SignalWire::Skills::SkillRegistry->register_skill( 'claude_skills', __PACKAGE__ );

has '+skill_name'        => ( default => sub { 'claude_skills' } );
has '+skill_description' => ( default => sub { 'Load Claude SKILL.md files as agent tools' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

# Parsed skills discovered from skills_path (populated by setup()).
has _skills => ( is => 'rw', default => sub { [] } );

# Discover and parse all SKILL.md files under the configured skills_path.
# Parity with Python ClaudeSkillsSkill.setup: skills_path is required and
# must be an existing directory. An empty skill set is still a valid setup.
sub setup ($self) {
    my $skills_path = $self->params->{skills_path};
    return 0 unless defined $skills_path && length $skills_path;

    $skills_path = _expand_user($skills_path);
    return 0 unless -d $skills_path;
    $self->params->{skills_path} = $skills_path;

    my $include = $self->params->{include} // ['*'];
    my $exclude = $self->params->{exclude} // [];

    my $skills = SignalWire::Skills::SkillDiscovery::discover_skills(
        $skills_path,
        include => $include,
        exclude => $exclude,
    );
    $self->_skills($skills);
    return 1;
}

# Register one SWAIG tool per discovered skill. Each tool name is
# "<tool_prefix><sanitized-skill-name>"; the handler returns the SKILL.md
# body (or a requested section's content) with $ARGUMENTS / ${CLAUDE_*}
# substitution applied.
sub register_tools ($self) {
    my $prefix = $self->params->{tool_prefix} // 'claude_';

    for my $skill ( @{ $self->_skills } ) {
        my $tool_name = $prefix . _sanitize_tool_name( $skill->{name} );

        my $overrides   = $self->params->{skill_descriptions} // {};
        my $description = $overrides->{ $skill->{name} }      // $skill->{description}
            // "Use the $skill->{name} skill";

        my %properties = (
            arguments => {
                type        => 'string',
                description => $skill->{argument_hint}
                    // 'Arguments or context to pass to the skill',
            },
        );

        my @section_names = sort keys %{ $skill->{sections} // {} };
        if (@section_names) {
            $properties{section} = {
                type        => 'string',
                description => 'Which reference section to load',
                enum        => \@section_names,
            };
        }

        my $response_prefix  = $self->params->{response_prefix}  // '';
        my $response_postfix = $self->params->{response_postfix} // '';

        # Capture the skill in a closure so each tool renders its own body.
        my $handler = sub ( $args, $raw ) {
            require SignalWire::SWAIG::FunctionResult;
            my $section   = $args->{section};
            my $arguments = $args->{arguments} // '';

            my $content;
            if ( defined $section && exists $skill->{sections}{$section} ) {
                $content =
                    SignalWire::Skills::SkillDiscovery::_slurp( $skill->{sections}{$section} );
                $content = "Error loading section '$section'" unless defined $content;
            } else {
                $content = $skill->{body};
            }

            $content = _substitute_variables( $content, $skill->{skill_dir}, $raw );
            $content = _substitute_arguments( $content, $arguments );

            if ( length $response_prefix || length $response_postfix ) {
                my @parts;
                push @parts, $response_prefix if length $response_prefix;
                push @parts, $content;
                push @parts, $response_postfix if length $response_postfix;
                $content = join( "\n\n", @parts );
            }

            return SignalWire::SWAIG::FunctionResult->new($content);
        };

        $self->define_tool(
            name        => $tool_name,
            description => $description,
            parameters  => {
                type       => 'object',
                properties => \%properties,
                required   => ['arguments'],
            },
            handler => $handler,
        );
    }
    return $self;
}

# Speech hints: each skill's name words (hyphens/underscores split),
# deduplicated. Parity with Python get_hints.
sub get_hints ($self) {
    my %seen;
    for my $skill ( @{ $self->_skills } ) {
        my $name = $skill->{name} // '';
        $name =~ s/[-_]+/ /g;
        for my $w ( split /\s+/, $name ) {
            $seen{$w} = 1 if length $w;
        }
    }
    return [ sort keys %seen ];
}

# One prompt section per discovered skill (its SKILL.md body), listing any
# available reference sections.
sub _get_prompt_sections ($self) {
    my @sections;
    my $prefix = $self->params->{tool_prefix} // 'claude_';
    for my $skill ( @{ $self->_skills } ) {
        my $tool_name = $prefix . _sanitize_tool_name( $skill->{name} );
        my $body      = $skill->{body};
        my @keys      = sort keys %{ $skill->{sections} // {} };
        if (@keys) {
            $body .= "\n\nAvailable reference sections: " . join( ', ', @keys );
            $body .= "\nCall ${tool_name}(section=\"<name>\") to load a section.";
        }
        push @sections, { title => $skill->{name}, body => $body };
    }
    return \@sections;
}

sub get_instance_key ($self) {
    my $skills_path = $self->params->{skills_path} // 'default';
    return $self->skill_name . '_' . $skills_path;
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        skills_path => {
            type        => 'string',
            description => 'Directory of Claude skill folders (each with SKILL.md)',
            required    => 1
        },
        include => {
            type        => 'array',
            description => 'Glob patterns for skills to include',
            default     => ['*']
        },
        exclude => {
            type        => 'array',
            description => 'Glob patterns for skills to exclude',
            default     => []
        },
        tool_prefix => {
            type        => 'string',
            description => 'Prefix for generated tool names',
            default     => 'claude_'
        },
        skill_descriptions =>
            { type => 'object', description => 'Override descriptions per skill', default => {} },
        response_prefix =>
            { type => 'string', description => 'Text prepended to skill results', default => '' },
        response_postfix =>
            { type => 'string', description => 'Text appended to skill results', default => '' },
    };
}

# --- helpers (package subs; not methods) ---

sub _expand_user ($path) {
    $path =~ s{\A~(?=/|\z)}{ $ENV{HOME} // '' }e;
    return $path;
}

# Sanitize a skill name for use as a SWAIG tool name: lowercase, hyphens/
# spaces -> underscore, strip other invalid chars, no leading digit.
sub _sanitize_tool_name ($name) {
    $name = lc( $name // '' );
    $name =~ s/[-\s]+/_/g;
    $name =~ s/[^a-z0-9_]//g;
    $name = "_$name" if length $name && $name =~ /\A\d/;
    return length $name ? $name : 'unnamed';
}

# ${CLAUDE_SKILL_DIR} / ${CLAUDE_SESSION_ID} substitution.
sub _substitute_variables ( $content, $skill_dir, $raw ) {
    $content //= '';
    my $dir = defined $skill_dir ? "$skill_dir" : '';
    $content =~ s/\$\{CLAUDE_SKILL_DIR\}/$dir/g;
    my $session_id = ( ref($raw) eq 'HASH' ? $raw->{call_id} : undef ) // '';
    $content =~ s/\$\{CLAUDE_SESSION_ID\}/$session_id/g;
    return $content;
}

# $ARGUMENTS / $ARGUMENTS[N] / $N substitution, with the fallback-append
# when the body has no bare $ARGUMENTS. Parity with Python
# _substitute_arguments.
sub _substitute_arguments ( $body, $arguments ) {
    $body      //= '';
    $arguments //= '';

    my $has_bare   = ( $body =~ /\$ARGUMENTS(?!\[)/ ) ? 1                          : 0;
    my @positional = length $arguments                ? split( /\s+/, $arguments ) : ();

    # $ARGUMENTS[N]
    $body =~ s/\$ARGUMENTS\[(\d+)\]/ defined $positional[$1] ? $positional[$1] : '' /ge;

    # $N shorthand (after $ARGUMENTS[...] to avoid clobbering indices)
    $body =~ s/\$(\d+)(?!\d)/ defined $positional[$1] ? $positional[$1] : '' /ge;

    # bare $ARGUMENTS
    $body =~ s/\$ARGUMENTS/$arguments/g;

    if ( !$has_bare && length $arguments ) {
        $body .= "\n\nARGUMENTS: $arguments";
    }
    return $body;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::ClaudeSkills - load Claude SKILL.md files as agent tools

=head1 DESCRIPTION

Perl port of Python's C<claude_skills> skill. Walks the configured
C<skills_path> (via the shared L<SignalWire::Skills::SkillDiscovery> walker),
parses each subdirectory's C<SKILL.md> (YAML frontmatter + markdown body) and
supporting C<.md> section files, and registers one SWAIG tool per skill. Each
tool returns the skill's instructions (or a requested section) with
C<$ARGUMENTS> / C<${CLAUDE_SKILL_DIR}> / C<${CLAUDE_SESSION_ID}> substitution.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
