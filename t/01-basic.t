# $Id: 01-basic.t,v 1.15 2003/06/29 20:20:59 david Exp $

use strict;
use Test::More;
use File::Spec::Functions qw(catdir catfile);
use lib 'lib', catdir('t', 'lib');
use Apache::Test qw(have_lwp);
use Apache::TestRequest qw(GET POST);

##############################################################################
# Figure out if an apache configuration was prepared by Makefile.PL.
plan tests => 43, have_lwp;

##############################################################################
# Define the test function.
local $| = 1;
my $logfile = catfile(qw(logs error_log));
sub run_test {
    my ($test_name, $code, $req, $expect, $headers, $regex) = @_;
    my $res = $req->{method} eq 'POST' ? POST @{$req}{qw(uri content)} :
      GET $req->{uri};
    is( $res->code, $code, "$test_name for $code code" );
    is( $res->content, $expect, "Check $test_name for '$expect'" )
      if $expect;

    # Test the headers.
    if ($headers) {
        while (my ($h, $v) = each %$headers) {
            is( $res->header($h), $v, "Check $test_name for '$v' header" );
        }
    }

    # Read the log file.
    if ($regex) {
        open LOG, $logfile or die "Cannot open '$logfile': $!\n";
        local $/;
        my $log = <LOG>;
        close LOG;
        like( $log, $regex, "$test_name Log check");
    }
}

##############################################################################
# Run the tests.

# Just make sure it works.
run_test 'Simple test', 200,
  { uri => '/test.html?myCallbackTester|simple_cb=1' },
  'Success';

# Make sure that POST works.
run_test 'POST test', 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|simple_cb' => 1 ]
  },
  'Success';

# Check that multiple callbacks execute in priority order.
run_test 'Execution order', 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => [  'myCallbackTester|priority_cb0' => 0,
                  'myCallbackTester|priority_cb2' => 2,
                  'myCallbackTester|priority_cb9' => 9,
                  'myCallbackTester|priority_cb7' => 7,
                  'myCallbackTester|priority_cb1' => 1,
                  'myCallbackTester|priority_cb4' => 4,
                  'myCallbackTester|priority_cb'  => 'def' ]
  },
  " 0 1 2 4 5 7 9";

# Execute the one callback with an array of values
run_test 'Array of Values', 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => [ 'myCallbackTester|multi_cb' => 1,
                 'myCallbackTester|multi_cb' => 1,
                 'myCallbackTester|multi_cb' => 1,
                 'myCallbackTester|multi_cb' => 1,
                 'myCallbackTester|multi_cb' => 1 ]
  },
  "5";

# Emmulate the sumission of an <input type="image" /> button.
run_test 'Image button', 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => [ 'myCallbackTester|simple_cb.x' => 18,
                 'myCallbackTester|simple_cb.y' => 24 ]
  },
  "Success";

# Make sure that an image submit doesn't cause the callback to be called twice.
run_test 'Image button', 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => [ 'myCallbackTester|count_cb.x' => 18,
                 'myCallbackTester|count_cb.y' => 24 ]
  },
  "1";

# Make sure an exception get thrown for a non-existant package.
run_test 'Non-existant exception', 500,
  { uri => '/test.html?myNoSuchLuck|foo_cb=1' },
  0, 0, qr/No such callback package 'myNoSuchLuck'/;

# Make sure an exception get thrown for a non-existant callback.
run_test 'Non-existent callback', 500,
  { uri => '/test.html?myCallbackTester|foo_cb=1' },
  0, 0, qr/No callback found for callback key 'myCallbackTester|foo_cb'/;

# Make sure that redirects work.
run_test "Redirects", 302,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|redir_cb' => 0,
                'myCallbackTester|set_status_ok_cb9' => 1 ]
  },
  0, { Location => 'http://example.com/'};

# Make sure that redirect without abort works.
run_test "Redirect without abort", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|redir_cb' => 1,
                'myCallbackTester|set_status_ok_cb9' => 1 ]
  };


# Test "redirected" attribute.
run_test 'redirected attribute', 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|redir_cb' => 1,
                'myCallbackTester|test_redirected_cb9' => 1 ]
  },
  'yes';

# Test "redirected" attribute for false value.
run_test "false redirected attribute", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|test_redirected_cb' => 1 ]
  },
  'no';

# Test "aborted" for false value.
run_test "false aborted", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|test_aborted_cb' => 0 ]
  },
  'no';

# Try the before request callback.
run_test "before request callback", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => [result   => 'success',
                do_upper => 1 ]
  },
  "SUCCESS";

    # Try the after request callback.
run_test "after request callback", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|simple_cb' => 1,
                'do_upper'                   => 1]
  },
  "SUCCESS";

# Now check the priority attribute of the MasonX::CallbackHandler.
run_test "priority attribute", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|chk_priority_cb'  => 1,
                'myCallbackTester|chk_priority_cb9' => 1,
                'myCallbackTester|chk_priority_cb2' => 1 ]
  },
  "259";

# Now check the cb_key attribute of the MasonX::CallbackHandler.
run_test "cb_key attribute", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|cb_key1_cb1' => 1,
                'myCallbackTester|cb_key2_cb2' => 1,
                'myCallbackTester|cb_key3_cb3' => 1 ]
  },
  "cb_key1cb_key2cb_key3";


# Now check the pkg_key attribute of the MasonX::CallbackHandler.
run_test "pkg_key attribute", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester1|pkg_key1_cb1' => 1,
                'myCallbackTester2|pkg_key2_cb2' => 1,
                'myCallbackTester3|pkg_key3_cb3' => 1 ]
  },
  'myCallbackTester1myCallbackTester2myCallbackTester3';

# Now check the class_key accessor of the MasonX::CallbackHandler.
run_test "pkg_key attribute", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester1|class_key1_cb1' => 1,
                'myCallbackTester2|class_key2_cb2' => 1,
                'myCallbackTester3|class_key3_cb3' => 1 ]
  },
  'myCallbackTester1myCallbackTester2myCallbackTester3';

# Now check the trigger_key attribute of the MasonX::CallbackHandler.
run_test "trigger_key", 200,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|trig_key1_cb1' => 1,
                'myCallbackTester|trig_key2_cb2' => 1,
                'myCallbackTester|trig_key3_cb3' => 1 ]
  },
  'myCallbackTester|trig_key1_cb1'
  . 'myCallbackTester|trig_key2_cb2'
  . 'myCallbackTester|trig_key3_cb3';

# Now try to die in the callback.
run_test "die in callback", 500,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|exception_cb' => 0 ]
  },
  0, 0, qr/\[error\]\s+Error thrown by callback: He's dead, Jim/;

# Now throw an exception in the callback.
run_test "exception in callback", 500,
  { uri     => '/test.html',
    method  => 'POST',
    content => ['myCallbackTester|exception_cb' => 1 ]
  },
  0, 0,  qr/\[error\]\s+He's dead, Jim/;

__END__
