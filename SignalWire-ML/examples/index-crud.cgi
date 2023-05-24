#!/usr/bin/env perl
use strict;
use warnings;
use CGI qw(:standard);
use Data::Dumper;
use DBI;

# The SQLite CRUD (Create, Read, Update, Delete) application is a simple implementation
# of a web-based interface for managing a SQLite database. It allows users to interact
# with the database by performing CRUD operations on the tables within the database.
#
# The application is built using Perl and CGI.pm, a Perl module for creating Common
# Gateway Interface (CGI) scripts. It utilizes the CGI module to handle HTTP requests
# and generate HTML responses.

my $q = CGI->new;

# The UI is driven by the schema of the database.
my $database = "my.db";
my $dbh = DBI->connect("dbi:SQLite:dbname=$database","","") or die $DBI::errstr;
my $table = $q->param('table') // '';
my $id = $q->param('id') // '';
my $action = $q->param('action') // 'tables';

if ($table ne '') {
    my $sth = $dbh->prepare("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?");
    $sth->execute($table);
    my ($table_count) = $sth->fetchrow_array;

    if ($table_count == 0) {
        die "Table $table does not exist";
    }
}

my %dispatch = (
    tables => \&show_tables,
    list => \&list_records,
    delete => \&delete_record,
    edit => (grep { /^sql_/ } $q->param) ? \&update_record : \&display_edit_form,
    add => (grep { /^sql_/ } $q->param) ? \&insert_record : \&display_add_form,
    );

if (exists $dispatch{$action}) {
    $dispatch{$action}->($q, $dbh, $table, $id);
} else {
    print "Unknown action: $action";
}

