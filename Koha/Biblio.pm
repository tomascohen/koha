package Koha::Biblio;

# Copyright 2014 Universidad Nacional de Cordoba
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Koha::Database;

=head1 FUNCTIONS

=cut

=head2 GetBiblio

  my $biblio = GetBiblio( $biblionumber, $deleted );

=cut

sub GetBiblio {

    my ( $biblionumber, $deleted ) = @_;

    my $schema = Koha::Database->new()->schema();
    my $table  = ( $deleted ) ? 'Deletedbiblio' : 'Biblio';

    my $resultset = $schema->resultset( $table );
    $resultset->result_class('DBIx::Class::ResultClass::HashRefInflator');

    return $resultset->find({ biblionumber => $biblionumber });
}

=head2 GetBiblioData

  $data = GetBiblioData($biblionumber);

Returns information about the book with the given biblionumber.
C<&GetBiblioData> returns a reference-to-hash. The keys are the fields in
the C<biblio> and C<biblioitems> tables in the
Koha database.

In addition, C<$data-E<gt>{subject}> is the list of the book's
subjects, separated by C<" , "> (space, comma, space).
If there are multiple biblioitems with the given biblionumber, only
the first one is considered.

=cut

sub GetBiblioData {
    my ( $biblionumber, $deleted ) = @_;

    my $schema            = Koha::Database->new()->schema();
    my $biblioitem_table = ( $deleted ) ? 'Biblioitem' : 'Deletedbiblioitem';
    my $biblio_table      = ( $deleted ) ? 'Biblio'      : 'Deletedbiblio';

    my $biblionumber_field = $biblio_table . ".biblionumber";

    my %resultset = $schema->resultset( $biblio_table )->search(
      {
        $biblionumber_field => $biblionumber
      },
      {
        join     => [ $biblioitem_table, 'Itemptypes' ]
      }
    );

    return \%resultset;
}


1;