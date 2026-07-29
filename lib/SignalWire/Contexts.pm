package SignalWire::Contexts;
use strict;
use warnings;
use JSON ();

our $MAX_CONTEXTS          = 50;
our $MAX_STEPS_PER_CONTEXT = 100;

# Reserved tool names auto-injected by the runtime when contexts/steps are
# present. User-defined SWAIG tools must not collide with these names:
#   - next_step / change_context are injected when valid_steps or
#     valid_contexts is set so the model can navigate the flow.
#   - gather_submit is injected while a step's gather_info is collecting
#     answers.
# ContextBuilder->validate rejects any agent that registers a user tool
# sharing one of these names (see the validation in
# SignalWire::Contexts::ContextBuilder::validate below).
our %RESERVED_NATIVE_TOOL_NAMES = (
    next_step      => 1,
    change_context => 1,
    gather_submit  => 1,
);

# Valid values for a step's or context's ``history`` visibility mode.
#   keep     nothing is cleared — every prior step's instructions AND dialogue
#            stay in the model's context.
#   default  prior step instructions are hidden; the dialogue is kept.
#   hide     prior instructions hidden AND the prior dialogue pulled out of the
#            model's context (recover it via ${step_history.*} in the new text).
our @HISTORY_MODES = qw( keep default hide );

sub _validate_history {
    my ($mode) = @_;
    unless ( defined $mode && grep { $_ eq $mode } @HISTORY_MODES ) {
        my $shown = defined $mode ? "'$mode'" : 'undef';
        die "history must be one of ("
            . join( ', ', map { "'$_'" } @HISTORY_MODES )
            . "), got $shown";
    }
    return $mode;
}

# ==========================================================================
# GatherQuestion
# ==========================================================================
package SignalWire::Contexts::GatherQuestion;
use Moo;
use JSON ();

has 'key'       => ( is => 'ro', required => 1 );
has 'question'  => ( is => 'ro', required => 1 );
has 'type'      => ( is => 'ro', default  => sub { 'string' } );
has 'confirm'   => ( is => 'ro', default  => sub { 0 } );
has 'prompt'    => ( is => 'ro', default  => sub { undef } );
has 'functions' => ( is => 'ro', default  => sub { undef } );

# Tri-state: undef means "inherit the gather_info default"; a defined 0/1
# overrides it for this question.
has 'isolated' => ( is => 'ro', default => sub { undef } );

sub to_hash {
    my ($self) = @_;
    my %d = ( key => $self->key, question => $self->question );
    $d{type}      = $self->type      if $self->type ne 'string';
    $d{confirm}   = JSON::true       if $self->confirm;
    $d{prompt}    = $self->prompt    if defined $self->prompt;
    $d{functions} = $self->functions if defined $self->functions;

    # Emitted even when false, so it can override an isolated gather default.
    $d{isolated} = $self->isolated ? JSON::true : JSON::false
        if defined $self->isolated;
    return \%d;
}

# ==========================================================================
# GatherInfo
# ==========================================================================
package SignalWire::Contexts::GatherInfo;
use Moo;
use JSON ();

has '_questions'         => ( init_arg => undef, is      => 'rw', default => sub { [] } );
has '_output_key'        => ( is       => 'rw',  default => sub { undef } );
has '_completion_action' => ( is       => 'rw',  default => sub { undef } );
has '_prompt'            => ( is       => 'rw',  default => sub { undef } );
has '_isolated'          => ( is       => 'rw',  default => sub { 0 } );

sub add_question {
    my ( $self, %opts ) = @_;
    my $q = SignalWire::Contexts::GatherQuestion->new(
        key       => $opts{key},
        question  => $opts{question},
        type      => $opts{type}    // 'string',
        confirm   => $opts{confirm} // 0,
        prompt    => $opts{prompt},
        functions => $opts{functions},
        isolated  => $opts{isolated},
    );
    push @{ $self->_questions }, $q;
    return $self;
}

sub to_hash {
    my ($self) = @_;
    die "gather_info must have at least one question" unless @{ $self->_questions };
    my %d = ( questions => [ map { $_->to_hash } @{ $self->_questions } ] );
    $d{prompt}            = $self->_prompt            if defined $self->_prompt;
    $d{output_key}        = $self->_output_key        if defined $self->_output_key;
    $d{completion_action} = $self->_completion_action if defined $self->_completion_action;
    $d{isolated}          = JSON::true                if $self->_isolated;
    return \%d;
}

# ==========================================================================
# Step
# ==========================================================================
package SignalWire::Contexts::Step;
use Moo;
use JSON ();

has 'name' => ( is => 'ro', required => 1 );

has '_text'                => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_step_criteria'       => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_functions'           => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_valid_steps'         => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_valid_contexts'      => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_sections'            => ( init_arg => undef, is => 'rw', default => sub { [] } );
has '_gather_info'         => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_end'                 => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_skip_user_turn'      => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_skip_to_next_step'   => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_reset_system_prompt' => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_reset_user_prompt'   => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_reset_consolidate'   => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_reset_full_reset'    => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_history'             => ( init_arg => undef, is => 'rw', default => sub { undef } );

sub set_text {
    my ( $self, $text ) = @_;
    die "Cannot use set_text() when POM sections have been added"
        if @{ $self->_sections };
    $self->_text($text);
    return $self;
}

sub add_section {
    my ( $self, $title, $body ) = @_;
    die "Cannot add POM sections when set_text() has been used"
        if defined $self->_text;
    push @{ $self->_sections }, { title => $title, body => $body };
    return $self;
}

sub add_bullets {
    my ( $self, $title, $bullets ) = @_;
    die "Cannot add POM sections when set_text() has been used"
        if defined $self->_text;
    push @{ $self->_sections }, { title => $title, bullets => $bullets };
    return $self;
}

sub set_step_criteria {
    my ( $self, $criteria ) = @_;
    $self->_step_criteria($criteria);
    return $self;
}

#
# set_functions — set which non-internal functions are callable while this
# step is active.
#
# IMPORTANT — inheritance behavior:
#   If you do NOT call this method, the step inherits whichever function
#   set was active on the previous step (or the previous context's last
#   step). The server-side runtime only resets the active set when a step
#   explicitly declares its `functions` field. This is the most common
#   source of bugs in multi-step agents: forgetting set_functions on a
#   later step lets the previous step's tools leak through. Best practice
#   is to call set_functions explicitly on every step that should differ
#   from the previous one.
#
# Keep the per-step active set small: LLM tool selection accuracy
# degrades noticeably past ~7-8 simultaneously-active tools per call.
# Use per-step whitelisting to partition large tool collections.
#
# Arguments:
#   $functions — one of:
#     - arrayref of function names (whitelist)
#     - empty arrayref []         (explicit disable-all)
#     - the string "none"         (synonym for [])
#
# Internal functions (e.g. gather_submit, hangup_hook) are ALWAYS protected
# and cannot be deactivated by this whitelist. The native navigation tools
# next_step and change_context are injected automatically when
# set_valid_steps / set_valid_contexts is used; they are not affected by
# this list and do not need to appear in it.
#
sub set_functions {
    my ( $self, $functions ) = @_;
    $self->_functions($functions);
    return $self;
}

