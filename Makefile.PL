use ExtUtils::MakeMaker;
use Apache::test;
use FindBin;
use File::Spec::Functions qw(catdir catfile);
use File::Path;

if (my %params = Apache::test->get_test_params) {
    # We can use apache to test the module during "make test".
    make_confs();
    make_data_dir();

    my $include = 'INCLUDE ' . catdir($FindBin::Bin, 't', 'test.conf');

    Apache::test->write_httpd_conf( %params, include => $include );
    *MY::test = sub { Apache::test->MM_test(%params) };
}

my $clean = join ' ', map { catfile('t', $_) }
  qw(*.conf httpd.* error_log httpd data);

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'MasonX::ApacheHandler::WithCallbacks',
    'VERSION_FROM'	=> 'lib/MasonX/ApacheHandler/WithCallbacks.pm',
    'PREREQ_PM'		=> { HTML::Mason => '1.10',
                             mod_perl    => '1.22' },
    'clean'             => { FILES => $clean },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/MasonX/ApacheHandler/WithCallbacks.pm',
       AUTHOR     => 'David Wheeler <david@wheeler.net>') : ()),
);

sub make_confs {
    # Get a list of all of the .conf files we'll be testing.
    my $conf_dir = catdir('t', 'conf');
    opendir DIR, $conf_dir or die "Cannot open directory '$conf_dir': $!\n";
    while (my $file = readdir DIR ) {
        next unless $file =~ /\.conf$/;
        # Copy the file to t/ and set the component root and data directory.
        my $in = catfile('t', 'conf', $file);
        my $out = catfile('t', $file);
        open IN, $in or die "Cannot open '$in': $!\n";
        open OUT, ">$out" or die "Cannot open '$out': $!\n";
        while (<IN>) {
            s/TEST\s+(.*)$/catdir($FindBin::Bin, 't', $1)/e;
            print OUT;
        }
    }

    # Write out a default, empty test include .conf.
    my $test_conf = catfile('t', 'test.conf');
    open CONF, ">$test_conf" or die "Cannot open '$test_conf': $!\n";
    close CONF;
}

sub make_data_dir {
    # Create the data directory if it doesn't exist.
    my $data_dir = catdir('t', 'data');
    mkdir $data_dir, 0777 or die "Can't make dir '$data_dir': $!\n"
      unless -d $data_dir;

    # Allow anyone to write files to the data directory.
    chmod 0777, $data_dir or die "Can't chmod '$data_dir'\n";
}
