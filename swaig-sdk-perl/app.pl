#!/usr/bin/env perl
# Example SWAIG Server for SignalWire AI Agent written in Perl.
use strict;
use warnings;

# PSGI/Plack
use Plack::Builder;
use Plack::Runner;
use Plack::Request;
use Plack::Response;
use Plack::App::Directory;

# SignalWire modules
use SignalWire::ML;

# Other modules
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;
use URL::Encode qw (url_encode);
use Env::C;

my $ENV = Env::C::getallenv();

my $function = {
    get_joke => { function  => \&get_joke,
		  signature => { 
		      function => 'get_joke',
		      purpose  => "get a joke to tell the user",
		      argument => {
			  type => "object",
			  properties => {
			      type => {
				  type => "string",
				  description => "must either be 'jokes' or 'dadjokes'" },
			  },
			  requried => [ 'type' ]
		      }
		  }
    },
    get_trivia => { function  => \&get_trivia,
		    signature => { 
			function => 'get_trivia',
			purpose  => "get a trivia question",
			argument => {
			    type => "object",
			    properties => {
				category => {
				    type => "string",
				    description => "Valid options are artliterature, language, sciencenature, general, fooddrink, peopleplaces, geography, historyholidays, entertainment, toysgames, music, mathematics, religionmythology, sportsleisure. Pick a category at random if not asked for a specific category." }
			    },
			    required => [ 'category' ]
			}
		    }
    },
    get_weather => { function  => \&get_weather,
		     signature => { 
			 function => 'get_weather',
			 purpose  => "latest weather information for any city",
			 argument => {
			     type => "object",
			     properties => {
				 city => {
				     type => "string",
				     description => "City name." },
				 state => {
				     type => "string",
				     description => "US state for United States cities only. Optional" }
			     },
			     required => [ 'city' ]
			 }
		     }
    }
};

sub get_joke {
    my $data      = shift;
    my $post_data = shift;
    my $ua        = LWP::UserAgent->new;
    my $swml      = SignalWire::ML->new();

    print STDERR Dumper($post_data) if $ENV{DEBUG};

    my $response = $ua->get("https://api.api-ninjas.com/v1/$data->{type}",
			    'X-Api-Key' => $ENV{API_KEY});
    
    my $res = Plack::Response->new(200);
    $res->content_type('application/json');
    
    print STDERR Dumper($response) if $ENV{DEBUG};

    if ($response->is_success) {
	my $joke = decode_json($response->decoded_content);	
	print STDERR Dumper($joke) if $ENV{DEBUG};
	$res->body($swml->swaig_response_json( { response => "Tell the user: $joke->[0]->{joke}" } ) );
    } else {
	$res->body($swml->swaig_response_json( { response => "Tell the user: I'm not that funny these days." } ) );
    }
    return $res->finalize;
}

sub get_trivia {
    my $data      = shift;
    my $post_data = shift;
    my $config    = $post_data->{meta_data}->{config};
    my $ua        = LWP::UserAgent->new;
    my $swml      = SignalWire::ML->new();

    print STDERR Dumper($post_data) if $ENV{DEBUG};
    
    my $response = $ua->get("https://api.api-ninjas.com/v1/trivia?category=$data->{category}",
			    'X-Api-Key' => $ENV{API_KEY});

    my $res = Plack::Response->new(200);
    $res->content_type('application/json');

    print STDERR Dumper($response) if $ENV{DEBUG};

    if ($response->is_success) {
	my $trivia = decode_json($response->decoded_content);
	print STDERR Dumper($trivia) if $ENV{DEBUG};
	$res->body($swml->swaig_response_json( { response => "category $trivia->[0]->{category} questions: $trivia->[0]->{question} answer: $trivia->[0]->{answer}, be sure to give the user time to answer before saying the answer." }));
    } else {
	$res->body($swml->swaig_response_json( { response => "Tell the user: Water isn't wet, it makes things wet." } ) );
    }
    return $res->finalize;
}

