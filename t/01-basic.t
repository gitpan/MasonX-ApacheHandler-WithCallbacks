# $Id: 01-basic.t,v 1.2 2003/01/02 22:40:16 david Exp $

use strict;
use Test::More tests => 16;
use File::Spec::Functions qw(catdir);
use lib 'lib', catdir('t', 'lib');
use Apache::test qw(have_httpd);

##############################################################################
# Figure out if an apache configuration was prepared by Makefile.PL.
unless (-e catdir('t', 'httpd.conf') and -x catdir('t', 'httpd')) {

    # Skip all of the tests.
    SKIP: { skip "No apache server configuration", 11 }

    # And just exit if there's no apache config.
    exit;
}

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
    { request   => { uri     => '/test.html?myNoSuchLuck|foo_cb=1',
                   },
      code      => '500'
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

  );


##############################################################################
# Start up Apache.
die "Unable to start apache" unless have_httpd;
ok(1, "Server started");

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
}

__END__
