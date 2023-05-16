package SignalWire::ML;

use strict;
use warnings;
use JSON;
use YAML qw(Dump Bless);;
use Data::Dumper;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);

our $VERSION = '1.0';
our $AUTOLOAD;

sub new {
    my $proto = shift;
    my $args  = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{_content}->{version} = $args->{version} ||= '1.0.0';
    $self->{_content}->{engine}  = $args->{engine}  ||= 'gcloud';
    $self->{_voice}              = $args->{voice}   ||= undef;
    $self->{_SWAIG}->{functions} = [];
    $self->{_SWAIG}->{defaults}  = {};
    return bless($self, $class);
}

# This adds the ai application to the section provided in the args,
# taking all the previously set params and options for the AI and
# attaching them to the application.
sub add_aiapplication {
    my $self    = shift;
    my $section = shift;
    my $app     = "ai";
    my $args    = {};

    foreach my $data ('post_prompt','voice', 'engine', 'post_prompt_url', 'post_prompt_auth_user',
		      'post_prompt_auth_password', 'languages', 'hints', 'params', 'prompt', 'SWAIG') {
	next unless $self->{"_$data"};
	$args->{$data} = $self->{"_$data"};
    }
    push @{$self->{_content}->{sections}->{$section} },  { $app =>  $args };

    return;
}

# add application to section, providing all the app args.
sub add_application {
    my $self    = shift;
    my $section = shift;
    my $app     = shift;
    my $args    = shift;

    push @{$self->{_content}->{sections}->{$section} },  { $app =>  $args };

    return;
}

# set post_url and optionally pass in post_user and post_password
sub set_aipost_prompt_url {
    my $self       = shift;
    my $postprompt = shift;

    while ( my ($k,$v) = each(%{$postprompt}) ) {
	$self->{"_$k"} = $postprompt->{$k};
    }

    return;
}

# Set params overriding any previously set params
sub set_aiparams {
    my $self = shift;

    $self->{_params} = shift;

    return;
}

# Add one or more params
sub add_aiparams {
    my $self   = shift;
    my $params = shift;

    while ( my ($k,$v) = each(%{$params}) ) {
	$self->{_params}->{$k} = $v;
    }

    return;
}

# Set hints overriding any previously set hints
sub set_aihints {
    my $self  = shift;
    my @hints = @_;

    $self->{_hints} = \@hints;

    return;
}

# Add hints, and make sure they are uniq
sub add_aihints {
    my $self  = shift;
    my @hints = @_;
    my %seen;

    push  @{ $self->{_hints} }, @hints;
    @{ $self->{_hints} } = grep { !$seen{$_}++ } @{ $self->{_hints} };

    return;
}

sub add_aiswaigdefaults {
    my $self  = shift;
    my $SWAIG = shift;

    while ( my ($k,$v) = each(%{$SWAIG}) ) {
	$self->{_SWAIG}->{defaults}->{$k} = $v;
    }

    return;
}

sub add_aiswaigfunction {
    my $self  = shift;
    my $SWAIG = shift;

    @{ $self->{_SWAIG}->{functions} } = (@{ $self->{_SWAIG}->{functions} }, $SWAIG);

    return;
}

# Add language appending to the list
sub add_ailanguage {
    my $self     = shift;
    my $language = shift;

    @{ $self->{_languages} } = (@{ $self->{_languages} }, $language);

    return;
}

# set lanugages overriding previous languages
sub set_ailanguage {
    my $self     = shift;
    my $language = shift;

    $self->{_languages} = $language;

    return;
}

#set post_prompt
sub set_aipost_prompt {
    my $self       = shift;
    my $postprompt = shift;

    while ( my ($k,$v) = each(%{$postprompt}) ) {
	$self->{_postPrompt}->{$k} = $v;
    }

    return;
}

# set prompt
sub set_aiprompt {
    my $self   = shift;
    my $prompt = shift;

    while ( my ($k,$v) = each(%{$prompt}) ) {
	$self->{_prompt}->{$k} = $v;
    }

    return;
}

# Reply a SWAIG response with optional SWML if sections exist.
sub SWAIGResponse {
    my $self     = shift;
    my $response = shift;
    my $json     = JSON->new->allow_nonref;

    if($self->{_content}->{sections}) {
	$response->{SWML} = $self->{_content};
    }

    return $json->pretty->utf8->encode( $response )
}

# Render the object to JSON;
sub render_json {
    my $self = shift;
    my $json = JSON->new->allow_nonref;

    return $json->pretty->utf8->encode( $self->{_content} )
}

# Render the object to YAML;
sub render_yaml {
    my $self = shift;

    return Dump $self->{_content};
}

1;
