# $Id: 04conf.t,v 1.6 2003/07/02 01:42:23 david Exp $

use strict;
use Test::More;
use File::Spec::Functions qw(catdir);

##############################################################################
# Figure out if an apache configuration was prepared by Makefile.PL.
BEGIN {
    plan skip_all => 'Apache::Test required to run tests'
      unless eval {require Apache::Test};
    plan skip_all => 'libwww-perl is not installed'
      unless Apache::Test::have_lwp();

    require Apache::TestRequest;
    Apache::TestRequest->import(qw(GET POST));
    plan tests => 12;
}

sub run_test {
    my ($uri, $test_name, $code, $expect) = @_;
    my $res = GET $uri;
    is( $res->code, $code, "$test_name for $code code" );
    is( $res->content, $expect, "Check $test_name for '$expect'" )
}

# Test MasonCallbacks + MasonDefaultPkgKey.
run_test '/conf_test/test.html?CBFoo|pkg_key_cb=1',
  "Testd MasonCallbacks + MasonDefaultPkgKey",
  200,
  'CBFoo';

# Test MasonCallbacks + MasonDefaultPriority.
run_test '/conf_test/test.html?CBFoo|priority_cb=1',
  "Test MasonCallbacks + MasonDefaultPriority.",
  200,
  '3';

# Test MasonPreCallbacks.
run_test '/conf_test/test.html?result=success&do_upper=1',
  "Test MasonPreCallback",
  200,
  'SUCCESS';

# Test MasonPostCallbacks.
run_test '/conf_test/test.html?result=SUCCESS&do_lower=1',
  "Test MasonPreCallback",
  200,
  'success';

# Test MasonExecNullCbValues.
run_test '/no_exec_conf/test.html?CBFoo|exec_cb=1',
  "Test MasonMasonExecNullCbValues with a value",
  200,
  'executed';

# Test MasonExecNullCbValues again.
run_test '/no_exec_conf/test.html?CBFoo|exec_cb=',
  "Test MasonMasonExecNullCbValues with no value",
  200,
  '';
