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

    $self->{_version}       = $args->{version}       ||= '1.0.0';
    $self->{_engine}        = $args->{engine}        ||= 'gcloud';
    $self->{_voice}         = $args->{voice};
    $self->{_params}        = $args->{params}        ||= {};
    $self->{_prompt}        = $args->{prompt}        ||= {};
    $self->{_hints}         = $args->{hints}         ||= [];
    $self->{_postPromptURL}          = $args->{postPromptURL};
    $self->{_postPromptAuthUser}     = $args->{postPromptAuthUser};
    $self->{_postPromptAuthPassword} = $args->{postPromptAuthPassword};
    $self->{_languages}              = $args->{lanuages};
    $self->{_SWAIG}                  = $args->{SWAIG}    ||= [];

    return bless($self, $class);
}

# This adds the ai application to the section provided in the args,
# taking all the previously set params and options for the AI and
# attaching them to the application.
sub addAIApplication {
    my $self    = shift;
    my $section = shift;
    my $app     = "ai";
    my $args    = {};

    $self->setVersion($self->{_version});

    foreach my $data ('postPrompt','voice', 'engine', 'postPromptURL', 'postPromptAuthUser',
		      'postPromptAuthPassword', 'languages', 'hints', 'params', 'prompt', 'SWAIG') {
	next unless $self->{"_$data"};
	$args->{$data} = $self->{"_$data"};
    }
    push @{$self->{_content}->{sections}->{$section} },  { $app =>  $args };

    return;
}

# add application to section, providing all the app args.
sub addApplication {
    my $self    = shift;
    my $section = shift;
    my $app     = shift;
    my $args    = shift;

    $self->setVersion($self->{_version});

    push @{$self->{_content}->{sections}->{$section} },  { $app =>  $args };

    return;
}

# set postUrl and optionally pass in postUser and postPassword
sub setAIpostPromptURL {
    my $self       = shift;
    my $postprompt = shift;

    while ( my ($k,$v) = each(%{$postprompt}) ) {
	$self->{"_$k"} = $postprompt->{$k};
    }

    return;
}

# Set params overriding any previously set params
sub setAIparams {
    my $self = shift;

    $self->{_params} = shift;

    return;
}

# Add one or more params
sub addAIparams {
    my $self   = shift;
    my $params = shift;

    while ( my ($k,$v) = each(%{$params}) ) {
	$self->{_params}->{$k} = $v;
    }

    return;
}

# Set hints overriding any previously set hints
sub setAIhints {
    my $self  = shift;
    my @hints = @_;

    $self->{_hints} = \@hints;

    return;
}

# Add hints, and make sure they are uniq
sub addAIhints {
    my $self  = shift;
    my @hints = @_;
    my %seen;

    push  @{ $self->{_hints} }, @hints;
    @{ $self->{_hints} } = grep { !$seen{$_}++ } @{ $self->{_hints} };

    return;
}

# Set document version
sub setVersion {
    my $self     = shift;
    my $version  = shift;

    $self->{_content}->{version} = $version ? $version : $self->{_version};

    return;
}

sub addAISWAIG {
    my $self  = shift;
    my $SWAIG = shift;

    @{ $self->{_SWAIG} } = (@{ $self->{_SWAIG} }, $SWAIG);

    return;
}

# Add language appending to the list
sub addAIlanguage {
    my $self     = shift;
    my $language = shift;

    @{ $self->{_languages} } = (@{ $self->{_languages} }, $language);

    return;
}

# set lanugages overriding previous languages
sub setAIlanguage {
    my $self     = shift;
    my $language = shift;

    $self->{_languages} = $language;

    return;
}

#set postPrompt
sub setAIpostPrompt {
    my $self       = shift;
    my $postprompt = shift;

    while ( my ($k,$v) = each(%{$postprompt}) ) {
	$self->{_postPrompt}->{$k} = $v;
    }

    return;
}

# set prompt
sub setAIprompt {
    my $self   = shift;
    my $prompt = shift;

    while ( my ($k,$v) = each(%{$prompt}) ) {
	$self->{_prompt}->{$k} = $v;
    }

    return;
}

# Render the object to JSON;
sub renderJSON {
    my $self = shift;
    my $json = JSON->new->allow_nonref;

    return $json->pretty->utf8->encode( $self->{_content} )
}

# Render the object to YAML;
sub renderYAML {
    my $self = shift;

    return Dump $self->{_content};
}

1;
