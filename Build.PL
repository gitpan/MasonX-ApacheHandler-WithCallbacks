use Module::Build;

warn <<"DELETION_WARN";

MasonX::ApacheHandler::WithCallbacks has been deleted, there is no code
in this distribution. Please use MasonX::Interp::WithCallbacks, instead.

If you wish to find the old MasonX::ApacheHandler::WithCallbacks, it is
available on BackPAN.

  http://history.perl.org/backpan/

DELETION_WARN

Module::Build->new( module_name  => 'MasonX::ApacheHandler::WithCallbacks',
                    dist_version => '1.10',
                    license      => 'perl',
                  )->create_build_script;
