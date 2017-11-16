# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4

# This file is part of Sympa, see top-level README.md file for details

package Sympa::Spool::Held;

use strict;
use warnings;

use Conf;

use base qw(Sympa::Spool);

sub _directories {
    return {directory => $Conf::Conf{'queueauth'},};
}

use constant _generator => 'Sympa::Message';

sub _glob_pattern { shift->{_pattern} }

use constant _marshal_format => '%s@%s_%s';
use constant _marshal_keys   => [qw(localpart domainpart AUTHKEY)];
use constant _marshal_regexp => qr{\A([^\s\@]+)\@([-.\w]+)_([\da-f]+)\z};
use constant _store_key      => 'authkey';

sub new {
    my $class   = shift;
    my %options = @_;

    my $self = $class->SUPER::new(%options);
    $self->{_pattern} =
        Sympa::Spool::build_glob_pattern($self->_marshal_format,
        $self->_marshal_keys, %options);

    $self;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sympa::Spool::Held - Spool for held messages waiting for confirmation

=head1 SYNOPSIS

  use Sympa::Spool::Held;

  my $spool = Sympa::Spool::Held->new;
  my $authkey = $spool->store($message);

  my $spool =
      Sympa::Spool::Held->new(context => $list, authkey => $authkey);
  my ($message, $handle) = $spool->next;

=head1 DESCRIPTION

L<Sympa::Spool::Held> implements the spool for held messages waiting for
confirmation.

=head2 Methods

See also L<Sympa::Spool/"Public methods">.

=over

=item new ( [ context =E<gt> $list ], [ authkey =E<gt> $authkey ] )

=item next ( [ no_lock =E<gt> 1 ] )

If the pairs describing metadatas are specified,
contents returned by next() are filtered by them.

=item quarantine ( )

Does nothing.

=item store ( $message, [ original =E<gt> $original ] )

If storing succeeded, returns authentication key.

=back

=head2 Context and metadata

See also L<Sympa::Spool/"Marshaling and unmarshaling metadata">.

This class particularly gives following metadata:

=over

=item {authkey}

Authentication key generated automatically
when the message is stored to spool.

=back

=head1 CONFIGURATION PARAMETERS

Following site configuration parameters in sympa.conf will be referred.

=over

=item queueauth

Directory path of held message spool.

Note:
Named such by historical reason.

=back

=head1 SEE ALSO

L<sympa_msg(8)>, L<wwsympa(8)>,
L<Sympa::Message>, L<Sympa::Spool>.

=head1 HISTORY

L<Sympa::Spool::Held> appeared on Sympa 6.2.8.

=cut
