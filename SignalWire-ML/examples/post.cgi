#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use JSON;
use UUID 'uuid';
use File::Slurp;
use DateTime;

my $q = CGI->new;
my $json = JSON->new->allow_nonref->pretty->utf8;
my $zone = $ENV{TIMEZONE} || "America/Chicago";

print $q->header("application/json");

my $json_text = $q->param('POSTDATA');
my $post_data = $json->decode($json_text);
(my $app_name = $post_data->{"app_name"}) =~ s/[^\w\d\-]//g;
my $uuid = uuid();

append_to_log("$ENV{POST_LOG_DIR}/post.log", "\nPOSTDATA: " . $json->pretty->encode($post_data) . "\n");

my %dispatch_table = (
    'fetch_conversation' => \&handle_fetch_conversation,
    'post_conversation'  => \&handle_post_conversation,
    'log_application'    => \&handle_log_application,
);

my $action = $post_data->{"action"};

if (exists $dispatch_table{$action}) {
    $dispatch_table{$action}->($post_data);
} else {
    if ( $post_data->{"conversation_id"} && $post_data->{"conversation_summary"} ) {
	$dispatch_table{'post_conversation'}->($post_data);
    } else {
	$dispatch_table{'log_application'}->($post_data);
    }
}

print $json->encode({ response => "data received" });

sub handle_fetch_conversation {
    my ($post_data) = @_;
    if ($post_data->{"conversation_id"}) {
        my $summary = read_file("$ENV{CONVO_LOG_DIR}/$post_data->{'conversation_id'}");
        my $response = $summary ? "Conversation found" : "No previous conversation found";
        print $json->encode({ response => $response, conversation_summary => $summary });
    }
}

sub handle_post_conversation {
    my ($post_data) = @_;
    if ($post_data->{"conversation_id"} && $post_data->{"conversation_summary"}) {
        append_to_log("$ENV{CONVO_LOG_DIR}/$post_data->{'conversation_id'}", format_conversation($post_data->{"conversation_summary"}));
    }
}

sub handle_log_application {
    my ($post_data) = @_;
    if ($app_name) {
        write_to_log("$ENV{AI_LOG_DIR}/${app_name}-${uuid}", $json_text);
    }
}

sub append_to_log {
    my ($filename, $data) = @_;
    open my $fh, '>>', $filename or die "Could not open $filename: $!";
    print $fh $data;
    close $fh;
}

sub write_to_log {
    my ($filename, $data) = @_;
    open my $fh, '>', $filename or die "Could not open $filename: $!";
    print $fh $data;
    close $fh;
}

sub format_conversation {
    my ($conversation_summary) = @_;
    my $dt = DateTime->now;    
    my $tz = DateTime::TimeZone->new(name => $zone);
    $dt->set_time_zone($tz);
    my $formatted_time = $dt->strftime("%D %I:%M%p CT");
    chomp($conversation_summary);
    return "- Call $formatted_time: $conversation_summary\n";
}

