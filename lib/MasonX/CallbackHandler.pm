=head1 NAME

MasonX::CallbackHandler - (Deleted) Mason callback request class and OO callback base class

=head1 SYNOPSIS

This module no longer works and has been deleted. It has been replaced with
MasonX::Interp::WithCallbacks, which allows callbacks to be executed outside
of a mod_perl environment as well as inside mod_perl.

=head1 DESCRIPTION

This module has been B<deleted> and older versions removed from CPAN. Please
use L<MasonX::Interp::WithCallbacks|MasonX::Interp::WithCallbacks>, instead.

MasonX::ApacheHandler::WithCallbacks was a first stab at designing a
parameter-triggered callback architecture, and I soon realized that it could
be generalized not only for other templating systems, but also for all of
Mason, not just Mason running under ApacheHandler. Thus I abstracted out the
callback handling code to C<Params::CallbackRequest|Params::CallbackRequest>,
and developed MasonX::Interp::WithCallbacks to replace
MasonX::ApacheHandler::WithCallbacks. MasonX::CallbackHandler was replaced
with L<Params::Callback|Params::Callback>, and MasonX::CallbackTester has been
eliminated altogether.

If you wish to find a copy of this module, please look on the BackPAN
historical CPAN archive. L<http://history.perl.org/backpan/>

=head1 AUTHOR

David Wheeler <david@wheeler.net>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by David Wheeler

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
