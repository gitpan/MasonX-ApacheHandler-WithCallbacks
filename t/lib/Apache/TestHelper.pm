package Apache::TestHelper;

use strict;

use File::Basename;
use File::Path;
use File::Spec::Functions;
use Cwd;
use Carp;
require Test::More;
require Exporter;
*import = \&Exporter::import;
use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(test_load_apache start_httpd kill_httpd get_pid);

sub get_pid {
    local *PID;
    my $pid_file = catfile( 't', 'httpd.pid' );
    open PID, "<$pid_file" or croak "Can't open $pid_file: $!";
    my $pid = <PID>;
    close PID;
    chomp $pid;
    return $pid;
}

sub test_load_apache {
    Test::More::diag "\nTesting whether Apache can be started\n";
    start_httpd('');
    kill_httpd(10);
}

sub start_httpd {
    my $def = shift;
    $def = "-D$def" if $def;

    my $httpd = catfile( 't', 'httpd' );
    my $conf_file = catfile( cwd, 't', 'httpd.conf' );
    my $cmd ="$httpd $def -f $conf_file";
    Test::More::diag "Executing $cmd\n";
    system ($cmd) and croak "Can't start httpd server as '$cmd': $!";

    my $x = 0;
    Test::More::diag "Waiting for httpd to start.\n";
    until ( -e 't/httpd.pid' ) {
        sleep (1);
        $x++;
        if ( $x > 10 ) {
            croak "No t/httpd.pid file has appeared after 10 seconds.  ",
                  "There is probably a problem with the configuration ",
                  "file that was generated for these tests.";
        }
    }
}

sub kill_httpd {
    my $wait = shift;
    my $pid_file = catfile( 't', 'httpd.pid' );
    return unless -e $pid_file;
    my $pid = get_pid();

    Test::More::diag "\nKilling httpd process ($pid)\n";
    my $result = kill 'TERM', $pid;
    if ( ! $result and $! =~ /no such (?:file|proc)/i ) {
        # Looks like apache wasn't running, so we're done
        unlink $pid_file or warn "Couldn't remove $pid_file: $!";
        return;
    }
    croak "Can't kill process $pid: $!" unless $result;

    if ($wait) {
        Test::More::diag "Waiting for httpd to shut down\n";
        my $x = 0;
        while ( -e $pid_file ) {
            sleep (1);
            $x++;
            if ( $x > 1 ) {
                my $result = kill 'TERM', $pid;
                if ( ! $result and $! =~ /no such (?:file|proc)/i ) {
                    # Looks like apache wasn't running, so we're done
                    if ( -e $pid_file ) {
                        unlink $pid_file
                            or warn "Couldn't remove $pid_file: $!";
                    }
                    return;
                }
            }

            croak "$pid_file file still exists after $wait seconds. " .
                  "Exiting."
              if $x > $wait;
        }

    }
}


1;
