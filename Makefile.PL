use ExtUtils::MakeMaker;
use FindBin;
use File::Path;
use File::Spec::Functions qw(catdir catfile);
use Apache::TestMM qw(test clean);
use Apache::TestRunPerl;

Apache::TestMM::filter_args();
Apache::TestRunPerl->generate_script();
make_data_dir();

my $clean = join ' ', map { catfile('t', $_) }
  qw(data TEST logs);

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'MasonX::ApacheHandler::WithCallbacks',
    'VERSION_FROM'	=> 'lib/MasonX/ApacheHandler/WithCallbacks.pm',
    'PREREQ_PM'		=> { HTML::Mason  => '1.10',
                             Apache::Test => '1.03',
                             mod_perl     => '1.22' },
    'clean'             => { FILES => $clean },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/MasonX/ApacheHandler/WithCallbacks.pm',
       AUTHOR     => 'David Wheeler <david@wheeler.net>') : ()),
);

sub make_data_dir {
    # Create the data directory if it doesn't exist.
    my $data_dir = catdir('t', 'data');
    mkdir $data_dir, 0777 or die "Can't make dir '$data_dir': $!\n"
      unless -d $data_dir;

    # Allow anyone to write files to the data directory.
    chmod 0777, $data_dir or die "Can't chmod '$data_dir'\n";
}
