# $Id: 02errors.t,v 1.6 2003/06/17 22:43:04 david Exp $

use strict;
use Test::More;
use File::Spec::Functions qw(catfile);
use Apache::Test qw(have_lwp);
use Apache::TestRequest qw(GET);

plan tests => 12, have_lwp;

##############################################################################
# Get the name of the error log.
local $| = 1;
my $logfile = catfile('logs', 'error_log');

##############################################################################
# Test a bad callback key.
run_test('/bad_key',
         qr/Missing or invalid callback key/,
         'Check bad callback key');

##############################################################################
# Test a bad priority.
run_test('/bad_priority',
         qr/Not a valid priority: 'foo'/,
         'Check bad priority');

##############################################################################
# Test a bad code ref.
my $err = "Callback for package key 'myCallbackTester' and callback key " .
  "'coderef' not a code reference";
run_test('/bad_coderef',
         qr/$err/,
         'Check bad code ref');

##############################################################################
# Test for a used key.
run_test('/used_key',
         qr/Callback key 'my_key' already used by package key 'myCallbackTester'/,
         'Check used key');

##############################################################################
# Test a bad global code ref.
run_test('/global_coderef',
         qr/Global pre callback not a code reference/,
         'Check bad global code ref');

##############################################################################
# Test warning.
run_test('/no_cbs',
         qr/You didn't specify any callbacks./,
         "Check no callbacks warning",
         200 );

##############################################################################

sub run_test {
    my ($uri, $regex, $test_name, $code) = @_;
    my $res = GET $uri;
    $code ||= 500;
    is( $res->code, $code, "$test_name for $code code" );
    open LOG, $logfile or die "Cannot open '$logfile': $!\n";
    local $/;
    my $log = <LOG>;
    close LOG;
    like( $log, $regex, $test_name);
}
