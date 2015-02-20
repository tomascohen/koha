package Koha::Filter::MARCXML::ViewPolicy;

# Copyright 2015 Theke Solutions

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

Koha::Filter::MARCXML::ViewPolicy - Prepare records for display

=head1 SYNOPSIS

This filter processes a Koha::Search::Result objects representing search result
record, and hides fields/subfields as specified by the frameworks. It also
substitutes authorized value codes for their corresponding descriptions.

=head1 DESCRIPTION

Filter to embed see from headings into MARC records.

=cut

use Modern::Perl;
use Carp;

use C4::Biblio qw/ GetMarcStructure /;
use C4::ClassSource;
use C4::Context;
use C4::Koha;
use Koha::Search::Result;

use Encode qw/ encode /;
use XML::LibXSLT;

use base qw(Koha::RecordProcessor::Base);
our $NAME = 'ViewPolicy';
our $VERSION = '1.0';

=head2 filter

    my $filter = Koha::RecordProcessor->new( { filters => ( 'ViewPolicy' ) } );
    my $filtered_search_result = $filter->process($search_result);

=cut

sub filter {

    my $self  = shift;
    my $param = shift;
    my $options = shift;
    my $result;

    my $branch = $options->{ branch };
    my $interface = $options->{ interface } // 'opac';

    return unless defined $param;

    if (ref $param eq 'ARRAY') {
        my @object_array;
        foreach my $this_object (@$param) {
            next if ref $this_object ne 'Koha::Search::Result';
            push @object_array, _processobject($this_object,$branch,$interface);
        }
        $result = \@object_array;
    } elsif (ref $param eq 'Koha::Search::Result') {
        $result = _processobject($param,$branch,$interface);
    }

    return $result;
}


sub _processobject {

    my $result_object = shift;
    my $branch    = shift;
    my $interface = shift;

    # Create the XSLT processor
    my $xslt = XML::LibXSLT->new();
    my $framework = C4::Biblio::GetFrameworkCode( $result_object->id );
    # Generate the XSLT code
    my $xslt_filter =  _buildXSLTFrameworkFilter( $framework, $interface, $branch );
    # Create the stylesheet XML object out of the code
    my $style_raw = XML::LibXML->load_xml( string => $xslt_filter, no_cdata => 1 );
    my $stylesheet = $xslt->parse_stylesheet( $style_raw );
    # Return a new Koha::Search::Result object containing the
    # transformed record.
    return Koha::Search::Result->new({
        schema => $result_object->schema(),
        id     => $result_object->id(),
        record => $stylesheet->transform( $result_object->record() )
    });
}

=head2

    my $authorized_values = _buildAuthorizedValuesFilter( $interface, $branch )

Given an interface ('opac' or 'intranet') and a branchcode this function returns a collection
of XSLT templates named following the schema authval-handling-$categorycode-$interface-$branch
to be called when building an XSLT for filtering XML data for display. Its purpose is to
replace authorized value codes for descriptions when the corresponding cataloguing framework
requires it.

=cut

sub _buildAuthorizedValuesXSLT {

    my ( $interface, $branch ) = @_;

    my $opac = ( $interface eq 'opac' ) ? 1 : 0;
    my $categories = GetAuthorisedValueCategories();
    # Add hardcoded categories too...
    push @{ $categories }, 'itemtypes';
    push @{ $categories }, 'branches';
    push @{ $categories }, 'cn_source';

    my $xslt = "";

    foreach my $category ( @{ $categories } ) {
        my $category_xslt = _buildAuthorizedValueXSLT( $category, $interface, $branch );
        $xslt .= $category_xslt if defined $category_xslt;
    }

    return $xslt;
}

=head2

    my $xslt = _buildAuthorizedValueXSLTTemplate( $category_code, $interface, $branch )

This function returns an XSLT template to be applied on subfields of MARCXML data that contains
authorized value codes. The result is the substitution of the code, for the corresponding description
for the specified interface (opac or intranet).

NOTE: This function is not intended to be used directly, but in the context of the generation of XSLTs
for filtering out the contents of MARCXML for rendering.

=cut

sub _buildAuthorizedValueXSLT {
    
    my ( $category_code, $interface, $branch ) = @_;

    my $opac = ( $interface eq 'opac' ) ? 1 : 0;
    my $category_values;

    # Handle hardcoded ones as exceptions
    if ( $category_code eq 'branches') {
        $category_values = _buildBranchesNames();
    }
    elsif ( $category_code eq 'itemtypes' ) {
        $category_values = _buildItemTypeNames();
    }
    elsif ( $category_code eq 'cn_source' ) {
        $category_values = _buildCNSourceNames();
    }
    else {
       $category_values = GetAuthorisedValues( $category_code, undef, $opac ); 
    }

    my $xslt = "  <xsl:template name=\"authval-handling-";
    $xslt .= $category_code;
    $xslt .= "-" . $interface;
    $xslt .= "-" . $branch;
    $xslt .= "\">\n";
    $xslt .=<<'EOXSL';
    <xsl:param name="authcode"/>
    <xsl:choose>
EOXSL


    foreach my $authorized_value ( @{ $category_values } ) {
        $xslt .= "      <xsl:when test=\"\$authcode='" . $authorized_value->{ authorised_value } . "'\">" .
                      "<xsl:text>" . $authorized_value->{ lib } . "</xsl:text></xsl:when>\n";
    }

    $xslt .= "      <xsl:otherwise><xsl:value-of select=\"\$authcode\"/></xsl:otherwise>\n";
    $xslt .=<<'EOXSL';
    </xsl:choose>
  </xsl:template>
EOXSL

    return $xslt;
}