sub set_valid_steps {
    my ( $self, $steps ) = @_;
    $self->_valid_steps($steps);
    return $self;
}

sub set_valid_contexts {
    my ( $self, $contexts ) = @_;
    $self->_valid_contexts($contexts);
    return $self;
}

#
# set_end — mark this step as terminal for the step flow.
#
# IMPORTANT: end=1 does NOT end the conversation or hang up the call.
# It exits step mode entirely after this step executes — clearing the
# steps list, current step index, valid_steps, and valid_contexts. The
# agent keeps running, but operates only under the base system prompt
# and the context-level prompt; no more step instructions are injected
# and no more next_step tool is offered.
#
# To actually end the call, call a hangup tool or define a hangup hook.
#
sub set_end {
    my ( $self, $end ) = @_;
    $self->_end( $end ? 1 : 0 );
    return $self;
}

sub set_skip_user_turn {
    my ( $self, $skip ) = @_;
    $self->_skip_user_turn( $skip ? 1 : 0 );
    return $self;
}

sub set_skip_to_next_step {
    my ( $self, $skip ) = @_;
    $self->_skip_to_next_step( $skip ? 1 : 0 );
    return $self;
}

sub set_gather_info {
    my ( $self, %opts ) = @_;
    $self->_gather_info(
        SignalWire::Contexts::GatherInfo->new(
            _output_key        => $opts{output_key},
            _completion_action => $opts{completion_action},
            _prompt            => $opts{prompt},
            _isolated          => $opts{isolated} ? 1 : 0,
        )
    );
    return $self;
}

#
# add_gather_question — add a question to this step's gather_info.
# set_gather_info() must be called before this method.
#
# IMPORTANT — gather mode locks function access:
#   While the model is asking gather questions, the runtime forcibly
#   deactivates ALL of the step's other functions. The only callable
#   tools during a gather question are:
#
#     - gather_submit (the native answer-submission tool)
#     - Whatever names you pass in this question's `functions` option
#
#   next_step and change_context are also filtered out — the model
#   cannot navigate away until the gather completes. This is by design:
#   it forces a tight ask → submit → next-question loop.
#
#   If a question needs to call out to a tool (e.g. validate an email,
#   geocode a ZIP), list that tool name in this question's `functions`
#   option. Functions listed here are active ONLY for this question.
#
sub add_gather_question {
    my ( $self, %opts ) = @_;
    die "Must call set_gather_info() before add_gather_question()"
        unless defined $self->_gather_info;
    $self->_gather_info->add_question(%opts);
    return $self;
}

sub clear_sections {
    my ($self) = @_;
    $self->_sections( [] );
    $self->_text(undef);
    return $self;
}

sub set_reset_system_prompt {
    my ( $self, $sp ) = @_;
    $self->_reset_system_prompt($sp);
    return $self;
}

sub set_reset_user_prompt {
    my ( $self, $up ) = @_;
    $self->_reset_user_prompt($up);
    return $self;
}

sub set_reset_consolidate {
    my ( $self, $c ) = @_;
    $self->_reset_consolidate( $c ? 1 : 0 );
    return $self;
}

sub set_reset_full_reset {
    my ( $self, $fr ) = @_;
    $self->_reset_full_reset( $fr ? 1 : 0 );
    return $self;
}

#
# set_history — control what the model still sees when this step is entered.
#
# The mode applies at the moment this step is entered and governs everything
# before it (including the turn that triggered the transition); it does not
# affect this step's own accumulating turns. Nothing is deleted from the call
# log — this only changes what the model sees.
#
#   "keep"    — clear nothing; prior instructions AND dialogue stay visible.
#   "default" — hide prior step instructions, keep the dialogue (the default
#               when unset).
#   "hide"    — hide prior instructions AND pull prior dialogue out of the
#               model's context; recover pieces via a ${step_history.*}
#               reference in this step's text.
#
# Dies unless $history is one of keep/default/hide. Returns $self for chaining.
#
sub set_history {
    my ( $self, $history ) = @_;
    $self->_history( SignalWire::Contexts::_validate_history($history) );
    return $self;
}

sub _render_text {
    my ($self) = @_;
    return $self->_text if defined $self->_text;

    die "Step '" . $self->name . "' has no text or POM sections defined"
        unless @{ $self->_sections };

    my @parts;
    for my $sec ( @{ $self->_sections } ) {
        if ( exists $sec->{bullets} ) {
            push @parts, "## $sec->{title}";
            push @parts, map { "- $_" } @{ $sec->{bullets} };
        } else {
            push @parts, "## $sec->{title}";
            push @parts, $sec->{body};
        }
        push @parts, '';
    }
    my $text = join( "\n", @parts );
    $text =~ s/\s+$//;
    return $text;
}

sub to_hash {
    my ($self) = @_;
    my %d = (
        name => $self->name,
        text => $self->_render_text,
    );

    $d{step_criteria}     = $self->_step_criteria  if defined $self->_step_criteria;
    $d{functions}         = $self->_functions      if defined $self->_functions;
    $d{valid_steps}       = $self->_valid_steps    if defined $self->_valid_steps;
    $d{valid_contexts}    = $self->_valid_contexts if defined $self->_valid_contexts;
    $d{end}               = JSON::true             if $self->_end;
    $d{skip_user_turn}    = JSON::true             if $self->_skip_user_turn;
    $d{skip_to_next_step} = JSON::true             if $self->_skip_to_next_step;
    $d{history}           = $self->_history        if defined $self->_history;

    my %reset;
    $reset{system_prompt} = $self->_reset_system_prompt if defined $self->_reset_system_prompt;
    $reset{user_prompt}   = $self->_reset_user_prompt   if defined $self->_reset_user_prompt;
    $reset{consolidate}   = JSON::true                  if $self->_reset_consolidate;
    $reset{full_reset}    = JSON::true                  if $self->_reset_full_reset;
    $d{reset}             = \%reset                     if keys %reset;

    $d{gather_info} = $self->_gather_info->to_hash if defined $self->_gather_info;

    return \%d;
}

# ==========================================================================
# Context
# ==========================================================================
package SignalWire::Contexts::Context;
use Moo;
use JSON ();

has 'name' => ( is => 'ro', required => 1 );

has '_steps'                  => ( init_arg => undef, is => 'rw', default => sub { {} } );
has '_step_order'             => ( init_arg => undef, is => 'rw', default => sub { [] } );
has '_valid_contexts'         => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_valid_steps'            => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_initial_step'           => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_post_prompt'            => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_system_prompt'          => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_system_prompt_sections' => ( init_arg => undef, is => 'rw', default => sub { [] } );
has '_consolidate'            => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_full_reset'             => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_user_prompt'            => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_isolated'               => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has '_prompt_text'            => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_prompt_sections'        => ( init_arg => undef, is => 'rw', default => sub { [] } );
has '_enter_fillers'          => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_exit_fillers'           => ( init_arg => undef, is => 'rw', default => sub { undef } );
has '_history'                => ( init_arg => undef, is => 'rw', default => sub { undef } );

