use ExtUtils::MakeMaker;

warn <<"DELETION_WARN";

MasonX::ApacheHandler::WithCallbacks has been deleted, there is no code
in this distribution. Please use MasonX::Interp::WithCallbacks, instead.

If you wish to find the old MasonX::ApacheHandler::WithCallbacks, it is
available on BackPAN.

  http://history.perl.org/backpan/

DELETION_WARN

WriteMakefile(
    NAME    => 'MasonX::ApacheHandler::WithCallbacks',
    VERSION => '1.10');