## Helper functions we should get rid of ASAP.

sub _buildItemTypeNames {
    my $itemtypes;
    my $dbh = C4::Context->dbh();
    my $sth = $dbh->prepare("SELECT itemtype,description FROM itemtypes"); # FIXME : use C4::Branch::GetBranches
    $sth->execute();

    while ( my $itemtype_data = $sth->fetchrow_hashref ) {
        push @{ $itemtypes },
            {
                authorised_value => $itemtype_data->{ itemtype },
                lib => Encode::encode( 'UTF-8', $itemtype_data->{ description } )
            };
    }

    return $itemtypes;
}

sub _buildBranchesNames {
    my $branches;
    my $dbh = C4::Context->dbh();
    my $sth = $dbh->prepare("SELECT branchcode,branchname FROM branches"); # FIXME : use C4::Branch::GetBranches
    $sth->execute();

    while ( my $branch_data = $sth->fetchrow_hashref ) {
        push @{ $branches },
            {
                authorised_value => $branch_data->{ branchcode },
                lib => Encode::encode( 'UTF-8', $branch_data->{ branchname } )
            };
    }

    return $branches;
}

sub _buildCNSourceNames {
    my $sources = GetClassSources();
    my @sources = ();
    foreach my $cn_source (sort keys %$sources) {
        my $source = $sources->{$cn_source};
        push @sources, 
          {  
            authorised_value => $source->{'cn_source'},
            lib              => Encode::encode( 'UTF-8', $source->{'description'} ),
          } 
    }

    return \@sources;
}


=head2

    my $xslt = _buildXSLTFrameworkFilter( $framework, $interface, $branch );

Given a framework code, an interface ('opac' or 'intranet') and a branch code returns
an XSLT transformation to be applied to records retrieved for display.

TODO: $branch should be used to filter authorized value descriptions once it is implemented.

=cut

sub _buildXSLTFrameworkFilter {

    my ( $framework, $interface, $branch ) = @_;

    my $xslt = "";
    my $forlibrarian   = ( $interface eq 'intranet' ) ? 1 : 0;
    my $marc_structure = GetMarcStructure( $forlibrarian, $framework );
    my $authorized_values_xslt = _buildAuthorizedValueXSLT( $interface, $branch );

    # Loop through tags
    foreach my $field ( keys %{ $marc_structure } ) {
        # Loop through subtags
        foreach my $subfield ( keys %{ $marc_structure->{ $field } }) {
            next if ( $subfield eq 'tab' ||
                      $subfield eq 'mandatory' ||
                      $subfield eq 'repeatable' ||
                      $subfield eq 'lib' );
            # Field visibility
            my $hidden = $marc_structure->{ $field }->{ $subfield }->{ hidden };
            # TODO: someone designed this creepy visibility control, fix this ASAP
            if ( $interface eq 'opac' && $hidden > 0 ) {
                $xslt .= "  <xsl:template match=\"marc:datafield[\@tag='" . $field . "']/marc:subfield[\@code='" . $subfield . "']\"/>\n"
            } elsif ( $hidden == -8 ||
                      $hidden == -4 ||
                      $hidden == -3 ||
                      $hidden == -2 ||
                      $hidden ==  2 ||
                      $hidden ==  3 ||
                      $hidden ==  5 ||
                      $hidden ==  8 ) {
                # damn. staff interface, complex calculation of visibility
                $xslt .= "  <xsl:template match=\"marc:datafield[\@tag='" . $field . "']/marc:subfield[\@code='" . $subfield . "']\"/>\n"
            } else {
                # Field should not be hidden. Call the Authorized Value template if specified by the framework
                if ( $marc_structure->{ $field }->{ $subfield }->{ authorised_value } &&
                     $marc_structure->{ $field }->{ $subfield }->{ authorised_value } ne '' ) {
                    my $categorycode = $marc_structure->{ $field }->{ $subfield }->{ authorised_value };
                    $xslt .= "  <xsl:template match=\"marc:datafield[\@tag='$field']/marc:subfield[\@code='$subfield']\">\n";
                    $xslt .= "    <xsl:copy>\n";
                    $xslt .= "      <xsl:copy-of select=\"\@*\"/>\n";
                    $xslt .= "      <xsl:call-template name=\"authval-handling-$categorycode-$interface-$branch\">\n";
                    $xslt .= "        <xsl:with-param name=\"authcode\"><xsl:value-of select=\".\"/></xsl:with-param>\n";
                    $xslt .= "      </xsl:call-template>\n";
                    $xslt .= "    </xsl:copy>\n";
                    $xslt .= "  </xsl:template>\n";
                }
            }
        }
    }

    my $xslt_header =<<'EOHEADER';
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:marc="http://www.loc.gov/MARC21/slim"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
  <!--xsl:strip-space elements="*"/-->

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

EOHEADER

    my $xslt_footer =<<'EOFOOTER';
</xsl:stylesheet>
EOFOOTER

    return $xslt_header . $authorized_values_xslt . $xslt . $xslt_footer if defined $xslt;
}

1;

=head1 AUTHOR

Tomas Cohen Arazi <tomascohen@gmail.com>

Koha Development Team <http://koha-community.org/>

=cut
