use ExtUtils::MakeMaker;
use Apache::test;
use FindBin;
use File::Spec::Functions qw(catdir catfile);
use File::Path;

if (my %params = Apache::test->get_test_params) {
    # We can use apache to test the module during "make test".
    make_comps();

    my $include;
    while (<DATA>) {
        s/TEST\s+(.*)$/catdir($FindBin::Bin, 't', $1)/e;
        $include .= $_;
    }

    Apache::test->write_httpd_conf( %params, include => $include );
    *MY::test = sub { Apache::test->MM_test(%params) };
}

my $clean = join ' ', map { catfile('t', $_) }
  qw(httpd.conf httpd.loc httpd.pid error_log httpd comp data);

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'MasonX::ApacheHandler::WithCallbacks',
    'VERSION_FROM'	=> 'lib/MasonX/ApacheHandler/WithCallbacks.pm',
    'PREREQ_PM'		=> {HTML::Mason => '1.10',
                            mod_perl    => '1.22' },
    'clean'        => {FILES => $clean },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/MasonX/ApacheHandler/WithCallbacks.pm',
       AUTHOR     => 'David Wheeler <david@wheeler.net>') : ()),
);

sub make_comps {
    # Create the component root if it doesn't exist.
    my $comp_root = catdir('t', 'comp');
    mkdir $comp_root or die "Can't make dir '$comp_root': $!\n"
      unless -d $comp_root;

    # Create the data directory if it doesn't exist.
    my $data_dir = catdir('t', 'data');
    mkdir $data_dir or die "Can't make dir '$data_dir': $!\n"
      unless -d $data_dir;

    # Allow anyone to write files to the data directory.
    chmod 0777, $data_dir or die "Can't chmod '$data_dir'\n";

    # Write the test component if it doesn't exist.
    my $test_mc = catfile($comp_root, 'test.html');
    unless (-f $test_mc) {
        open MC, ">$test_mc" or die "Cannot open '$test_mc' : $!\n";
        print MC '% $m->print($ARGS{result});';
        close MC;
    }
}

__DATA__
DocumentRoot TEST comp
PerlSetVar MasonCompRoot TEST comp
PerlSetVar MasonDataDir TEST data
PerlSetVar MasonDefaultPriority 5
PerlSetVar MasonDefaultPkgKey myCallbackTester
PerlSetVar MasonDeferStatusCheck 1
PerlModule MasonCallbackTester
PerlModule MasonX::ApacheHandler::WithCallbacks
SetHandler perl-script
#PerlHandler MasonX::ApacheHandler::WithCallbacks
PerlHandler MasonCallbackTester