sub get_weather {
    my $data      = shift;
    my $post_data = shift;
    my $config    = $post_data->{meta_data}->{config};
    my $city      = url_encode( $data->{city} );
    my $state	  = url_encode( $data->{state} ) || '';
    my $ua        = LWP::UserAgent->new;
    my $swml      = SignalWire::ML->new();

    print STDERR Dumper($post_data) if $ENV{DEBUG};
    
    my $response = $ua->get("https://api.api-ninjas.com/v1/weather?city=$city&state=$state",
			    'X-Api-Key' => $ENV{API_KEY});

    my $res = Plack::Response->new(200);
    $res->content_type('application/json');

    print STDERR Dumper($response) if $ENV{DEBUG};

    if ($response->is_success) {
	my $weather = decode_json($response->decoded_content);
	$weather->{temp} = $weather->{temp} * 9/5 + 32;
	$weather->{max_temp} = $weather->{max_temp} * 9/5 + 32;
	$weather->{min_temp} = $weather->{min_temp} * 9/5 + 32;
	$weather->{feels_like} = $weather->{feels_like} * 9/5 + 32;
	
	print STDERR Dumper($weather) if $ENV{DEBUG};
	$res->body($swml->swaig_response_json( { response => "The weather in $city is $weather->{temp}F, High of $weather->{max_temp}F, Low of $weather->{min_temp}F, Feels like $weather->{feels_like}F." }));
    } else {
	$res->body($swml->swaig_response_json( { response => "I'm sorry, I couldn't get the weather for $city." } ) );
    }
    return $res->finalize;
}
    
my $swaig_app = sub {
    my $env       = shift;
    my $req       = Plack::Request->new($env);
    my $post_data = decode_json( $req->raw_body );
    my $swml      = SignalWire::ML->new();
    my $data      = $post_data->{argument}->{parsed}->[0];

    print STDERR Dumper($post_data) if $ENV{DEBUG};
    
    if (defined $post_data->{action} && $post_data->{action} eq 'get_signature') {
	my @functions;
	my @funcs;
	my $res = Plack::Response->new(200);
	
	$res->content_type('application/json');
	
	print STDERR Dumper($post_data) if $ENV{DEBUG};

	if ( scalar (@{ $post_data->{functions}}) ) {
	    @funcs =  @{ $post_data->{functions}};
	} else {
	    @funcs = keys %{$function};
	}

	print STDERR Dumper(\@funcs) if $ENV{DEBUG};
	
	foreach my $func ( @funcs ) {
	    $function->{$func}->{signature}->{web_hook_auth_user}     = $ENV{WEB_AUTH_USER};
	    $function->{$func}->{signature}->{web_hook_auth_password} = $ENV{WEB_AUTH_PASS};
	    $function->{$func}->{signature}->{web_hook_url}           = "https://$env->{HTTP_HOST}$env->{REQUEST_URI}";
	    push @functions, $function->{$func}->{signature};
	}
	print STDERR Dumper(\@funcs) if $ENV{DEBUG};
	$res->body( encode_json( \@functions ) );
	
	return $res->finalize;
    } elsif (defined $post_data->{function} && exists $function->{$post_data->{function}}->{function}) {
	$function->{$post_data->{function}}->{function}->($data, $post_data, $env);
    } else {
	my $res = Plack::Response->new( 500 );

	$res->content_type('application/json');

	$res->body($swml->swaig_response_json( { response => "I'm sorry, I don't know how to do that." } ));

	return $res->finalize;
    }
};

sub authenticator {
	my ($username, $password) = @_;
	return $username eq $ENV{WEB_AUTH_USER} && $password eq $ENV{WEB_AUTH_PASS};
}

# PSGI application entry point
my $app = builder {

    enable sub {
	my $app = shift;
	
	return sub {
	    my $env = shift;
	    my $res = $app->( $env );

	    Plack::Util::header_set( $res->[1], 'Expires', 0 );
	    
	    return $res;
	};
    };

    mount "/swaig" => builder {
	enable "Auth::Basic", authenticator => \&authenticator;
	$swaig_app;
    };

    mount "/" => builder {
	my $res = Plack::Response->new(200);
	$res->body("Hello, World!");
	return $res->finalize;
    };
    
};

# Running the PSGI application
my $runner = Plack::Runner->new;

$runner->run( $app );

1;