sub add_step {
    my ( $self, $name, %opts ) = @_;
    die "Step '$name' already exists in context '" . $self->name . "'"
        if exists $self->_steps->{$name};
    die "Maximum steps per context ($SignalWire::Contexts::MAX_STEPS_PER_CONTEXT) exceeded"
        if keys %{ $self->_steps } >= $SignalWire::Contexts::MAX_STEPS_PER_CONTEXT;

    my $step = SignalWire::Contexts::Step->new( name => $name );
    $self->_steps->{$name} = $step;
    push @{ $self->_step_order }, $name;

    $step->add_section( 'Task', $opts{task} )       if defined $opts{task};
    $step->add_bullets( 'Process', $opts{bullets} ) if defined $opts{bullets};
    $step->set_step_criteria( $opts{criteria} )     if defined $opts{criteria};
    $step->set_functions( $opts{functions} )        if defined $opts{functions};
    $step->set_valid_steps( $opts{valid_steps} )    if defined $opts{valid_steps};

    return $step;
}

sub get_step {
    my ( $self, $name ) = @_;
    return $self->_steps->{$name};
}

sub remove_step {
    my ( $self, $name ) = @_;
    if ( exists $self->_steps->{$name} ) {
        delete $self->_steps->{$name};
        $self->_step_order( [ grep { $_ ne $name } @{ $self->_step_order } ] );
    }
    return $self;
}

sub move_step {
    my ( $self, $name, $position ) = @_;
    die "Step '$name' not found in context '" . $self->name . "'"
        unless exists $self->_steps->{$name};
    my @order = grep { $_ ne $name } @{ $self->_step_order };
    splice @order, $position, 0, $name;
    $self->_step_order( \@order );
    return $self;
}

#
# set_initial_step — set which step the context starts on when entered.
#
# By default, a context starts on its first step (index 0). Use this
# to skip a preamble step on re-entry via change_context.
#
sub set_initial_step {
    my ( $self, $step_name ) = @_;
    $self->_initial_step($step_name);
    return $self;
}

sub set_valid_contexts {
    my ( $self, $contexts ) = @_;
    $self->_valid_contexts($contexts);
    return $self;
}

sub set_valid_steps {
    my ( $self, $steps ) = @_;
    $self->_valid_steps($steps);
    return $self;
}

sub set_post_prompt {
    my ( $self, $pp ) = @_;
    $self->_post_prompt($pp);
    return $self;
}

sub set_system_prompt {
    my ( $self, $sp ) = @_;
    die "Cannot use set_system_prompt() when POM sections have been added for system prompt"
        if @{ $self->_system_prompt_sections };
    $self->_system_prompt($sp);
    return $self;
}

sub set_consolidate {
    my ( $self, $c ) = @_;
    $self->_consolidate( $c ? 1 : 0 );
    return $self;
}

sub set_full_reset {
    my ( $self, $fr ) = @_;
    $self->_full_reset( $fr ? 1 : 0 );
    return $self;
}

sub set_user_prompt {
    my ( $self, $up ) = @_;
    $self->_user_prompt($up);
    return $self;
}

#
# set_isolated — mark this context as isolated. Entering it wipes
# conversation history.
#
# When isolated=1 and the context is entered via change_context, the
# runtime wipes the conversation array. The model starts fresh with only
# the new context's system_prompt + step instructions, with no memory of
# prior turns.
#
# EXCEPTION — reset overrides the wipe:
#   If the context also has a reset configuration (via set_consolidate
#   or set_full_reset), the wipe is skipped in favor of the reset
#   behavior. Use reset with consolidate=1 to summarize prior history
#   into a single message instead of dropping it entirely.
#
# Use cases: switching to a sensitive billing flow that should not see
# prior small-talk; handing off to a different agent persona; resetting
# after a long off-topic detour.
#
sub set_isolated {
    my ( $self, $iso ) = @_;
    $self->_isolated( $iso ? 1 : 0 );
    return $self;
}

sub add_system_section {
    my ( $self, $title, $body ) = @_;
    die "Cannot add POM sections for system prompt when set_system_prompt() has been used"
        if defined $self->_system_prompt;
    push @{ $self->_system_prompt_sections }, { title => $title, body => $body };
    return $self;
}

sub add_system_bullets {
    my ( $self, $title, $bullets ) = @_;
    die "Cannot add POM sections for system prompt when set_system_prompt() has been used"
        if defined $self->_system_prompt;
    push @{ $self->_system_prompt_sections }, { title => $title, bullets => $bullets };
    return $self;
}

sub set_prompt {
    my ( $self, $prompt ) = @_;
    die "Cannot use set_prompt() when POM sections have been added"
        if @{ $self->_prompt_sections };
    $self->_prompt_text($prompt);
    return $self;
}

sub add_section {
    my ( $self, $title, $body ) = @_;
    die "Cannot add POM sections when set_prompt() has been used"
        if defined $self->_prompt_text;
    push @{ $self->_prompt_sections }, { title => $title, body => $body };
    return $self;
}

sub add_bullets {
    my ( $self, $title, $bullets ) = @_;
    die "Cannot add POM sections when set_prompt() has been used"
        if defined $self->_prompt_text;
    push @{ $self->_prompt_sections }, { title => $title, bullets => $bullets };
    return $self;
}

sub set_enter_fillers {
    my ( $self, $fillers ) = @_;
    $self->_enter_fillers($fillers) if ref $fillers eq 'HASH';
    return $self;
}

sub set_exit_fillers {
    my ( $self, $fillers ) = @_;
    $self->_exit_fillers($fillers) if ref $fillers eq 'HASH';
    return $self;
}

#
# set_history — set the default visibility mode for every step in this context.
#
# A step's own set_history() overrides this default. See Step->set_history for
# what each mode ("keep" / "default" / "hide") does. Dies unless $history is one
# of the three modes. Returns $self for chaining.
#
sub set_history {
    my ( $self, $history ) = @_;
    $self->_history( SignalWire::Contexts::_validate_history($history) );
    return $self;
}

sub add_enter_filler {
    my ( $self, $lang, $fillers ) = @_;
    if ( $lang && ref $fillers eq 'ARRAY' ) {
        $self->_enter_fillers( {} ) unless defined $self->_enter_fillers;
        $self->_enter_fillers->{$lang} = $fillers;
    }
    return $self;
}

sub add_exit_filler {
    my ( $self, $lang, $fillers ) = @_;
    if ( $lang && ref $fillers eq 'ARRAY' ) {
        $self->_exit_fillers( {} ) unless defined $self->_exit_fillers;
        $self->_exit_fillers->{$lang} = $fillers;
    }
    return $self;
}

sub _render_prompt {
    my ($self) = @_;
    return $self->_prompt_text if defined $self->_prompt_text;
    return unless @{ $self->_prompt_sections };
    return _render_sections( $self->_prompt_sections );
}

sub _render_system_prompt {
    my ($self) = @_;
    return $self->_system_prompt if defined $self->_system_prompt;
    return unless @{ $self->_system_prompt_sections };
    return _render_sections( $self->_system_prompt_sections );
}

sub _render_sections {
    my ($sections) = @_;
    my @parts;
    for my $sec (@$sections) {
        if ( exists $sec->{bullets} ) {
            push @parts, "## $sec->{title}";
            push @parts, map { "- $_" } @{ $sec->{bullets} };
        } else {
            push @parts, "## $sec->{title}";
            push @parts, $sec->{body};
        }
        push @parts, '';
    }
    my $text = join( "\n", @parts );
    $text =~ s/\s+$//;
    return $text;
}

