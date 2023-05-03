package SignalWire::SWML;

use strict;
use warnings;
use JSON;
use Data::Dumper;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);

our $VERSION = '1.0';
our $AUTOLOAD;

sub new {
    my $proto = shift;
    my $args  = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{_version}      = $args->{version}       ||= '1.0.0';
    $self->{_engine}       = $args->{engine}        ||= 'gcloud';
    $self->{_voice}        = $args->{voice}         ||= 'en-US-Neural2-F';
    $self->{_params}       = $args->{params}        ||= {};
    $self->{_prompt}       = $args->{prompt}        ||= {};
    $self->{_hints}        = $args->{hints}         ||= [];
    $self->{_postUrl}      = $args->{postUrl};
    $self->{_postUser}     = $args->{postUser};
    $self->{_postPassword} = $args->{postPassword};
    $self->{_languages}    = $args->{lanuages}      ||= [];
    $self->{_SWAIG}        = $args->{SWAIG}         ||= [];
    
    return bless($self, $class);
}

# Not sure we need this
#sub addSection {
#    my $self    = shift;
#    my $section = shift;
#
#    $self->setVersion($self->{_version});
#    $self->{_content}->{sections}->{$section} = {};
#
#    return;
#}

# This adds the ai application to the section provided in the args,
# taking all the previously set params and options for the AI and
# attaching them to the application.
sub addAIApplication {
    my $self     = shift;
    my $section  = shift;
    my $app      = "ai";
    my $args      = {};

    foreach my $data ('postPrompt','voice', 'engine', 'postUrl', 'postUser', 'postPassword', 'languages', 'hints', 'params', 'prompt', 'SWAIG') {
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
sub setAIpostUrl {
    my $self = shift;
    my $post = shift;

    while ( my ($k,$v) = each(%{$post}) ) {
        $self->{"_$k"} = $post->{$k};
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
    my $self = shift;
    my $params = shift;

    while ( my ($k,$v) = each(%{$params}) ) {
	$self->{_params}->{$k} = $v;
    }
    
    return;
}

# Set hints overriding any previously set hints
sub setAIhints {
    my $self = shift;
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
    my $self    = shift;
    my $version = shift;

    $self->{_content}->{version} = $version ? $version : $self->{_version};

    return;
}

sub addAISWAIG {
    my $self = shift;
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

sub setAIpostPrompt {
    my $self       = shift;
    my $postprompt = shift;

    while ( my ($k,$v) = each(%{$postprompt}) ) {
	$self->{_postPrompt}->{$k} = $v;
    }

    return;
}

sub setAIprompt {
    my $self   = shift;
    my $prompt = shift;

    while ( my ($k,$v) = each(%{$prompt}) ) {
	$self->{_prompt}->{$k} = $v;
    }

    return;
}

# Render the SWML in JSON;
sub renderJSON {
    my $self = shift;
    my $json = JSON->new->allow_nonref;
    my $i = 0;

    return $json->pretty->encode( $self->{_content} )
}

1;
