#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use Data::Dumper;
use JSON;
use File::Slurp;
use File::stat;
use POSIX qw(strftime);

my $q = CGI->new;
my $json = JSON->new->allow_nonref;

print $q->header("text/html");

my $id = $q->param('id');

if ($id) {
    my $data = parse_json_file($id);
    print_conversation_log($data);
    print_specific_data($data);
} else {
    print_file_list();
}

sub parse_json_file {
    my ($file) = @_;
    my $jtxt = read_file($file);
    return $json->pretty->utf8->decode($jtxt);
}

sub print_conversation_log {
    my ($data) = @_;

    my $tablecontent;
    foreach (@{ $data->{call_log} }) {
        my $style = $_->{role} eq "system" ? "background-color:#aa1.12;color:white"
	    : $_->{role} eq "user" ? "background-color:#2a4d69;color:white"
	    : "background-color:#4b86b4;color:white";
	
        push @{ $tablecontent }, $q->td({-style => $style, -align => 'left', -valign => 'top' },
					[$q->strong("$_->{role}:"), $_->{content}]);
    }

    print $q->start_html(-title => "AI data collector", -style => "font-face:tahoma;font-size:18pt", -bgcolor => "#eeeeee");
    print $q->h1("AI data collector");
    print $q->a({ -href=> "$ENV{SCRIPT_NAME}" }, "<--back"),$q->h2("Conversation Log");
    print $q->table({ -cellspacing => 0, -cellpadding => 5, -border => 0, -width => '100%', -style => "font-face:tahoma;font-size:18pt"},
		    $q->Tr({ -style => "background-color:#4b86b4;color:white" }, $tablecontent));
}

sub print_specific_data {
    my ($data) = @_;
    
    my $collected;
    if ($data->{post_prompt_data}->{raw} =~ /{/) {
        push @{ $collected }, $q->td({-align => 'left', -valign => 'top' }, $q->pre("$data->{post_prompt_data}->{parsed}[0]"));
    } else {
        push @{ $collected }, $q->td({-align => 'left', -valign => 'top' }, "$data->{post_prompt_data}->{raw}");
    }

    print $q->h2("Specific Collected Data");
    print $q->table({ -cellspacing => 1, -cellpadding => 5, -border => 0, -width => '100%', -style => "font-face:tahoma;font-size:18pt"},
		    $q->Tr($collected));
}

sub print_file_list {
    my @files = sort { stat($b)->mtime <=> stat($a)->mtime } glob("logs/*");
    
    my $tablecontent;
    foreach(@files) {
        my $data = parse_json_file($_);
        my $st = stat($_);
        my $timestamp = strftime "%Y-%m-%d %H:%M", localtime($st->ctime);
        my ($name) = $data->{caller_id_name};
        my ($num) = $data->{caller_id_number};

        push @{ $tablecontent }, $q->td({-align => 'left', -valign => 'top' },
					[$q->strong("$timestamp"), $name, $num, $q->a({-href => "$ENV{SCRIPT_NAME}?id=$_"},"$_")]);
    }

    print $q->table({ -cellspacing => 1, -cellpadding => 5, -border => 0, -width => '100%',
			  -style => "font-face:tahoma;font-size:18pt"}, $q->Tr($tablecontent));
}
