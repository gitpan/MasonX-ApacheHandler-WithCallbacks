# $Id: 02errors.t,v 1.1 2003/02/14 22:43:02 david Exp $

use strict;
use Test::More tests => 12;
use File::Spec::Functions qw(catdir catfile);
use lib 'lib', catdir('t', 'lib');
use Apache::test qw(have_httpd);
use Apache::TestHelper;


##############################################################################
# Figure out if an apache configuration was prepared by Makefile.PL.
unless (-e catdir('t', 'httpd.conf') and -x catdir('t', 'httpd')) {

    # Skip all of the tests.
    SKIP: { skip "No apache server configuration", 11 }

    # And just exit if there's no apache config.
    exit;
}

##############################################################################
# Kill Apache, delete the error log, and get the .conf file data.
local $| = 1;
my $wait = 20;
kill_httpd($wait);
my $logfile = catfile('t', 'error_log');
unlink $logfile;

my $err_conf = load_conf();
my $test_conf = catfile('t', 'test.conf');

##############################################################################
# Test a bad callback key.
write_conf('bad_cb_key_handler');
start_httpd();
run_test(qr/Missing or invalid callback key/, 'Check bad callback key');

##############################################################################
# Test a bad priority.
write_conf('bad_priority_handler');
start_httpd();
run_test(qr/Not a valid priority: 'foo'/, 'Check bad priority');

##############################################################################
# Test a bad code ref.
write_conf('bad_coderef_handler');
start_httpd();
my $err = "Callback for package key 'errorTester' and callback key " .
  "'coderef' not a code reference";
run_test(qr/$err/, 'Check bad code ref');

##############################################################################
# Test for a used key.
write_conf('used_key_handler');
start_httpd();
run_test(qr/Callback key 'my_key' already used by package key 'errorTester'/,
         'Check used key');

##############################################################################
# Test a bad global code ref.
write_conf('bad_global_coderef_handler');
start_httpd();
run_test(qr/Global pre callback not a code reference/,
         'Check bad global code ref');

##############################################################################
# Test warning.
write_conf('no_cbs_handler');
start_httpd();
run_test(qr/You didn't specify any callbacks./,
         "Check no callbacks warning", 200 );

##############################################################################
start_httpd();

##############################################################################

sub run_test {
    my ($regex, $test_name, $code) = @_;
    my $res = Apache::test->fetch({ uri => '/' });
    $code ||= 500;
    is( $res->code, $code, "$test_name for $code code" );
    kill_httpd($wait);
    open LOG, $logfile or die "Cannot open '$logfile': $!\n";
    local $/;
    my $log = <LOG>;
    close LOG;
    unlink $logfile;
    like( $log, $regex, $test_name);
}

sub load_conf {
    my $err_conf = catfile 't', 'errors.conf';
    open ERRCONF, $err_conf or die "Cannot open '$err_conf': $!\n";
    local $/;
    return <ERRCONF>;
}

sub write_conf {
    my $handler = shift;
    open CONF, ">$test_conf" or die "Cannot open '$test_conf': $!\n";
    print CONF $err_conf, "PerlHandler MasonCallbackErrorTester::$handler\n";
    close CONF;
}