sub to_hash {
    my ($self) = @_;
    die "Context '" . $self->name . "' has no steps defined"
        unless keys %{ $self->_steps };

    my %d = ( steps => [ map { $self->_steps->{$_}->to_hash } @{ $self->_step_order } ], );

    $d{valid_contexts} = $self->_valid_contexts if defined $self->_valid_contexts;
    $d{valid_steps}    = $self->_valid_steps    if defined $self->_valid_steps;
    $d{initial_step}   = $self->_initial_step   if defined $self->_initial_step;
    $d{post_prompt}    = $self->_post_prompt    if defined $self->_post_prompt;

    my $sp = $self->_render_system_prompt;
    $d{system_prompt} = $sp if defined $sp;

    $d{consolidate} = JSON::true          if $self->_consolidate;
    $d{full_reset}  = JSON::true          if $self->_full_reset;
    $d{user_prompt} = $self->_user_prompt if defined $self->_user_prompt;
    $d{isolated}    = JSON::true          if $self->_isolated;

    if ( @{ $self->_prompt_sections } ) {
        $d{pom} = $self->_prompt_sections;
    } elsif ( defined $self->_prompt_text ) {
        $d{prompt} = $self->_prompt_text;
    }

    $d{enter_fillers} = $self->_enter_fillers if defined $self->_enter_fillers;
    $d{exit_fillers}  = $self->_exit_fillers  if defined $self->_exit_fillers;
    $d{history}       = $self->_history       if defined $self->_history;

    return \%d;
}

# ==========================================================================
# ContextBuilder
# ==========================================================================
#
# SignalWire::Contexts::ContextBuilder
#
# Builder for multi-step, multi-context AI agent workflows.
#
# A ContextBuilder owns one or more Contexts; each Context owns an ordered
# list of Steps. Only one context and one step is active at a time. Per
# chat turn, the runtime injects the current step's instructions as a
# system message, then asks the LLM for a response.
#
# Native tools auto-injected by the runtime:
#
#   When a step (or its enclosing context) declares valid_steps or
#   valid_contexts, the runtime auto-injects two native tools so the
#   model can navigate the flow:
#
#     - next_step(step => enum)       — present when valid_steps is set
#     - change_context(context => enum) — present when valid_contexts is set
#
#   A third native tool — gather_submit — is injected during gather_info
#   questioning. These three names are reserved: ContextBuilder->validate
#   rejects any agent that defines a SWAIG tool with one of these names.
#   See %SignalWire::Contexts::RESERVED_NATIVE_TOOL_NAMES.
#
# Function whitelisting (Step->set_functions):
#
#   Each step may declare a functions whitelist. The whitelist is applied
#   in-memory at the start of each LLM turn. CRITICALLY: if a step does
#   NOT declare a functions field, it INHERITS the previous step's active
#   set. See Step->set_functions for details and examples.
#
package SignalWire::Contexts::ContextBuilder;
use Moo;
use JSON         ();
use Scalar::Util ();

has '_contexts'      => ( init_arg => undef, is => 'rw', default => sub { {} } );
has '_context_order' => ( init_arg => undef, is => 'rw', default => sub { [] } );

# Weak reference to the owning agent so validate() can check
# user-defined tool names against RESERVED_NATIVE_TOOL_NAMES. Set via
# attach_agent(); AgentBase->define_contexts wires this up automatically.
has '_agent' => ( is => 'rw', default => sub { undef } );

sub attach_agent {
    my ( $self, $agent ) = @_;
    $self->_agent($agent);
    Scalar::Util::weaken( $self->{_agent} ) if defined $agent;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->_contexts( {} );
    $self->_context_order( [] );
    return $self;
}

sub add_context {
    my ( $self, $name ) = @_;
    die "Context '$name' already exists" if exists $self->_contexts->{$name};
    die "Maximum number of contexts ($SignalWire::Contexts::MAX_CONTEXTS) exceeded"
        if keys %{ $self->_contexts } >= $SignalWire::Contexts::MAX_CONTEXTS;

    my $ctx = SignalWire::Contexts::Context->new( name => $name );
    $self->_contexts->{$name} = $ctx;
    push @{ $self->_context_order }, $name;
    return $ctx;
}

sub get_context {
    my ( $self, $name ) = @_;
    return $self->_contexts->{$name};
}

sub has_contexts {
    my ($self) = @_;
    return scalar( keys %{ $self->_contexts } ) ? 1 : 0;
}

