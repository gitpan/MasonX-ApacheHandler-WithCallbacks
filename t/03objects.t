# $Id: 03objects.t,v 1.9 2003/05/01 05:38:37 david Exp $

use strict;
use Test::More;
use File::Spec::Functions qw(catdir);
use lib 'lib', catdir('t', 'lib');
use LWP::UserAgent;
use Apache::test qw(have_httpd);

##############################################################################
# Figure out if an apache configuration was prepared by Makefile.PL.
unless (-e catdir('t', 'httpd.conf') and -x catdir('t', 'httpd')) {
    # Skip all of the tests.
    plan skip_all => 'no httpd';
} elsif ($] < 5.006) {
    # No OO interface before Perl 5.6. Skip all of the tests and exit.
    plan skip_all => 'OO interface not supported prior to Perl 5.6.0';
} else {
    plan tests => 96;
}

##############################################################################
# Don't use Apache::test's default UA object because it will try to actually
# execute redirects when we use GET or HEAD.
my $ua = LWP::UserAgent->new(requests_redirectable => 0);

run_test("Simple CB",
         'test.html?OOTester|simple_cb=1',
         200,
         'Simple Success');

run_test("Complete CB Def",
         'test.html?OOTester|complete_cb=1',
         200,
         'Complete Success');

run_test("Meth Key CB",
         'test.html?OOTester|meth_key_cb=1',
         200,
         'CBKey Success');

run_test("Pre Callback",
         'test.html?do_upper=1&result=upper_me',
         200,
         'UPPER_ME');

run_test("Post Callback",
         'test.html?do_lower=1&result=LOWER_ME',
         200,
         'lower_me');

run_test("Check class",
         'test.html?OOTester|class_cb=1',
         200,
         'MasonOOCallbackTester => MasonOOCallbackTester');

run_test("Check class",
         'test.html?OOTester|inherit_cb=1',
         200,
         'Yes');

run_test("Simple sub CB",
         'test.html?OOTesterSub|subsimple_cb=1',
         200,
         'Subsimple Success');

run_test("Check class",
         'test.html?OOTesterSub|inherit_cb=1',
         200,
         'Yes and Yes');

# Make sure that inheritance works.
run_test("Check inheritance",
         'test.html?OOTesterSub|class_cb=1',
         200,
         'MasonOOCallbackTester => MasonOOCallbackTesterSub');

# Make sure that request callback inheritance works.
run_test("Subclassed Pre Callback",
         'test.html?do_upper=1&result=upper_me',
         200,
         'UPPER_ME PRECALLBACK Overridden PostCallback',
         '/req_sub');

run_test("Subclassed Post Callback",
         'test.html?do_lower=1&result=LOWER_ME',
         200,
         'lower_me precallback Overridden PostCallback',
         '/req_sub');

# Check that multiple callbacks execute in priority order.
run_test( 'Execution order',
          'test.html?OOTester|chk_priority_cb0=0'
            . '&OOTester|chk_priority_cb2=2'
            . '&OOTester|chk_priority_cb9=9'
            . '&OOTester|chk_priority_cb7=7'
            . '&OOTester|chk_priority_cb1=1'
            . '&OOTester|chk_priority_cb4=4'
            . '&OOTester|chk_priority_cb=def',
          200,
          " 0 1 2 4 5 7 9");

# Execute the one callback with an array of values
run_test('Array of Values',
         'test.html?OOTester|multi_cb=1'
           . '&OOTester|multi_cb=1'
           . '&OOTester|multi_cb=1'
           . '&OOTester|multi_cb=1'
           . '&OOTester|multi_cb=1',
         200,
         "5");

# Emmulate the sumission of an <input type="image" /> button.
run_test( 'Image button',
          'test.html?OOTester|simple_cb.x=18'
          . '&OOTester|simple_cb.y=24',
          200,
          "Simple Success");

# Make sure that redirects work.
run_test("Redirects",
         'test.html?OOTester|redir_cb=0'
           . '&OOTester|set_status_ok_cb9=1',
         302, 0, 0,
         { Location => 'http://example.com/'}
        );

# Make sure that redirect without abort works.
run_test("Redirect without abort",
         'test.html?OOTester|redir_cb=1'
         . '&OOTester|set_status_ok_cb9=1',
         200);

# Test "redirected" attribute.
run_test('redirected attribute',
         'test.html?OOTester|redir_cb=1'
           . '&OOTester|test_redirected_cb9=1',
         200,
         'yes');

# Test "aborted" for false value.
run_test("false aborted",
         '/test.html?OOTester|test_aborted_cb=0',
         200,
         'no');

# Now throw an exception in the callback.
run_test("exception in the callback",
         'Test?OOTester|exception_cb=1',
         500);

# Now die in the callback.
run_test("die in the callback",
         'test.html?OOTester|exception_cb=0',
         500);

# Make sure that the same object is used for different callbacks to the same
# class.
run_test("Same object",
         'text.html?OOTester|same_object_cb1=0'
           . '&OOTester|same_object_cb=1',
         200,
         'Yes'
        );

# Check that cb_classes => 'ALL' worked properly by checking for callbacks
# in each of the callback classes.
foreach my $ckey (qw(OOTester OOTesterSub Empty ReqSub)) {
    run_test("Check 'ALL'",
             "test.html?$ckey|simple_cb=1",
             200,
             'Simple Success',
             '/all');
}

# Make sure that when request callbacks are called that there are no values
# returned by most of the accessors.
    run_test("Check request callback attributes",
             "test.html?OOTester|pre_post_cb=1",
             200,
             'Attributes okay');

# Check the combined callback handler that loads some functional and some
# OO callbacks. Start with the functional callback.
run_test("Check functional CB in combined",
         "test.html?myCallbackTester|simple_cb=1",
         200,
         'Success',
         '/attrs');

# Now try the OO meethod.
run_test("Check functional CB in combined",
         "test.html?OOTester|simple_cb=1",
         200,
         'Simple Success',
         '/attrs');

# Check the combined callback handler to make sure that the request callbacks
# are loading properly.
run_test("Check combined request CBs",
         "test.html?do_presto=1&do_lower=1",
         200,
         'presto',
         '/attrs');



##############################################################################
sub run_test {
    my ($test_name, $uri, $code, $expect, $dir, $headers) = @_;
    foreach my $loc ($dir ? ($dir) : qw(/oop /empty)) {
        my $res = Apache::test->fetch($ua, { uri => "$loc/$uri" });
        is( $res->code, $code, "$test_name for $code code" );
        is( $res->content, $expect, "Check $test_name for '$expect'" )
          if $expect;
        # Test the headers.
        if ($headers) {
            while (my ($h, $v) = each %$headers) {
                is( $res->header($h), $v, "Check $test_name for '$v' header" );
            }
        }
    }
}
