#!/usr/bin/perl
use CGI;
use Data::Dumper;
use JSON;
use File::Slurp;
use File::stat;
use POSIX qw(strftime);

my $q    = new CGI;
my $json = JSON->new->allow_nonref;

print $q->header("text/html"),
    $q->start_html(-title => "AI data collector", -style => "font-face:tahoma;font-size:18pt", -bgcolor => "#eeeeee"),
    $q->h1("AI data collector");

my $id = $q->param('id');

if ($id) {
  my $jtxt = read_file("$id");
  my $obj = $json->pretty->utf8->decode($jtxt);
  my $collected;
  my $convo = $obj->{callLog};
  my $tablecontent;

  print $q->a({ -href=>"$ENV{SCRIPT_NAME}" }, "<--back"),$q->h2("Conversation Log");

  foreach ( @{ $convo } ) {
      my $style;
      if ($_->{role} eq "system") {
	  $style = "background-color:#aa1111;color:white";
      } elsif ($_->{role} eq "user") {
	  $style = "background-color:#2a4d69;color:white";
      } else {
	  $style = "background-color:#4b86b4;color:white";
      }
      
      push @{ $tablecontent }, $q->td({-style => $style, -align => 'left', -valign => 'top' },
				      [$q->strong("$_->{role}:"), $_->{content}]);
  }

  print $q->table({ -cellspacing => 0, -cellpadding => 5, -border => 0, -width => '100%', -style => "font-face:tahoma;font-size:18pt"},
		  $q->Tr({ -style => "background-color:#4b86b4;color:white" }, $tablecontent));

  print $q->h2("Specific Collected Data");

  if ($obj->{systemEnd} =~ /{/) {
      push @{ $collected }, $q->td({-align => 'left', -valign => 'top' }, $q->pre("$obj->{systemEnd}"));
  } else {
      push @{ $collected }, $q->td({-align => 'left', -valign => 'top' }, "$obj->{systemEnd}");
  }

  print $q->table({ -cellspacing => 1, -cellpadding => 5, -border => 0, -width => '100%', -style => "font-face:tahoma;font-size:18pt"},
		  $q->Tr($collected));
} else {
    my @files = sort { stat($b)->mtime <=> stat($a)->mtime } glob("logs/*");

    my $tablecontent;
    
    foreach(@files) {
	my $jtxt      = read_file("$_");
	my $obj       = $json->pretty->utf8->decode($jtxt);
	my $st        = stat("$_");
	my $timestamp = strftime "%Y-%m-%d %H:%M", localtime($st->ctime);
	my ($name)    = $obj->{callerIDName};
	my ($num)     = $obj->{callerIDNum};

	push @{ $tablecontent }, $q->td({-style => $style, -align => 'left', -valign => 'top' },
					[$q->strong("$timestamp"), $name, $num,
					 $q->a({-href => "${SCRIPT_NAME}?id=$_"},"$_")]);
	
    }
    print $q->table({ -cellspacing => 1, -cellpadding => 5, -border => 0, -width => '100%',
			  -style => "font-face:tahoma;font-size:18pt"}, $q->Tr($tablecontent));
}