sub validate {
    my ($self) = @_;
    die "At least one context must be defined" unless keys %{ $self->_contexts };

    # Single context must be "default"
    if ( keys %{ $self->_contexts } == 1 ) {
        my ($name) = keys %{ $self->_contexts };
        die 'When using a single context, it must be named "default"'
            unless $name eq 'default';
    }

    # Each context must have steps
    for my $cname ( keys %{ $self->_contexts } ) {
        my $ctx = $self->_contexts->{$cname};
        die "Context '$cname' must have at least one step"
            unless keys %{ $ctx->_steps };
    }

    # Validate initial_step references a real step in the context
    for my $cname ( keys %{ $self->_contexts } ) {
        my $ctx = $self->_contexts->{$cname};
        if ( defined $ctx->_initial_step ) {
            die "Context '$cname' has initial_step='${\$ctx->_initial_step}' "
                . "but that step does not exist. Available steps: ["
                . join( ', ', map { "'$_'" } sort keys %{ $ctx->_steps } ) . "]"
                unless exists $ctx->_steps->{ $ctx->_initial_step };
        }
    }

    # Validate step references in valid_steps
    for my $cname ( keys %{ $self->_contexts } ) {
        my $ctx = $self->_contexts->{$cname};
        for my $sname ( keys %{ $ctx->_steps } ) {
            my $step = $ctx->_steps->{$sname};
            if ( defined $step->_valid_steps ) {
                for my $vs ( @{ $step->_valid_steps } ) {
                    next if $vs eq 'next';
                    die "Step '$sname' in context '$cname' references unknown step '$vs'"
                        unless exists $ctx->_steps->{$vs};
                }
            }
        }
    }

    # Validate context references (context-level and step-level)
    for my $cname ( keys %{ $self->_contexts } ) {
        my $ctx = $self->_contexts->{$cname};
        if ( defined $ctx->_valid_contexts ) {
            for my $vc ( @{ $ctx->_valid_contexts } ) {
                die "Context '$cname' references unknown context '$vc'"
                    unless exists $self->_contexts->{$vc};
            }
        }
        for my $sname ( keys %{ $ctx->_steps } ) {
            my $step = $ctx->_steps->{$sname};
            if ( defined $step->_valid_contexts ) {
                for my $vc ( @{ $step->_valid_contexts } ) {
                    die "Step '$sname' in context '$cname' references unknown context '$vc'"
                        unless exists $self->_contexts->{$vc};
                }
            }
        }
    }

    # Validate gather_info
    for my $cname ( keys %{ $self->_contexts } ) {
        my $ctx = $self->_contexts->{$cname};
        for my $sname ( keys %{ $ctx->_steps } ) {
            my $step = $ctx->_steps->{$sname};
            if ( defined $step->_gather_info ) {
                die "Step '$sname' in context '$cname' has gather_info with no questions"
                    unless @{ $step->_gather_info->_questions };

                my %seen;
                for my $q ( @{ $step->_gather_info->_questions } ) {
                    die
"Step '$sname' in context '$cname' has duplicate gather_info question key '${\$q->key}'"
                        if $seen{ $q->key }++;
                }

                my $action = $step->_gather_info->_completion_action;
                if ( defined $action ) {
                    if ( $action eq 'next_step' ) {
                        my $idx;
                        my @order = @{ $ctx->_step_order };
                        for my $i ( 0 .. $#order ) {
                            if ( $order[$i] eq $sname ) { $idx = $i; last }
                        }
                        die "Step '$sname' in context '$cname' has gather_info "
                            . "completion_action='next_step' but it is the last "
                            . "step in the context. Either "
                            . "(1) add another step after '$sname', "
                            . "(2) set completion_action to the name of an "
                            . "existing step in this context to jump to it, or "
                            . "(3) set completion_action=undef (default) to "
                            . "stay in '$sname' after gathering completes."
                            if defined $idx && $idx >= $#order;
                    } elsif ( !exists $ctx->_steps->{$action} ) {
                        my @available = sort keys %{ $ctx->_steps };
                        die "Step '$sname' in context '$cname' has gather_info "
                            . "completion_action='$action' but '$action' is not "
                            . "a step in this context. Valid options: "
                            . "'next_step' (advance to the next sequential "
                            . "step), undef (stay in the current step), or "
                            . "one of ["
                            . join( ', ', map { "'$_'" } @available ) . "].";
                    }
                }
            }
        }
    }

    # Validate that user-defined tools do not collide with reserved
    # native tool names. The runtime auto-injects next_step /
    # change_context / gather_submit when contexts/steps are present, so
    # user tools sharing those names would never be called.
    if ( defined $self->_agent && $self->_agent->can('list_tool_names') ) {
        my @registered = $self->_agent->list_tool_names;
        my @colliding;
        for my $name (@registered) {
            push @colliding, $name
                if exists $SignalWire::Contexts::RESERVED_NATIVE_TOOL_NAMES{$name};
        }
        if (@colliding) {
            my @sorted   = sort @colliding;
            my @reserved = sort keys %SignalWire::Contexts::RESERVED_NATIVE_TOOL_NAMES;
            die "Tool name(s) ["
                . join( ', ', map { "'$_'" } @sorted )
                . "] collide with reserved native tools auto-injected by "
                . "contexts/steps. The names ["
                . join( ', ', map { "'$_'" } @reserved )
                . "] are reserved and cannot be used for user-defined SWAIG "
                . "tools when contexts/steps are in use. Rename your "
                . "tool(s) to avoid the collision.";
        }
    }

    # STRICT-RENDER GAP2 (r5 F3): a step's set_functions([...]) whitelist entry
    # that is neither a registered SWAIG tool nor a reserved native tool is a
    # DANGLING reference — the step would render an active-function set pointing
    # at nothing (get_datetime vs get_current_time). Only enforce when a real
    # tool registry is present (an agent that can list its tools); a builder
    # with no agent cannot know the tool universe and must not red a valid
    # document. "none"/[] (disable-all) are not lists of references to resolve.
    if ( defined $self->_agent && $self->_agent->can('list_tool_names') ) {
        my %known = map { $_ => 1 } $self->_agent->list_tool_names;
        $known{$_} = 1 for keys %SignalWire::Contexts::RESERVED_NATIVE_TOOL_NAMES;
        for my $cname ( keys %{ $self->_contexts } ) {
            my $ctx = $self->_contexts->{$cname};
            for my $sname ( keys %{ $ctx->_steps } ) {
                my $step  = $ctx->_steps->{$sname};
                my $funcs = $step->_functions;

                # Only an explicit arrayref whitelist is a list of references.
                # undef (inherit), "none", or a scalar disable-all are skipped.
                next unless ref $funcs eq 'ARRAY';
                for my $fn (@$funcs) {
                    next if $known{$fn};
                    my @available = sort keys %known;
                    die "Step '$sname' in context '$cname' whitelists function "
                        . "'$fn' via set_functions(), but no such SWAIG tool is "
                        . "registered on the agent and it is not a reserved native "
                        . "tool. This would emit a dangling function reference. "
                        . "Register the tool (define_tool / a skill) or remove it "
                        . "from the step. Available: ["
                        . join( ', ', map { "'$_'" } @available ) . "]";
                }
            }
        }
    }
    return;
}

sub to_hash {
    my ($self) = @_;
    $self->validate;

    my %result;
    for my $cname ( @{ $self->_context_order } ) {
        $result{$cname} = $self->_contexts->{$cname}->to_hash;
    }
    return \%result;
}

# Back to main package
package SignalWire::Contexts;

