# $Id: 01-basic.t,v 1.7 2003/02/14 22:43:02 david Exp $

use strict;
use Test::More tests => 25;
use File::Spec::Functions qw(catdir catfile);
use File::Copy qw(copy);
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
# Kill Apache and copy the appropriate .conf for Apache to load.
local $| = 1;
kill_httpd(20);
copy catfile('t', 'basic.conf'), catfile('t', 'test.conf');
start_httpd();

##############################################################################
# Create the hashes that define the test requets.
my @test_reqs =
  # First, make sure it works.
  ( { request => { uri     => '/test.html?myCallbackTester|simple_cb=1'
                 },
      expect  => "Success"
    },

    # Make sure that POST works.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|simple_cb=1'
                 },
      expect  => "Success"
    },

    # Check that multiple callbacks execute in priority order.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|priority_cb0=0'
                              . '&myCallbackTester|priority_cb2=2'
                              . '&myCallbackTester|priority_cb9=9'
                              . '&myCallbackTester|priority_cb7=7'
                              . '&myCallbackTester|priority_cb1=1'
                              . '&myCallbackTester|priority_cb4=4'
                              . '&myCallbackTester|priority_cb=def'
                 },
      expect  => " 0 1 2 4 5 7 9"
    },

    # Execute the one callback with an array of values
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|multi_cb=1'
                              . '&myCallbackTester|multi_cb=1'
                              . '&myCallbackTester|multi_cb=1'
                              . '&myCallbackTester|multi_cb=1'
                              . '&myCallbackTester|multi_cb=1'
                 },
      expect  => "5"
    },

    # Emmulate the sumission of an <input type="image" /> button.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|simple_cb.x=18'
                              . 'myCallbackTester|simple_cb.y=24'
                 },
      expect  => "Success"
    },

    # Make sure an exception get thrown for a non-existant callback.
    { request => { uri     => '/test.html?myNoSuchLuck|foo_cb=1',
                 },
      code    => '500',
      regex   => qr/No callback found for callback key 'myNoSuchLuck|foo_cb'/
    },

    # Make sure that redirects work.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|redir_cb=0'
                              . '&myCallbackTester|set_status_ok_cb9=1'
                 },
      code    => '302',
      headers => { Location => 'http://example.com/'},
    },

    # Make sure that redirect without abort works.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|redir_cb=1'
                              . '&myCallbackTester|set_status_ok_cb9=1'
                 },
      code    => '200',
    },

    # Test "redirected" attribute.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|redir_cb=1'
                              . '&myCallbackTester|test_redirected_cb9=1'
                 },
      expect  => 'yes'
    },

    # Test "redirected" attribute for false value.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|test_redirected_cb=1'
                 },
      expect  => 'no'
    },

    # Test abort.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|test_aborted_cb=1'
                 },
      expect  => 'yes'
    },

    # Test "aborted" for false value.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|test_aborted_cb=0'
                 },
      expect  => 'no'
    },

    # Try the before request callback.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'result=success&do_upper=1'
                 },
      expect  => "SUCCESS"
    },

    # Try the after request callback.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|simple_cb=1&do_upper=1'
                 },
      expect  => "SUCCESS"
    },

    # Now check the priority attribute of the MasonX::CallbackHandle.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|chk_priority_cb=1'
                              . '&myCallbackTester|chk_priority_cb9=1'
                              . '&myCallbackTester|chk_priority_cb2=1'
                 },
      expect  => "259"
    },

    # Now check the cb_key attribute of the MasonX::CallbackHandle.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|cb_key1_cb1=1'
                              . '&myCallbackTester|cb_key2_cb2=1'
                              . '&myCallbackTester|cb_key3_cb3=1'
                 },
      expect  => "cb_key1cb_key2cb_key3"
    },

    # Now check the pkg_key attribute of the MasonX::CallbackHandle.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester1|pkg_key1_cb1=1'
                              . '&myCallbackTester2|pkg_key2_cb2=1'
                              . '&myCallbackTester3|pkg_key3_cb3=1'
                 },
      expect  => 'myCallbackTester1myCallbackTester2myCallbackTester3',
    },

    # Now check the trigger_key attribute of the MasonX::CallbackHandle.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|trig_key1_cb1=1'
                              . '&myCallbackTester|trig_key2_cb2=1'
                              . '&myCallbackTester|trig_key3_cb3=1'
                 },
      expect  => 'myCallbackTester|trig_key1_cb1'
                 . 'myCallbackTester|trig_key2_cb2'
                 . 'myCallbackTester|trig_key3_cb3'
    },

    # Now try to die in the callback.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|exception_cb=0'
                 },
      code    => '500',
      regex   => qr/\[error\]\s+Error thrown by callback: He's dead, Jim/
    },

    # Now throw an exception in the callback.
    { request => { uri     => '/test.html',
                   method  => 'POST',
                   content => 'myCallbackTester|exception_cb=1'
                 },
      code    => '500',
      regex   => qr/\[error\]\s+He's dead, Jim/
    },

  );


##############################################################################
# Start up Apache.
ok(1, "Server started");
my $logfile = catfile('t', 'error_log');

# Now run the tests.
foreach my $test (@test_reqs) {
    # Grab the http response.
    my $res = Apache::test->fetch($test->{request});

    # Test the expect content.
    if ($test->{expect}) {
        is( $res->content, $test->{expect},
            "Check for content '$test->{expect}'" );
    }

    # Test the response code.
    if ($test->{code}) {
        is( $res->code, $test->{code},
            "Check for code '$test->{code}'" );
    }

    # Test the headers.
    if (my $headers = $test->{headers}) {
        while (my ($h, $v) = each %$headers) {
            is( $res->header($h), $v, "Check for '$v' header" );
        }
    }

    # Scan the log.
    if (my $regex = $test->{regex}) {
        open LOG, $logfile or die "Cannot open '$logfile': $!\n";
        local $/;
        my $log = <LOG>;
        close LOG;
        like( $log, $regex, "Check log" );
    }
}

__END__
