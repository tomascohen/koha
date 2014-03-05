package Koha::Template::Plugin::Covers::CBUC;

# This file is part of Koha.
#
# Copyright (C) 2014  Tomas Cohen Arazi for OREX
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use C4::Context;
use Template::Plugin;
use base qw( Template::Plugin );

use vars qw/$user $pass $institution $image_size $base_url/;

sub new {

    my ( $class ) = @_;
    my $self = {} ;

    $self = bless $self, $class ;
    $self->_initialize();

    return $self;
}

sub _initialize {

    my $self = shift;

    $self->{ user }        = C4::Context->preference('CBUCUsername')    //'';
    $self->{ pass }        = C4::Context->preference('CBUCPassword')    // '';
    $self->{ institution } = C4::Context->preference('CBUCInstitution') // 'ICUB';
    $self->{ image_size }  = C4::Context->preference('CBUCImageSize')   // 'p';
    $self->{ base_url }    = C4::Context->preference('CBUCBaseUrl')    //
                                "http://cobertes.cbuc.cat/cobertes.php?";
    return $self;
}

sub GetCoverFromISBN {

    my ( $self, $isbn_param ) = @_;
    my $isbn;

    # We don't build URL if no ISBN passed
    return unless defined $isbn_param;

    if ( ref $isbn_param eq 'ARRAY') {
        $isbn = @$isbn_param[0]->{ marcisbn };
    } else {
        $isbn = $isbn_param;
    }

    my $cover_url = $self->_BuildCBUCCoverURL( $isbn );

    return $cover_url;
}


sub GetCoverFromISSN {

    my ( $self, $issn_param ) = @_;
    my $issn;

    # We don't build URL if no ISBN passed
    return unless defined $issn_param;

    if ( ref $issn_param eq 'ARRAY') {
        $issn = @$issn_param[0];
    } else {
        $issn = $issn_param;
    }

    my $cover_url = $self->_BuildCBUCCoverURL( $issn );

    return $cover_url;
}


sub _BuildCBUCCoverURL {

    my ($self, $id_param) = @_;
    my $cover_url = $self->{ base_url };

    # We don't build URL if no ISBN passed
    return unless defined $id_param;
    my $is_id = $id_param;


    # Sanitize ISBN/ISSN (too basic?)
    $is_id =~ s/^\s+//; # ltrim
    $is_id =~ s/\s+$//; # rtrim
    $is_id =~ s/(p|-)//g;

    # Zero padding (commented code just in case)
    # $isbn = sprintf "%010d", $isbn;

    # Build the URL
    $cover_url .= "mida=". $self->{ image_size };

    # The API allows to fetch cover images without an institution code
    # we use the institution code, or continue without it
    if ( $self->{ institution } ne '') {
        $cover_url .= "&institucio=" . $self->{ institution };
    }

    $cover_url .= "&isbn=" . $is_id;

    return $cover_url;
}

1;

__END__

=head1 NAME

Koha::Template::Plugin::Covers::CBUC

=head1 DESCRIPTION

Template::Toolkit plugin for retrieving cover images from CBUC.

This plugin is syspref-controlled:

=head3 CBUCUsername

  Username provided by CBUC (not actually used).

=head3 CBUCPassword

  Password provided by CBUC (not actually used).

=head3 CBUCInstitution

  Institution ID for cover retreival.

=head3 CBUCImageSize

  Desired image size (falls back to 'p', 'm' and 'g' are valid too).

=head3 CBUCBaseURL

  Base URL for cover retrieval. Defaults to 'http://cobertes.cbuc.cat/cobertes.php?'.

=head1 FUNCTIONS

=head2 GetCoverFromISBN

    $cover_url = GetCoverFromISBN( $isbn );
    $cover_url = GetCoverFromISBN( GetMarcISBN ( $record, $marcflavour ) );

=head2 GetCoverFromISSN

    $cover_url = GetCoverFromISSN( $issn );
    $cover_url = GetCoverFromISSN( GetMarcISSN ( $record, $marcflavour ) );

=head1 USAGE

=head2 Include in your TT templates

Just include it as any other TT plugin:

    [% USE Covers.CBUC %]

It might be convenient to check for the CBUCEnabled syspref for inclusion:

    [% IF Koha.Preference( 'CBUCEnabled' ) %]
        [% USE Covers.CBUC %]
    [% END %]

=head2 Use the provided functions like this:

    <img src="[% Covers.CBUC.GetCoverFromISSN( MARCISSNS ) %]"
         alt="" class="item-thumbnail" />
or
    <img src="[% Covers.CBUC.GetCoverFromISBN( normalized_isbn ) %]"
         alt="" class="item-thumbnail" />

=head1 NOTES

CBUC's API is vague (or non-existent) in many senses. There's an option to
authenticate the conection but no visible benefit can be guessed.

=head1 AUTHOR

Tomas Cohen Arazi <tomascohen@gmail.com>

=cut