# Python parity: signalwire.core.contexts.create_simple_context(name='default')
# is a module-level free function. Perl invocation forms supported:
#   - SignalWire::Contexts::create_simple_context('mycontext')   # free fn
#   - SignalWire::Contexts->create_simple_context('mycontext')   # class method
# Both forms collapse to a single optional ``$name`` argument.
sub create_simple_context {    ## no critic (Subroutines::RequireArgUnpacking)

    # The regex signature extractor reads this exact ``my ($name) = @_;`` first
    # line to emit the audited ``name`` param; and the dual free-fn / class-
    # method calling convention needs @_/shift to drop a possible receiver.
    # Unpacking into ``@args`` would rename the audited param and move the
    # surface, so RequireArgUnpacking is suppressed here (parity, not laziness).
    # Drop a class-method receiver BEFORE unpacking, so ``$name`` below is
    # always the caller's real argument whichever spelling was used. Doing it
    # here (rather than after the unpack) lets the parameter's own default be
    # the sub's FIRST statement about it: the audit reads the prologue for the
    # declared default, a default stated after a branch is invisible there, and
    # this one has to match the reference's ``name: str = "default"``.
    shift if @_ && defined $_[0] && !ref( $_[0] ) && $_[0] eq __PACKAGE__;

    my ($name) = @_;
    $name //= 'default';

    return SignalWire::Contexts::Context->new( name => $name );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Contexts - multi-step, multi-context AI agent workflow DSL

=head1 SYNOPSIS

    use SignalWire::Contexts;

    my $builder = SignalWire::Contexts::ContextBuilder->new;

    my $ctx = $builder->add_context('default');
    $ctx->set_isolated(0);

    my $step = $ctx->add_step('greet',
        task    => 'Greet the caller and find out why they called.',
        bullets => [ 'Be warm', 'Ask an open question' ],
    );
    $step->set_valid_steps( [ 'collect' ] );

    my $collect = $ctx->add_step('collect');
    $collect->add_section('Task', 'Collect the caller details.');
    $collect->set_gather_info( output_key => 'caller' );
    $collect->add_gather_question( key => 'name',  question => 'Your name?' );
    $collect->add_gather_question( key => 'email', question => 'Your email?' );
    $collect->set_end(1);

    my $swml = $builder->to_hash;   # validates, then serializes

    # Convenience free function / class method:
    my $simple = SignalWire::Contexts::create_simple_context('default');

=head1 DESCRIPTION

This file defines the Perl port of C<signalwire.core.contexts> — the DSL
for building multi-step, multi-context AI agent workflows. Loading it
defines several cooperating packages in one shot:

=over 4

=item C<SignalWire::Contexts::ContextBuilder>

The top-level builder. Owns one or more contexts; C<validate>/C<to_hash>
check the whole workflow and serialize it.

=item C<SignalWire::Contexts::Context>

A named context owning an ordered list of steps, plus context-level prompt,
history, filler, and reset configuration.

=item C<SignalWire::Contexts::Step>

A single step within a context: its instruction text (or POM sections),
step criteria, function whitelist, navigation targets, gather-info, reset,
and history settings.

=item C<SignalWire::Contexts::GatherInfo> and
C<SignalWire::Contexts::GatherQuestion>

The structured question-gathering payload attached to a step, and one
question within it.

=back

Only one context and one step is active at a time; per chat turn the
runtime injects the current step's instructions as a system message. Most
setters return C<$self> for fluent chaining.

=head2 Package constants

C<$MAX_CONTEXTS> (50) and C<$MAX_STEPS_PER_CONTEXT> (100) bound the
workflow size. C<%RESERVED_NATIVE_TOOL_NAMES> holds the runtime-injected
tool names (C<next_step>, C<change_context>, C<gather_submit>) that
user-defined SWAIG tools must not collide with. C<@HISTORY_MODES> lists the
valid step/context history visibility modes (C<keep>, C<default>, C<hide>).

=head1 FUNCTIONS

=over 4

=item C<create_simple_context($name)>

The Perl analog of Python's C<create_simple_context>. Returns a new
L</SignalWire::Contexts::Context> named C<$name> (default C<'default'>).
Callable both as a free function
(C<< SignalWire::Contexts::create_simple_context('x') >>) and as a class
method (C<< SignalWire::Contexts->create_simple_context('x') >>).

=back

=head1 METHODS

Because five packages share this one file, every method below is labelled
with the class it belongs to. Three names are declared on more than one
class — C<add_section>, C<add_bullets> and C<set_history> exist on both
C<Step> and C<Context>, and C<to_hash> exists on four of the five — and the
two implementations are B<not> interchangeable, so read the class heading
before the method.

Unless a method's entry says otherwise it returns C<$self>, so calls chain.
Every error in this module is raised with C<die> (a plain string, no
exception class), so callers wrap in C<eval> to catch.

=head2 ContextBuilder — workflow assembly

The top-level builder. C<< SignalWire::Contexts::ContextBuilder->new >>
takes no arguments; the contexts hash and its insertion order start empty.

=over 4

=item C<< $builder->add_context($name) >>

Create a new L</Context> called C<$name>, register it, and append it to the
insertion order. B<Returns the new Context, not C<$builder>> — this is the
one builder method that breaks the fluent-C<$self> pattern, because you
almost always want to keep configuring the context you just made. Dies if
C<$name> is already taken, or if the builder already holds
C<$MAX_CONTEXTS> (50) contexts. The name is the only argument: a context's
prompt is set on the returned object via C<set_prompt> / C<add_section>.

=item C<< $builder->get_context($name) >>

Return the L</Context> registered under C<$name>, or C<undef> if there is
none. Does not create anything and does not die on a miss.

=item C<< $builder->has_contexts() >>

Return C<1> if at least one context is registered, C<0> otherwise. A plain
boolean, not a count — callers wanting the count should use
C<< scalar keys >> on the result of their own bookkeeping.

=item C<< $builder->reset() >>

Drop every registered context and clear the insertion order, returning the
builder to its just-constructed state. The attached agent (see
C<attach_agent>) is B<not> cleared, so a builder reset mid-configuration
keeps validating tool names against the same agent.

=item C<< $builder->attach_agent($agent) >>

Record the owning agent so C<validate> can cross-check step function
whitelists and reserved tool names against the agent's real tool registry.
The reference is B<weakened> immediately, so attaching does not keep the
agent alive and does not create a reference cycle between agent and
builder. C<< AgentBase->define_contexts >> wires this up for you; you only
call it directly when constructing a builder outside an agent. Passing
C<undef> clears the agent (the weaken is skipped in that case).

=item C<< $builder->validate() >>

Check the whole workflow and die on the first problem found. B<Returns
nothing> (an empty list) — it is called for its exceptions, so C<validate>
is the one non-chainable method here. The checks, in the order they run:

=over 4

=item *

At least one context must exist.

=item *

If there is B<exactly one> context, it must be named C<default>. Two or
more contexts may be named anything.

=item *

Every context must own at least one step.

=item *

A context's C<initial_step>, if set, must name a step that exists in that
same context. The error lists the available step names.

=item *

Every entry in a step's C<valid_steps> must name a step in the B<same>
context. The literal string C<next> is exempt — it is the runtime's
"advance sequentially" token, not a step name.

=item *

Every entry in a context-level or step-level C<valid_contexts> must name a
registered context.

=item *

A step's C<gather_info>, if present, must hold at least one question, and
the question keys must be unique within that step.

=item *

A C<gather_info> C<completion_action> must be one of: C<next_step> (and
then the step must not be the last in its context's order), C<undef>
(stay put), or the name of a step in the same context.

=item *

If an agent is attached and can C<list_tool_names>, no registered tool may
be named C<next_step>, C<change_context> or C<gather_submit> — those are
injected by the runtime and a user tool of the same name would never be
reached. The error names every colliding tool.

=item *

If an agent is attached, every name in a step's C<set_functions> B<array>
whitelist must be either a registered tool or a reserved native name;
otherwise the step would emit a dangling function reference. Only an
arrayref is checked — C<undef> (inherit) and the C<"none"> disable-all
string are not lists of references to resolve. Without an attached agent
this check is skipped entirely, because a bare builder cannot know the
tool universe and must not reject a valid document.

=back

=item C<< $builder->to_hash() >>

Run C<validate> (so C<to_hash> dies on any of the problems above), then
serialize to a hashref keyed by context name, each value being that
context's C<to_hash>. The contexts are walked in B<insertion order>, so a
JSON encoder that preserves hash construction order emits them in the order
you added them.

=back

=head2 Context — a named group of steps

Constructed via C<< $builder->add_context >>, not directly. Carries a
read-only C<name> plus context-level prompt, history, filler and reset
settings that apply to every step it owns.

=over 4

=item C<< $ctx->add_step($name, %opts) >>

Create a L</Step> named C<$name>, register it, and append it to the step
order. B<Returns the new Step, not C<$ctx>>. Dies if the step name is
already used in this context, or if the context already holds
C<$MAX_STEPS_PER_CONTEXT> (100) steps.

C<%opts> is a convenience shorthand that forwards to the step's own
setters, each applied only when the key is defined: C<task> becomes
C<< $step->add_section('Task', ...) >>, C<bullets> becomes
C<< $step->add_bullets('Process', ...) >>, and C<criteria>, C<functions>
and C<valid_steps> forward to C<set_step_criteria>, C<set_functions> and
C<set_valid_steps>. Any other key is silently ignored — notably there is
B<no> C<text> or C<valid_contexts> shorthand, so those must be set on the
returned step. Because C<task>/C<bullets> go through the section path, a
step created with either of them cannot afterwards use C<set_text>.

=item C<< $ctx->get_step($name) >>

Return the L</Step> registered under C<$name>, or C<undef> if there is
none.

=item C<< $ctx->remove_step($name) >>

Delete the step and drop it from the step order. A name that is not present
is B<silently accepted> as a no-op rather than dying. Note that this does
not scrub references: another step's C<valid_steps>, or the context's
C<initial_step>, may still point at the removed name, and that only
surfaces later as a C<validate> failure.

=item C<< $ctx->move_step($name, $position) >>

Reorder an existing step by removing it from the order and splicing it back
in at index C<$position> (0-based, computed against the list with C<$name>
already removed). Dies if C<$name> is not a step in this context.
C<$position> itself is B<not> range-checked: it is handed to C<splice>, so a
negative index counts from the end and an index past the end appends.

=item C<< $ctx->set_initial_step($step_name) >>

Set which step the context starts on when it is entered. Without this a
context starts on the first step in its order. Useful to skip a preamble
step when re-entering a context via C<change_context>. The name is not
checked here — a step that does not exist is caught later by C<validate>.

=item C<< $ctx->set_prompt($prompt) >>

Set the context prompt as a single block of text. Dies if any prompt POM
section has already been added via C<add_section>/C<add_bullets> — text and
sections are mutually exclusive for the context prompt.

=item C<< $ctx->add_section($title, $body) >>

Append a prompt POM section with a title and a body string. Dies if
C<set_prompt> has already been used. Note this is the B<Context>
C<add_section> — the same-named C<Step> method fills the step's instruction
text instead.

=item C<< $ctx->add_bullets($title, $bullets) >>

Append a prompt POM section whose body is the arrayref C<$bullets>,
rendered as a bullet list. Dies if C<set_prompt> has already been used.

=item C<< $ctx->set_system_prompt($sp) >>

Set the context's system prompt as one block of text. Dies if a system
prompt section has already been added via C<add_system_section> /
C<add_system_bullets>. This is tracked separately from C<set_prompt>: a
context may have both a system prompt and a prompt.

=item C<< $ctx->add_system_section($title, $body) >> / C<< $ctx->add_system_bullets($title, $bullets) >>

Append a titled system-prompt POM section carrying a body string or a
bullet arrayref respectively. Either dies if C<set_system_prompt> has
already been used. Unlike the prompt sections, system-prompt sections are
B<rendered to markdown> before serialization (C<## Title> followed by the
body or C<- bullet> lines) and emitted as the C<system_prompt> string.

=item C<< $ctx->set_user_prompt($up) >>

Set the context's C<user_prompt> string, emitted verbatim. No validation,
no interaction with the section machinery.

=item C<< $ctx->set_post_prompt($pp) >>

Set the context's C<post_prompt>, emitted verbatim when defined.

=item C<< $ctx->set_valid_steps($steps) >> / C<< $ctx->set_valid_contexts($contexts) >>

Set the context-level navigation whitelists, each an arrayref of names,
stored and emitted as given. Declaring either causes the runtime to inject
the corresponding native tool (C<next_step> / C<change_context>). Both are
checked by C<validate>, which resolves C<valid_contexts> entries against
the registered contexts; C<valid_steps> is validated per-B<step>, not here.

=item C<< $ctx->set_isolated($iso) >>

Coerce C<$iso> to 1/0 and mark the context isolated. Entering an isolated
context via C<change_context> makes the runtime wipe the conversation
array, so the model starts fresh with only the new context's system prompt
and step instructions. B<Exception:> if the context also carries a reset
configuration (C<set_consolidate> or C<set_full_reset>), the wipe is
skipped in favour of the reset behaviour — use C<consolidate> to summarize
prior history into one message instead of dropping it. Emitted only when
true.

=item C<< $ctx->set_consolidate($c) >> / C<< $ctx->set_full_reset($fr) >>

Coerce to 1/0 and set the context-level reset flags, emitted only when
true. C<consolidate> summarizes prior conversation into a single message;
C<full_reset> resets it wholesale. Either one also suppresses the
C<set_isolated> wipe described above.

=item C<< $ctx->set_history($history) >>

Set the default history-visibility mode for every step in this context. A
step's own C<set_history> overrides it. C<$history> must be one of C<keep>,
C<default> or C<hide> — see the Step entry for what each does; anything
else (including C<undef>) dies with a message listing the three modes.

=item C<< $ctx->set_enter_fillers($fillers) >> / C<< $ctx->set_exit_fillers($fillers) >>

Replace the whole enter/exit filler map with C<$fillers>, a hashref keyed
by language tag (e.g. C<'en-US'>) whose values are arrayrefs of filler
phrases. B<A non-hashref argument is silently ignored> — the call still
returns C<$self> and the previous map is left untouched, so a typo here
fails quietly rather than dying.

=item C<< $ctx->add_enter_filler($lang, $fillers) >> / C<< $ctx->add_exit_filler($lang, $fillers) >>

Set one language's entry in the enter/exit filler map, creating the map if
it does not exist yet. C<$fillers> is an arrayref of phrases and B<replaces>
any phrases already stored for C<$lang> rather than appending to them.
Like the C<set_*> pair, a falsy C<$lang> or a non-arrayref C<$fillers> is
silently ignored.

=item C<< $ctx->to_hash() >>

Serialize the context. Dies if the context has no steps. Steps are emitted
under C<steps> in the context's step order. Optional keys appear only when
set: C<valid_contexts>, C<valid_steps>, C<initial_step>, C<post_prompt>,
C<user_prompt>, C<enter_fillers>, C<exit_fillers>, C<history>; the boolean
C<consolidate>, C<full_reset> and C<isolated> appear only when true.
C<system_prompt> is the rendered markdown of the system sections, or the
literal C<set_system_prompt> string. The context prompt is emitted as
B<either> C<pom> — the raw section arrayref, not rendered markdown — when
sections were used, B<or> C<prompt> when C<set_prompt> was used; sections
win if somehow both are present.

=back

=head2 Step — one instruction stage within a context

Constructed via C<< $ctx->add_step >>, not directly. Carries a read-only
C<name>.

=over 4

=item C<< $step->set_text($text) >>

Set the step's instruction text as one block. Dies if any POM section has
already been added via C<add_section>/C<add_bullets> — a step's text and its
sections are mutually exclusive. Remember that C<< add_step(task => ...) >>
adds a section, so a step created that way cannot use C<set_text> until
C<clear_sections> is called.

=item C<< $step->add_section($title, $body) >>

Append a titled instruction section with a body string. Dies if
C<set_text> has already been used. This is the B<Step> C<add_section>; the
C<Context> method of the same name populates the context prompt instead.

=item C<< $step->add_bullets($title, $bullets) >>

Append a titled instruction section whose body is the arrayref C<$bullets>,
rendered as C<- item> lines. Dies if C<set_text> has already been used.

=item C<< $step->clear_sections() >>

Drop every POM section B<and> clear any text set by C<set_text>. This is
the escape hatch out of the text-vs-sections lock: after calling it either
mode is available again. Note that a step left in this state with neither
text nor sections dies at serialization time.

=item C<< $step->set_step_criteria($criteria) >>

Set the natural-language criteria describing when this step is complete,
emitted verbatim as C<step_criteria>.

=item C<< $step->set_functions($functions) >>

Set which non-internal functions are callable while this step is active.
C<$functions> is an arrayref of tool names (a whitelist), an empty arrayref
(explicit disable-all), or the string C<"none"> (a synonym for the empty
list). The value is stored and emitted as-is; when an agent is attached,
C<< ContextBuilder->validate >> rejects an arrayref entry that names no
registered or reserved tool.

B<Inheritance is the trap here:> a step that does not call this method
inherits whichever function set was active on the previous step — or on the
previous context's last step. The runtime resets the active set only when a
step explicitly declares its C<functions> field, so a forgotten
C<set_functions> on a later step lets the earlier step's tools leak
through. Declare it explicitly on every step whose tool set should differ.
Keep the per-step set small: model tool-selection accuracy degrades past
roughly seven or eight simultaneously-active tools.

Internal functions such as C<gather_submit> and C<hangup_hook> are always
protected and cannot be switched off by this whitelist, and the native
C<next_step> / C<change_context> tools are injected independently — none of
them need to appear in the list.

=item C<< $step->set_valid_steps($steps) >> / C<< $step->set_valid_contexts($contexts) >>

Set this step's navigation whitelists, each an arrayref of names, stored
and emitted as given, and overriding the context-level equivalents.
Declaring either causes the runtime to inject the matching native tool.
C<validate> resolves every C<valid_steps> entry against the steps of the
B<same> context, except the literal C<next>, and every C<valid_contexts>
entry against the registered contexts.

=item C<< $step->set_end($end) >>

Coerce C<$end> to 1/0 and mark the step terminal for the step flow; emitted
only when true. B<This does not end the conversation or hang up the call.>
It exits step mode after this step runs, clearing the steps list, the
current step index, C<valid_steps> and C<valid_contexts>. The agent keeps
running under the base system prompt and the context prompt, with no
further step instructions injected and no C<next_step> tool offered. To end
the call, invoke a hangup tool or define a hangup hook.

=item C<< $step->set_skip_user_turn($skip) >> / C<< $step->set_skip_to_next_step($skip) >>

Coerce to 1/0 and set the two flow-control flags, each emitted only when
true. C<skip_user_turn> runs the step without waiting for the caller to
speak; C<skip_to_next_step> advances past the step without an LLM turn.

=item C<< $step->set_gather_info(%opts) >>

Attach a fresh L</GatherInfo> to the step, B<replacing> any gather config
and questions already there. Recognised options are C<output_key>
(the key the collected answers are stored under), C<completion_action>
(C<next_step>, a sibling step name, or C<undef> to stay put),
C<prompt> (extra instruction text for the gather loop), and C<isolated>
(coerced to 1/0; emitted only when true). Any other key is ignored. Must
be called before C<add_gather_question>.

=item C<< $step->add_gather_question(%opts) >>

Append a question to the step's gather config. B<Dies unless
C<set_gather_info> was called first> — there is no implicit creation.
C<%opts> is forwarded to L</GatherInfo>'s C<add_question>: C<key> and
C<question> are required, C<type> defaults to C<'string'>, C<confirm>
defaults to false, and C<prompt>, C<functions> and C<isolated> default to
C<undef>.

While the model is working through gather questions the runtime forcibly
deactivates all of the step's other functions. The only callable tools are
C<gather_submit> and whatever names this question's C<functions> option
lists — and those are active for this question only. C<next_step> and
C<change_context> are filtered out too, so the model cannot navigate away
until the gather completes; that is deliberate, to force a tight
ask-submit-next loop. List a tool in C<functions> when a question needs to
call out mid-gather (validating an email, geocoding a ZIP).

=item C<< $step->set_reset_system_prompt($sp) >> / C<< $step->set_reset_user_prompt($up) >>

Set the system/user prompt to install when this step performs a context
reset. Both are emitted as C<system_prompt> / C<user_prompt> B<inside> the
step's C<reset> sub-hash, and only when defined.

=item C<< $step->set_reset_consolidate($c) >> / C<< $step->set_reset_full_reset($fr) >>

Coerce to 1/0 and set the step-level reset flags, emitted inside the
C<reset> sub-hash only when true. The C<reset> key itself is omitted
entirely unless at least one of these four C<set_reset_*> values is
present.

=item C<< $step->set_history($history) >>

Control what the model can still see when this step is entered, overriding
the context-level default. C<$history> must be one of:

=over 4

=item C<keep>

Clear nothing — every prior step's instructions B<and> the dialogue stay
visible.

=item C<default>

Hide prior step instructions, keep the dialogue. This is the behaviour when
history is never set.

=item C<hide>

Hide prior instructions B<and> pull the prior dialogue out of the model's
context; recover pieces of it with a C<${step_history.*}> reference in this
step's own text.

=back

Anything else, C<undef> included, dies with a message listing the three
modes. The mode applies at the moment the step is entered and governs
everything before it, including the turn that triggered the transition; it
does not affect the step's own accumulating turns. Nothing is deleted from
the call log — this only changes what the model sees.

=item C<< $step->to_hash() >>

Serialize the step. C<name> and C<text> are always present; C<text> is
either the C<set_text> string or the markdown rendering of the POM sections
(C<## Title> plus the body or C<- bullet> lines, trailing whitespace
trimmed), and this B<dies> if the step has neither. Optional keys appear
only when set: C<step_criteria>, C<functions>, C<valid_steps>,
C<valid_contexts>, C<history>, C<gather_info>, and the C<reset> sub-hash;
the booleans C<end>, C<skip_user_turn> and C<skip_to_next_step> appear only
when true.

=back

=head2 GatherInfo and GatherQuestion — structured question collection

Normally built for you by the step-level C<set_gather_info> and
C<add_gather_question>; construct them directly only when assembling a
gather payload outside a step.

=over 4

=item C<< $gather->add_question(%opts) >>

Build a C<GatherQuestion> from C<%opts> and append it. C<key> and
C<question> are required (the underlying attributes are C<required>, so
omitting either dies in the constructor); C<type> defaults to C<'string'>,
C<confirm> defaults to C<0>, and C<prompt>, C<functions> and C<isolated>
default to C<undef>. Returns the GatherInfo for chaining, B<not> the new
question.

=item C<< $gather->to_hash() >>

Serialize the gather config. B<Dies if no question has been added> — an
empty gather is never valid. Always emits C<questions>; adds C<prompt>,
C<output_key> and C<completion_action> when defined, and C<isolated> only
when true.

=item C<< $question->to_hash() >>

Serialize one question. Always emits C<key> and C<question>. C<type> is
emitted only when it differs from the C<'string'> default, C<confirm> only
when true, and C<prompt> / C<functions> only when defined. C<isolated> is
the exception: because it is tri-state — C<undef> means "inherit the
gather-level default" — it is emitted whenever it is B<defined>, including
as an explicit C<false>, so a single question can opt out of an isolated
gather.

=back

=head1 SEE ALSO

L<SignalWire::Contexts::ContextBuilder> (thin loader for this module),
L<SignalWire::Agent::AgentBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