sub list_records {
    my ($q, $dbh, $table) = @_;

    print $q->header;

    display_navigation_links($q, $table);

    my $sth = $dbh->column_info(undef, undef, $table, '%');
    my @column_names;
    while (my $column_info = $sth->fetchrow_hashref) {
        push @column_names, $column_info->{COLUMN_NAME};
    }

    my $primary_key = find_primary_key($dbh, $table);

    my $select_sth = $dbh->prepare("SELECT * FROM $table");
    $select_sth->execute;

    my @rows;
    while (my $row = $select_sth->fetchrow_hashref) {
        push @rows, $row;
    }

    print $q->start_html(
        -title => "List Records",
        -style => {-code => q{
            tr:nth-child(even) {background-color: #f2f2f2;} 
            tr:nth-child(odd) {background-color: #ffffff;}
        }},
        -script => {-type => 'text/javascript', -code => q{ 
            function confirmDelete(url) { 
                if (confirm("Are you sure you want to delete this record?")) { 
                    window.location.href = url; 
                } 
            } 
        }}
	);

    print $q->start_table({-cellspacing => 0, -cellpadding => 5});

    my @header_cells = map { $q->th($_) } @column_names;
    push @header_cells, $q->th("Actions");
    print $q->Tr(@header_cells);

    foreach my $row (@rows) {
        my $row_id = $row->{$primary_key};
        my @cells = map { $q->td($row->{$_}) } @column_names;
        push @cells, $q->td(
            $q->button(-value => 'Edit', -onClick => "window.location.href='$ENV{SCRIPT_NAME}?action=edit&table=$table&id=$row_id'"),
            $q->button(-value => 'Delete', -onClick => "confirmDelete('$ENV{SCRIPT_NAME}?action=delete&table=$table&id=$row_id')")
	    );
        print $q->Tr(@cells);
    }

    print $q->end_table;
    print $q->end_html;
}

sub delete_record {
    my ($q, $dbh, $table, $id) = @_;

    my $primary_key = find_primary_key($dbh, $table);

    my $sth = $dbh->prepare("DELETE FROM $table WHERE ? = ?");
    $sth->execute($primary_key, $id);

    print $q->redirect($ENV{SCRIPT_NAME});
}

sub update_record {
    my ($q, $dbh, $table, $id) = @_;

    my %fields;
    foreach my $key ($q->param) {
        if ($key =~ /^sql_(.+)/) {
            $fields{$1} = $q->param($key);
        }
    }

    my $primary_key = find_primary_key($dbh, $table);

    my $set_clause = join ', ', map { "$_ = ?" } keys %fields;
    my $sth = $dbh->prepare("UPDATE $table SET $set_clause WHERE $primary_key = ?");
    $sth->execute(values %fields, $id);
    print $q->redirect($ENV{SCRIPT_NAME});
}

sub display_edit_form {
    my ($q, $dbh, $table, $id) = @_;

    print $q->header;

    display_navigation_links($q, $table);

    my $columns = $dbh->selectall_arrayref("PRAGMA table_info($table)");
    my @columns = map { $_->[1] } @$columns;

    my $primary_key = find_primary_key($dbh, $table);
    my @foreign_keys = find_foreign_keys($dbh, $table);

    my $sth = $dbh->prepare("SELECT * FROM $table WHERE $primary_key = ?");
    $sth->execute($id);

    my $record = $sth->fetchrow_hashref;

    print $q->start_form(-method => 'POST', -action => "$ENV{SCRIPT_NAME}");
    print $q->hidden(-name => 'action', -value => 'update');
    print $q->hidden(-name => 'table', -value => $table);
    print $q->hidden(-name => 'id', -value => $id);

    my @table_rows;

    foreach my $column (@columns) {
        my @row;
        push @row, $q->td($q->label("$column:"));
        my $column_type = get_column_type($dbh, $table, $column);

        if ($column_type eq 'BLOB') {
            push @row, $q->td($q->textarea(-name => "sql_$column", -default => $record->{$column}, -rows => 10, -columns => 40));
        } elsif (my ($foreign_key) = grep { $_->{from} eq $column } @foreign_keys) {
            my $foreign_values = $dbh->selectcol_arrayref("SELECT $foreign_key->{to} FROM $foreign_key->{table}");
            push @row, $q->td($q->popup_menu(-name => "sql_$column", -values => $foreign_values, -default => $record->{$column}));
        } elsif (my @enum_values = get_enum_values($dbh, $table, $column)) {
            push @row, $q->td($q->popup_menu(-name => "sql_$column", -values => \@enum_values, -default => $record->{$column}));
        } else {
            push @row, $q->td($q->textfield(-name => "sql_$column", -value => $record->{$column}));
        }
        push @table_rows, $q->Tr(@row);
    }

    print $q->start_table;
    print $q->Tr(@table_rows);
    print $q->end_table;

    print $q->submit(-value => 'Update record');
    print $q->end_form;
}

sub insert_record {
    my ($q, $dbh, $table) = @_;

    my %fields;
    foreach my $key ($q->param) {
        if ($key =~ /^sql_(.+)/) {
            $fields{$1} = $q->param($key);
        }
    }

    my $field_names = join ', ', keys %fields;
    my $placeholders = join ', ', ('?') x keys %fields;
    my $stmt = "INSERT INTO $table ($field_names) VALUES ($placeholders)";
    my $sth = $dbh->prepare($stmt);
    $sth->execute(values %fields);
    
    print $q->redirect($ENV{SCRIPT_NAME});
}

sub display_add_form {
    my ($q, $dbh, $table, $id) = @_;

    print $q->header;

    display_navigation_links($q, $table);

    my $columns = $dbh->selectall_arrayref("PRAGMA table_info($table)");
    my @columns = map { $_->[1] } @$columns;

    my $primary_key = find_primary_key($dbh, $table);
    my @foreign_keys = find_foreign_keys($dbh, $table);

    print $q->start_form(-method => 'POST', -action => $ENV{SCRIPT_NAME});
    print $q->hidden(-name => 'action', -value => 'add');
    print $q->hidden(-name => 'table', -value => $table);

    my @table_rows;

    foreach my $column (@columns) {
        my @row;
        push @row, $q->td($q->label("$column:"));
        my $column_type = get_column_type($dbh, $table, $column);

        if ($column eq $primary_key) {
	    my $next_id = get_next_id($dbh, $table);
            push @row, $q->td($q->textfield(-name => "sql_$column", -readonly => 1, -default => $next_id));
        } elsif ($column_type eq 'BLOB') {
            push @row, $q->td($q->textarea(-name => "sql_$column", -rows => 10, -columns => 40));
        } elsif (my ($foreign_key) = grep { $_->{from} eq $column } @foreign_keys) {
            my $foreign_values = $dbh->selectcol_arrayref("SELECT $foreign_key->{to} FROM $foreign_key->{table}");
            push @row, $q->td($q->popup_menu(-name => "sql_$column", -values => $foreign_values));
        } elsif (my @enum_values = get_enum_values($dbh, $table, $column)) {
            push @row, $q->td($q->popup_menu(-name => "sql_$column", -values => \@enum_values));
        } else {
            push @row, $q->td($q->textfield(-name => "sql_$column"));
        }
        push @table_rows, $q->Tr(@row);
    }

    print $q->start_table;
    print $q->Tr(@table_rows);
    print $q->end_table;

    print $q->submit(-value => 'Save record');
    print $q->end_form;
}

sub show_tables {
    my ($q, $dbh) = @_;

    print $q->header;
    print $q->start_html(-title => "Tables Available");
    print $q->h1("Tables Available in $database");

    my $tables = $dbh->selectcol_arrayref("SELECT name FROM sqlite_master WHERE type='table' AND name != 'sqlite_sequence'");

    foreach my $table (@$tables) {
        print $q->a({ href => "$ENV{SCRIPT_NAME}?action=list&table=$table" }, $table), $q->br;
    }

    print $q->end_html;
}

sub find_primary_key {
    my ($dbh, $table) = @_;

    my $sth = $dbh->prepare("PRAGMA table_info($table)");
    $sth->execute();

    my $primary_key;
    while (my $row = $sth->fetchrow_hashref) {
        if ($row->{pk}) {
            $primary_key = $row->{name};
            last;
        }
    }
    return $primary_key;
}

sub get_enum_values {
    my ($dbh, $table, $field) = @_;

    my $sql = "SELECT sql FROM sqlite_master WHERE type='table' AND name=?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($table);

    my $enum_values;
    while (my $row = $sth->fetchrow_arrayref) {
        if ($row->[0] =~ /CHECK\($field\s+IN\s+\((.*?)\)/i) {
            $enum_values = $1;
            last;
        }
    }

    my @values;
    if ($enum_values) {
        @values = $enum_values =~ /'([^']+)'/g;
    }

    return @values;
}

sub find_foreign_keys {
    my ($dbh, $table) = @_;

    my $sth = $dbh->prepare("PRAGMA foreign_key_list($table)");
    $sth->execute();

    my @foreign_keys;
    while (my $row = $sth->fetchrow_hashref) {
        push @foreign_keys, { 
            id         => $row->{id},
            seq        => $row->{seq},
            table      => $row->{table},
            from       => $row->{from},
            to         => $row->{to},
            on_update  => $row->{on_update},
            on_delete  => $row->{on_delete},
            match      => $row->{match},
        };
    }

    return @foreign_keys;
}

sub get_column_type {
    my ($dbh, $table, $column) = @_;
    my $result = $dbh->selectall_arrayref("PRAGMA table_info($table)");
    my ($type) = map { $_->[2] } grep { $_->[1] eq $column } @$result;
    return $type;
}

sub display_navigation_links {
    my ($q, $table) = @_;

    print $q->start_html(-title => "Navigation");
    print $q->start_table({-width => '100%', -valign => 'top'});

    print $q->start_Tr;
    print $q->td($q->button(-value => 'Go Back', -onClick => "history.back()"));
    print $q->td($q->button(-value => 'Add Record', -onClick => "window.location.href='$ENV{SCRIPT_NAME}?action=add&table=$table'"));
    print $q->td($q->button(-value => 'Home', -onClick => "window.location.href='$ENV{SCRIPT_NAME}'"));
    print $q->end_Tr;

    print $q->end_table;
    print $q->end_html;
}

sub get_next_id {
    my ($dbh, $table) = @_;
    
    my $primary_key = find_primary_key($dbh, $table);

    # Ensure that the table has an AUTOINCREMENT primary key
    my $check_sth = $dbh->prepare("PRAGMA table_info($table)");
    $check_sth->execute();
    my $has_autoincrement = 0;
    while (my $row = $check_sth->fetchrow_hashref) {
        if ($row->{name} eq $primary_key and $row->{pk} and $row->{type} =~ /INTEGER/i) {
            $has_autoincrement = 1;
            last;
        }
    }
    return undef unless $has_autoincrement;

    # If it does, get the next sequence number
    my $sth = $dbh->prepare("SELECT seq FROM sqlite_sequence WHERE name=?");
    $sth->execute($table);
    my ($last_id) = $sth->fetchrow_array();

    return defined($last_id) ? $last_id + 1 : 1;
}
__END__
