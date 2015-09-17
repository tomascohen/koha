package C4::IndicesItems;

# Copyright Biblioteca Real
#
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


use strict;
use C4::Context;
use C4::Biblio;
use C4::Auth;
use C4::AuthoritiesMarc;
use C4::Search;
use C4::Charset;
use ZOOM;
use MARC::Record;
use MARC::File::USMARC;
use MARC::File::XML ( BinaryEncoding => 'utf8', RecordFormat => 'USMARC' );
use XML::LibXML;
use Data::Dumper;
use Digest::SHA qw(sha1_base64);

sub new
{
    my $that = shift;
    my ($indexFieldsRef) = @_;

    my %indexFields = ('901' => {'a' => 1, '0' => 1, '9' => 1}, '902' => {'a' => 1, '0' => 1, '9' => 1}, '903' => {'a' => 1, '0' => 1}, '911' => {'a' => 1, '0' => 1, '9' => 1}, '912' => {'a' => 1, '0' => 1, '9' => 1}, '921' => {'a' => 1, '0' => 1}, '931' => {'a' => 1, '0' => 1});
    my $indexFields = (defined($indexFieldsRef))?$indexFieldsRef:\%indexFields;

    my %ESCAPES = ('&' => '&amp;', '<' => '&lt;', '>' => '&gt;');
    my $ESCAPE_REGEX = eval 'qr/' . join( '|', map { $_ = "\Q$_\E" } keys %ESCAPES ) . '/;';

    my $class = ref($that) || $that;
    my $self = {'indexes' => undef, 'indexFields' => $indexFields, 'ESCAPES' => \%ESCAPES, 'ESCAPE_REGEX' => $ESCAPE_REGEX};
    bless $self, $class;
    $self->fillIndexes();
    return $self;
}#new


sub fillIndexes
{
    my $self = shift;
    
    my %indexes = ('Encuadernador' => {'902' => {'subf' => ['a']}, '912' => {'subf' => ['a']}},
        'Impresor' => {'700' => {'ind1' => [4], 'subf' => ['a']}, '710' => {'ind1' => [4], 'subf' => ['a']}},
        'Incipit' => {'592' => {'subf' => ['a']}},
        'Materia' => {'650' => {'subf' => ['a']}},
        'Olim' => {'903' => {'subf' => ['a']}},
        'Onomastico' => {'100' => {'subf' => ['a']}, '110' => {'subf' => ['a']}, '700' => {'ind1' => [1,2,3], 'subf' => ['a']}, '710' => {'ind1' => [1,2,3], 'subf' => ['a']}},
        'Posesor' => {'901' => {'subf' => ['a']}, '911' => {'subf' => ['a']}, '921' => {'subf' => ['a']}, '931' => {'subf' => ['a']}},
        'Signatura' => {'952' => {'subf' => ['o']}},
        'Titulo' => {'130' => {'subf' => ['a']}, '245' => {'subf' => ['a']}}
    );
    my $indexes = $self->_indexesFromDB();
    if ($indexes) {
        $self->{'indexes'} = $indexes;
    } else {
        $self->{'indexes'} = \%indexes;
    }
}#fillIndexes


sub getNameIndexes
{
    my ($self) = @_;
    
    my @indexes = ();
    for my $name (keys %{$self->{indexes}}) {
        push @indexes, $name;
    }
    @indexes = sort @indexes;
    return \@indexes;
}#getNameIndexes


sub _indexesFromDB
{
    my $self = shift;
    
    my $indexes;
    my $dbh = C4::Context->dbh;
    eval {
        my $sth = $dbh->prepare('SELECT i.indice, ic.tag, ic.code, ic.ind1, ic.ind2 FROM indices i, indices_campos ic WHERE ic.id_indice=i.id_indice ORDER BY i.indice');
        $sth->execute();
        while (my $data = $sth->fetchrow_hashref) {
            $indexes = {} unless ($indexes);
            $indexes->{$data->{indice}} = {} unless (exists($data->{indice}));
            $indexes->{$data->{indice}}->{$data->{tag}} = {} unless (exists($indexes->{$data->{indice}}->{$data->{tag}}));
            my @subf = split(',', $data->{code});
            $indexes->{$data->{indice}}->{$data->{tag}}->{'subf'} = \@subf;
            if ($data->{ind1}) {
                my @ind1 = split(',', $data->{ind1});
                $indexes->{$data->{indice}}->{$data->{tag}}->{'ind1'} = \@ind1;
            }
            if ($data->{ind2}) {
                my @ind2 = split(',', $data->{ind2});
                $indexes->{$data->{indice}}->{$data->{tag}}->{'ind2'} = \@ind2;
            }
        }
        $sth->finish;
    };
    return $indexes;
}#_indexesFromDB


sub createIndexFieldsFromStructure
{
    my ($self, $frameworkcode, $indexFieldsRef) = @_;
    
    my $indexFieldsAux = (defined($indexFieldsRef))?$indexFieldsRef:$self->{indexFields};
    my $dbh = C4::Context->dbh;
    eval {
        my $sth = $dbh->prepare('SELECT tagfield, tagsubfield, hidden FROM marc_subfield_structure WHERE frameworkcode=? AND tagfield IN (\'' . join("','", keys %$indexFieldsAux) . '\')');
        $sth->execute( $frameworkcode );
        while (my $data = $sth->fetchrow_hashref) {
            unless (exists($self->{indexFields}->{$data->{'tagfield'}}->{$data->{'tagsubfield'}})) {
                $self->{indexFields}->{$data->{'tagfield'}}->{$data->{'tagsubfield'}} = 1 if ($data->{hidden} <= 4 && $data->{hidden} >= -4);
            }
        }
        $sth->finish;
    };
}#createIndexFieldsFromStructure


sub getIndexFields
{
    my $self = shift;

    return $self->{indexFields};
}#getIndexFields


sub cleanArraysFormHtml2Xml
{
    my ($self, $itemnumber, $tags, $subfields, $values) = @_;
    
    my $lastValue;
    $lastValue = $values->[$#{$values}] if ($itemnumber && $values->[$#{$values}] && $itemnumber == $values->[$#{$values}]);
    for (my $i = 0; $i < @$tags; $i++) {
        #print $tags->[$i] . ': ';
        if (exists($self->{indexFields}->{$tags->[$i]})) {
            #print ($tags->[$i] . ',' . $subfields->[$i] . ',' . $values->[$i]);
            splice(@$tags,$i,1);
            splice(@$subfields,$i,1);
            splice(@$values,$i,1) if (defined($values->[$i]));
            $i--;
        }
        #print "\n";
    }
    push @$values, $lastValue if ($lastValue);
}#cleanArraysFormHtml2Xml


sub checkLostSubfieldsIndicesField
{
    my ($self, $field_data) = @_;
    
    my @lostSubfields;
    if (exists($self->{indexFields}->{$field_data->{'tag'}})) {
        for my $subfield (keys %{$self->{indexFields}->{$field_data->{'tag'}}}) {
            next unless ($self->{indexFields}->{$field_data->{'tag'}}->{$subfield});
            my $encontrado = 0;
            for (@{$field_data->{'subfields'}}) {
                if ($_->{'subfield'} eq $subfield) {
                    $encontrado = 1;
                    last;
                }
            }
            push @lostSubfields, $subfield unless ($encontrado);
        }
    }
    return \@lostSubfields;
}#checkLostSubfieldsIndicesField



sub _escape {
    my ($self, $string) = @_;

    return '' if ! defined $string or $string eq '';
    my $pattern = $self->{'ESCAPE_REGEX'};
    $string =~ s/($pattern)/$self->{'ESCAPES'}->{$1}/oge;
    return( $string );
}#_escape


sub _record2Xml
{
    my ($self, $record) = @_;

    my @xml = ();
    push @xml, '<?xml version="1.0" encoding="UTF-8"?>
<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/ standards/marcxml/schema/MARC21slim.xsd"
    xmlns="http://www.loc.gov/MARC21/slim">';
    push( @xml, "  <leader>" . $self->_escape( $record->leader ) . "</leader>" );
    foreach my $field ( $record->fields() ) {
        my $tag = $field->tag();
        if ( $field->is_control_field() ) {
            my $data = $field->data;
            push( @xml, qq(  <controlfield tag="$tag">) . $self->_escape( $data ). qq(</controlfield>) );
        } else {
            my $i1 = $field->indicator( 1 );
            my $i2 = $field->indicator( 2 );
            push( @xml, qq(  <datafield tag="$tag" ind1="$i1" ind2="$i2">) );
            foreach my $subfield ( $field->subfields() ) {
                my ( $code, $data ) = @$subfield;
                push( @xml, qq(    <subfield code="$code">). $self->_escape( $data ).qq(</subfield>) );
            }
            push( @xml, "  </datafield>" );
        }
    }
    push( @xml, "</record>\n" );
    return( join( "\n", @xml ) );
}#_record2Xml


sub _updateBiblioItems
{
    my ($self, $biblionumber, $recordBiblio) = @_;

    my $dbh = C4::Context->dbh;
    my $encoding = C4::Context->preference("marcflavour");
    my $ldr = $recordBiblio->leader;
    my $original_encoding = substr($ldr,9,1);
    eval {
        my $sth = $dbh->prepare("UPDATE biblioitems SET marc=?,marcxml=? WHERE biblionumber=?");
        # Para evitar que haga la transformación en el xml de marc8 a utf8 si el carácter 9 del leader no es a
        if (!$original_encoding || $original_encoding ne 'a') {
            $sth->execute( $recordBiblio->as_usmarc(), $self->_record2Xml($recordBiblio), $biblionumber );
        } else {
            $sth->execute( $recordBiblio->as_usmarc(), $recordBiblio->as_xml_record($encoding), $biblionumber );
        }
        $sth->finish;
    };
    return 0 if ($@);
    return 1;
}#_updateBiblioItems

sub delIndicesItem
{
    my ($self, $biblionumber, $itemnumber, $recordBiblio, $modBiblio) = @_;
    
    return 0 unless ($itemnumber);
    $recordBiblio = GetMarcBiblio($biblionumber) unless ($recordBiblio);
    if ($recordBiblio) {
        my $tag;
        my $borrados = 0;
        for $tag (keys %{$self->{indexFields}}) {
            my @fieldsTag = $recordBiblio->field($tag);
            if (@fieldsTag) {
                for my $field (@fieldsTag) {
                    if (defined($field->subfield('0'))) {
                        if (!$field->subfield('0') || $field->subfield('0') == $itemnumber) {
                            $recordBiblio->delete_field($field);
                            $borrados = 1;
                        }
                    } else {
                        $recordBiblio->delete_field($field);
                        $borrados = 1;
                    }
                }
            }
        }
        if ($borrados) {
            unless ($modBiblio) {
                return $self->_updateBiblioItems($biblionumber, $recordBiblio);
            } else {
                my $frameworkcode = GetFrameworkCode($biblionumber);
                ModBiblio($recordBiblio, $biblionumber, $frameworkcode);
            }
        }
    }
    return 1;
}#delIndicesItem


sub addIndicesItemsFromHtml
{
    my ($self, $biblionumber, $itemnumber, $input, $recordBiblio, $BiblioAddsAuthorities, $modBiblio) = @_;
    
    return unless ($itemnumber);
    my ($campoHtml, $tag, $code);
    $recordBiblio = GetMarcBiblio($biblionumber) unless ($recordBiblio);
    if ($recordBiblio) {
        # print Dumper $recordBiblio;
        my %borrados = ();
        my $campo;
        # Se supone que los campos los devuelve en orden tal y como están en el form
        # ver http://search.cpan.org/dist/CGI/lib/CGI.pm#FETCHING_THE_NAMES_OF_ALL_THE_PARAMETERS_PASSED_TO_YOUR_SCRIPT:
        for $campoHtml ($input->param()) {
            #print "$campoHtml:" . $input->param($campoHtml) . "\n";
            if ($campoHtml =~ /^tag([0-9]+)_[0-9]+$/ && exists($self->{indexFields}->{$1})) {
                $tag = $1;
                if (!exists($borrados{$tag})) {
                    for my $campoBorr ($recordBiblio->field($tag)) {
                        if (defined($campoBorr->subfield('0'))) {
                            $recordBiblio->delete_field($campoBorr) if ($campoBorr->subfield('0') == $itemnumber);
                        } else {
                            $recordBiblio->delete_field($campoBorr);
                        }
                    }
                    $borrados{$tag} = 1;
                }
                if ($campo) {
                    $recordBiblio->insert_fields_ordered($campo) if ($campo->subfield('a'));
                    $campo = undef;
                }
                $campo = MARC::Field->new( $tag, '', '', 'a' => '');
            } elsif ($campoHtml =~ /^tag_([0-9]+)_subfield_([a-z0-9])_[0-9]+$/ && $campo) {
                $tag = $1;
                $code = $2;
                if (exists($self->{indexFields}->{$tag}->{$code})) {
                    #print "tag: $tag ; code: $code\n";
                    next if ($code eq '9' && !$input->param($campoHtml));
                    $input->param($campoHtml, $itemnumber) if ($code eq '0' && !$input->param($campoHtml));
                    my $param_value = $input->param($campoHtml);
                    my $param_value2 = $param_value;
                    if (!utf8::is_utf8($param_value2) && utf8::decode($param_value2)) {
                        $param_value = $param_value2;
                    }
                    if ($code eq 'a' && defined($campo->subfield($code)) && !$campo->subfield($code)) {
                        $campo->update('a' => $param_value);
                    } else {
                        $campo->add_subfields($code => $param_value);
                    }
                }
            }
        }
        if ($campo) {
            $recordBiblio->insert_fields_ordered($campo) if ($campo->subfield('a'));
            $campo = undef;
        }
        # print Dumper $recordBiblio;
        # print $self->_record2Xml($recordBiblio);
        my $frameworkcode = GetFrameworkCode($biblionumber);
        $self->_BiblioAddAuthorities($recordBiblio, $frameworkcode) if ($BiblioAddsAuthorities);
        unless ($modBiblio) {
            $self->_updateBiblioItems($biblionumber, $recordBiblio);
        } else {
            ModBiblio($recordBiblio, $biblionumber, $frameworkcode);
        }
    }
}#addIndicesItemsFromHtml



#
# sub that tries to find authorities linked to the biblio, cogido de addbiblio.pl
# the sub :
#   - search in the authority DB for the same authid (in $9 of the biblio)
#   - search in the authority DB for the same 001 (in $3 of the biblio in UNIMARC)
#   - search in the authority DB for the same values (exactly) (in all subfields of the biblio)
# if the authority is found, the biblio is modified accordingly to be connected to the authority.
# if the authority is not found, it's added, and the biblio is then modified to be connected to the authority.
#

sub _BiblioAddAuthorities
{
    my ($self, $record, $frameworkcode) = @_;

    my $dbh = C4::Context->dbh;
    my $query = $dbh->prepare(qq|
        SELECT authtypecode,tagfield
        FROM marc_subfield_structure 
        WHERE frameworkcode=? 
        AND (authtypecode IS NOT NULL AND authtypecode<>\"\")|);
    $query->execute($frameworkcode);
    my ($countcreated,$countlinked);
    while (my $data = $query->fetchrow_hashref) {
        next unless (exists($self->{indexFields}->{$data->{tagfield}}));
        foreach my $field ($record->field($data->{tagfield})) {
            next if ($field->subfield('3') || $field->subfield('9'));
            # No authorities id in the tag.
            # Search if there is any authorities to link to.
            my $query = 'at='.$data->{authtypecode}.' ';
            map {$query.= ' and he,ext="'.$_->[1].'"' if ($_->[0]=~/[A-z]/)}  $field->subfields();
            my ($error, $results, $total_hits) = SimpleSearch( $query, undef, undef, [ "authorityserver" ] );
            # there is only 1 result 
            if ( $error ) {
                warn "BIBLIOADDSAUTHORITIES: $error";
                return (0,0) ;
            }
            if ( @{$results} == 1) {
                my $marcrecord = MARC::File::USMARC::decode($results->[0]);
                $field->add_subfields('9'=>$marcrecord->field('001')->data);
                $countlinked++;
            } elsif (@{$results} > 1) {
            #More than One result 
            #This can comes out of a lack of a subfield.
                $countlinked++;
            } else {
            #There are no results, build authority record, add it to Authorities, get authid and add it to 9
            ###NOTICE : This is only valid if a subfield is linked to one and only one authtypecode     
            ###NOTICE : This can be a problem. We should also look into other types and rejected forms.
                my $authtypedata = GetAuthType($data->{authtypecode});
                next unless $authtypedata;
                my $marcrecordauth = MARC::Record->new();
                if (C4::Context->preference('marcflavour') eq 'MARC21') {
                    $marcrecordauth->leader('     nz  a22     o  4500');
                    SetMarcUnicodeFlag($marcrecordauth, 'MARC21');
                }
                my $authfield = MARC::Field->new($authtypedata->{auth_tag_to_report},'','',"a"=>"".$field->subfield('a'));
                map { $authfield->add_subfields($_->[0]=>$_->[1]) if ($_->[0]=~/[A-z]/ && $_->[0] ne "a" )}  $field->subfields();
                $marcrecordauth->insert_fields_ordered($authfield);

                # bug 2317: ensure new authority knows it's using UTF-8; currently
                # only need to do this for MARC21, as MARC::Record->as_xml_record() handles
                # automatically for UNIMARC (by not transcoding)
                # FIXME: AddAuthority() instead should simply explicitly require that the MARC::Record
                # use UTF-8, but as of 2008-08-05, did not want to introduce that kind
                # of change to a core API just before the 3.0 release.

                if (C4::Context->preference('marcflavour') eq 'MARC21') {
                    $marcrecordauth->insert_fields_ordered(MARC::Field->new('667','','','a'=>"Machine generated authority record."));
                    my $cite = $record->author() . ", " .  $record->title_proper() . ", " . $record->publication_date() . " "; 
                    $cite =~ s/^[\s\,]*//;
                    $cite =~ s/[\s\,]*$//;
                    $cite = "Work cat.: (" . C4::Context->preference('MARCOrgCode') . ")". $record->subfield('999','c') . ": " . $cite;
                    $marcrecordauth->insert_fields_ordered(MARC::Field->new('670','','','a'=>$cite));
                }

                my $authid = AddAuthority($marcrecordauth,'',$data->{authtypecode});
                $countcreated++;
                if ($field->subfield('9')) {
                    $field->delete_subfield(code => '9');
                }
                $field->add_subfields('9'=>$authid);
            }
        }  
    }
    return ($countlinked,$countcreated);
}#_BiblioAddAuthorities






sub searchZebra
{
    my ($self, $server, $query, $offset, $max_results, $format) = @_;

    my ($results, $hits, $resultsQuery);
    my $Zconn = C4::Context->Zconn( $server, 0, 1, '', $format);
    use Data::Printer colored => 1;
    warn p($Zconn);
    eval {
        if ($Zconn && $Zconn->errcode() == 0) {
            $resultsQuery = $Zconn->search_pqf($query);
        }
    };
    if ($@) {
        if ($@->code() eq 13) {
        } else {
            my $error = $@->message() . " (" . $@->code() . ") " . $@->addinfo() . " " . $@->diagset();
            warn "ERROR: $error";
            return ($error, undef, undef);
        }
    }
    my $first_record = defined( $offset ) ? $offset+1 : 1;
    $hits = $resultsQuery->size();
    my $last_record = $hits;
    if ( defined $max_results && $offset + $max_results < $hits ) {
        $last_record  = $offset + $max_results;
    }
    for my $j ( $first_record..$last_record ) {
        my $record = $resultsQuery->record( $j-1 )->raw();
        push @{$results}, $record;
    }
    $resultsQuery->destroy();
    #$Zconn->destroy();

    return (undef, $results, $hits);
}#searchZebra


sub getShaIndice
{
    my ($self, $tipo, $data) = @_;

    return sha1_base64($tipo . '_' . $self->_parseContent2Xml($data));
}#getShaIndice


sub buildIndice
{
    my ($self, $id, $tipo, $data, $xml) = @_;

    $id = $self->getShaIndice($tipo, $data) unless ($id);
    my $strXml = '';
    $strXml = '<?xml version="1.0" encoding="UTF-8"?>' . chr(10) if ($xml);
    $strXml .= '<indice tipo="' . $tipo . '" id="' . $id . '">' . $self->_parseContent2Xml($data) . '</indice>';
    return $strXml;
}#buildIndice



sub processIndicesOnRecord
{
    my ($self, $marcrecord, $zoom_update, $op, $all_records, $biblionumber, $debug) = @_;
    
    my %differentData = ();
    my ($index, $tag, $code, $ind1, $ind2, $data, $dataBusc, $indicesXml, $Zconn);
    $indicesXml = '' unless ($zoom_update);
    print 'Procesando biblio: ' . $marcrecord->subfield('999', 'c') . chr(10) if ($debug);
    for $index (keys %{$self->{indexes}}) {
        for $tag (keys %{$self->{indexes}->{$index}}) {
            print "Tag: $tag\n" if ($debug);
            my @fields = $marcrecord->field($tag);
            if (@fields) {
                for my $field (@fields) {
                    if (exists($self->{indexes}->{$index}->{$tag}->{'ind1'})) {
                        my $ok = $self->_checkIndicatorOnIndex(1, $field, $self->{indexes}->{$index}->{$tag}->{'ind1'});
                        next unless ($ok);
                    }
                    if (exists($self->{indexes}->{$index}->{$tag}->{'ind2'})) {
                        my $ok = $self->_checkIndicatorOnIndex(2, $field, $self->{indexes}->{$index}->{$tag}->{'ind2'});
                        next unless ($ok);
                    }
                    if (exists($self->{indexes}->{$index}->{$tag}->{'subf'})) {
                        for $code (@{$self->{indexes}->{$index}->{$tag}->{'subf'}}) {
                            print "Code: $code\n" if ($debug);
                            if (defined($field->subfield($code))) {
                                my @subfields = $field->subfield($code);
                                next unless (@subfields);
                                for $data (@subfields) {
                                    print "Data: $data\n" if ($debug);
                                    unless (exists($differentData{$data})) {
                                        $differentData{$data} = 1;
                                        unless ($all_records) {
                                            $dataBusc = $data;
                                            $dataBusc =~ s/[\\]*"//g;
                                            my ($err, $results, $total) = $self->searchZebra('indicesserver', '@and @attr 1=tipo @attr 4=3 "' . $index . '" @attr 1=indice @attr 2=3 @attr 3=1 @attr 4=1 @attr 5=100 @attr 6=1 "' . $dataBusc . '"', 0, 1, 'xml');
                                            unless ($total) {
                                                if ($zoom_update) {
                                                    $indicesXml = $self->buildIndice('', $index, $data, 1);
                                                    if ($op eq 'update') {
                                                        $self->updateIndiceZebra('indicesserver', $indicesXml, 'recordInsert');
                                                    }
                                                    $indicesXml = '';
                                                } else {
                                                    $indicesXml .= $self->buildIndice('', $index, $data) . chr(10);
                                                }
                                            } elsif ($op eq 'delete') {
                                                $self->deleteIndice($index, $data, 0, $biblionumber);
                                            }
                                        } else {
                                            $indicesXml .= $self->buildIndice('', $index, $data) . chr(10);
                                        }
                                    }
                                }#for
                            }
                        }
                    }
                }#for
            }
        }
    }
    %differentData = ();
    %differentData = undef;
    return $indicesXml;
}#processIndicesOnRecord


sub _parseContent2Xml
{
    my ($self, $content) = @_;

    $content =~ s/\&(?![a-zA-Z#0-9]{1,4};)/&amp;/g;
    $content =~ s/</&lt;/g;
    $content =~ s/>/&gt;/g;
    return $content;
}#_parseContent2Xml


sub deleteIndice
{
    my ($self, $type, $data, $searchIndice, $biblionumber) = @_;
    
    my ($err, $results, $total);
    if ($searchIndice) {
        ($err, $results, $total) = $self->searchZebra('indicesserver', '@and @attr 1=tipo @attr 4=3 "' . $type . '" @attr 1=indice @attr 2=3 @attr 3=1 @attr 4=1 @attr 5=100 @attr 6=1 "' . $data . '"', 0, 1, 'xml');
    } else {
        $total = 1;
    }
    if ($total == 1) {
        my ($errB, $resultsB, $totalB) = $self->searchZebra('biblioserver', '@attr 1=' . $type . ' @attr 5=100 @attr 2=3 @attr 3=2 "' . $data . '"', 0, 1);
        if ($totalB <= 1) {
            if ($totalB ==1 && $biblionumber) {
                my $marcRecord;
                eval {
                    $marcRecord = MARC::Record->new_from_usmarc($resultsB->[0]);
                };
                unless ($@) {
                    return if (!$marcRecord || $biblionumber != $marcRecord->subfield('999', 'c'));
                }
            }
            my $indicesXml = $self->buildIndice('', $type, $data, 1);
            $self->updateIndiceZebra('indicesserver', $indicesXml, 'recordDelete');
        }
    }
}#deleteIndice


sub updateIndiceZebra
{
    my ($self, $server, $record, $op) = @_;

    my $message = '';
    my $Zconn = C4::Context->Zconn( $server, 0, 1, '', 'xml');
    if ($Zconn && $Zconn->errcode() == 0) {
        my $Zpackage = $Zconn->package();
        $Zpackage->option(action => $op);
        unless ($record =~ /<INDICES>/) {
            $record =~ s/(<\?xml\s+version\s*=\s*["']1\.0["']\s+encoding\s*=\s*["']UTF-8["']\?>\r*\n+)/$1<INDICES>/;
            $record .= '</INDICES>';
        }
        $Zpackage->option(record => $record);
        eval { $Zpackage->send("update") };
        if ($@ && $@->isa("ZOOM::Exception")) {
            $message = $@->message() . " (" . $@->code() . ") " . $@->addinfo() . " " . $@->diagset();
            $Zpackage->destroy();
            warn $message;
        }
        eval { $Zpackage->send('commit') };
        if ($@) {
            #$message = $@->message() . " (" . $@->code() . ") " . $@->addinfo() . " " . $@->diagset();
            warn $@;
        } else {
            #$Zconn->destroy();
            return 1;
        }
        #$Zconn->destroy();
    } else {
        warn 'ERROR: No se pudo conectar al servidor ' . $server . ' para actualizar.' . chr(10);
    }
    return undef;
}#updateIndiceZebra


sub getDataFromIndiceRecord
{
    my ($self, $record) = @_;
    
    my ($type, $data, $id);
    my $parser = XML::LibXML->new();
    my $dom = $parser->parse_string($record);
    if ($dom) {
        my $root = $dom->documentElement();
        if ($root->nodeName eq 'indice' && $root->hasChildNodes()) {
            $data = $root->firstChild->nodeValue;
            $type = $root->getAttribute('tipo');
            $id = $root->getAttribute('id');
        }
    }
    return ($type, $data, $id);
}#getDataFromIndiceRecord


sub searchOnIndices
{
    my ($self, $term, $indexes, $limit, $offset, $orderby, $operatorc) = @_;
    
    my $dataResults;
    my $query = '';
    $term =~ s/[\\]*"//g;
    unless ($indexes) {
        $query = '@attr 1=indice @attr 3=1 @attr 5=1 "' . $term . '"';
    } else {
        my $query_or = '';
        my $index;
        for $index (@$indexes) {
            $query_or .= '@or ';
            my $query_operator = '@attr 5=3';
            if ($operatorc) {
                if ($operatorc eq 'start') {
                    $query_operator = '@attr 3=1 @attr 5=1';
                } elsif ($operatorc eq 'is') {
                    $query_operator = '@attr 2=3 @attr 3=1 @attr 4=1 @attr 5=100 @attr 6=1';
                } elsif ($operatorc eq 'contains') {
                    $query_operator = '@attr 5=3';
                }
            } else {
                $query_operator .= '  @attr 4=6';
            }
            $query .= ' @and @attr 1=tipo @attr 4=3 "' . $index . '" @attr 1=indice ' . $query_operator . ' "' . $term . '" ';
        }
        $query = ($query_or)?substr($query_or, 0, -4) . ' ' . $query:'' . $query;
    }
    $query = '@or ' . $query . ' @attr 7=' . ((!$orderby || $orderby eq 'HeadingAsc')?1:2) . ' @attr 1=indice 0';
    warn "'indicesserver', $query, $offset, $limit, 'xml'";
    my ($err, $results, $hits) = $self->searchZebra('indicesserver', $query, $offset, $limit, 'xml');
    my $totalBiblios = 0;
    if ($results && @$results) {
        $dataResults = [];
        for my $record (@$results) {
            next unless($record);
            my ($type, $data, $idIndice) = $self->getDataFromIndiceRecord($record);
            if ($data && $type) {
                my ($count, $marcrecord) = $self->_countRecordsFromDataIndex($data, $indexes?$type:'');
                my $refHash = {'term' => $data, 'type' => $type, 'count' => $count, 'id' => $idIndice};
                if ($marcrecord) {
                    $refHash->{'firstBiblio'} = $marcrecord->title() . (($marcrecord->author())?' / ' . $marcrecord->author():'');
                    $refHash->{'year'} = $marcrecord->publication_date();
                    $refHash->{'biblionumber'} = ($count == 1 && $marcrecord->subfield('999', 'c'))?$marcrecord->subfield('999', 'c'):0;
                }
                push @$dataResults, $refHash;
                if ($offset == 0 && $hits <= $limit) {
                    $totalBiblios += $count;
                }
            }
        }
        if  ($hits > $limit) {
            $totalBiblios = $self->_countTotalRecordsFromDataIndex($term, $indexes);
        }
    }
    return ($hits, $dataResults, $totalBiblios);
}#searchOnIndices


sub _countTotalRecordsFromDataIndex
{
    my ($self, $term, $type) = @_;
    
    my $total = 0;
    my $query = ($type)?'@attr 1=' . $type->[0] . ' @attr 4=6 @attr 5=3 "' . $term . '"':'@attr 1=Indice @attr 4=6 @attr 5=3 "' . $term . '"';
    my $Zconn = C4::Context->Zconn('biblioserver', 0);
    eval {
        if ($Zconn && $Zconn->errcode() == 0) {
            my $results = $Zconn->search_pqf($query);
            $total = $results->size();
            $results->destroy();
        }
    };
    if ($@) {
        if ($@->code() eq 13) {
        } else {
            my $error = $@->message() . " (" . $@->code() . ") " . $@->addinfo() . " " . $@->diagset();
            warn "ERROR: $error";
        }
    }
    return $total;
}#_countTotalRecordsFromDataIndex


sub _countRecordsFromDataIndex
{
    my ($self, $term, $type) = @_;
    
    my ($marcrecord, $results);
    my $total = 0;
    my $trunc = '5=100';
    if (length($term) > 200) {
        $term = substr($term, 0, 200);
        $trunc = '5=1';
    }
    $term =~ s/[\\]*"//g;
    my $query = ($type)?'@attr 1=' . $type . ' @attr 2=3 @attr 3=2 @attr 4=1 @attr 6=3 @attr ' . $trunc . ' "' . $term . '"':'@attr 1=Indice @attr 2=3 @attr 3=2 @attr 4=1 @attr 6=3 @attr ' . $trunc . ' "' . $term . '"';
    my $Zconn = C4::Context->Zconn('biblioserver', 0);
    eval {
        if ($Zconn && $Zconn->errcode() == 0) {
            $results = $Zconn->search_pqf($query);
            $total = $results->size();
        }
    };
    if ($@) {
        if ($@->code() eq 13) {
        } else {
            my $error = $@->message() . " (" . $@->code() . ") " . $@->addinfo() . " " . $@->diagset();
            warn "ERROR: $error";
        }
    }
    if ($total) {
        eval {
            my $record = $results->record(0)->raw();
            $marcrecord = MARC::Record->new_from_usmarc($record);
            $results->destroy();
        };
    }
    return ($total, $marcrecord);
}#_countRecordsFromDataIndex


sub searchBibliosFromDataIndex
{
    my ($self, $term, $indexes, $offset, $results_per_page, $branches, $sort_by) = @_;

    $term =~ s/[\\]*"//g;
    my $type = ($indexes && @$indexes)?$indexes->[0]:'Indice';
    my ($err, $results_hashref, $facets) = getRecords('@attr 1=' . $type . ' @attr 5=100 @attr 2=3 @attr 3=2 "' . $term . '"', '', $sort_by, ['biblioserver'], $results_per_page, $offset, undef, $branches, undef, 'pqf', undef);
    return ($err, $results_hashref, $facets);
}#searchBibliosFromDataIndex

sub _checkIndicatorOnIndex
{
    my ($self, $ind, $field, $indicators) = @_;
    
    my $ok = 0;
    my $indData = $field->indicator($ind);
    for (@$indicators) {
        if ($_ == $indData) {
            $ok = 1;
            last;
        }
    }
    return $ok;
}#_checkIndicatorOnIndex


sub getIndiceFromItem
{
    my ($self, $marcrecord, $itemnumber, $indice, $additionalSubfields) = @_;
    
    my ($tag, $code, $ind1, $ind2, $data, $value);
    my @dataIndices = ();
    my $indices = $self->{indexes}->{$indice};
    for $tag (keys %$indices) {
        my $rlin;
        my @fields = $marcrecord->field($tag);
        if (@fields) {
            for my $field (@fields) {
                my @codes = ();
                my %codes;
                if (exists($indices->{$tag}->{'ind1'})) {
                    my $ok = $self->_checkIndicatorOnIndex(1, $field, $indices->{$tag}->{'ind1'});
                    next unless ($ok);
                }
                if (exists($indices->{$tag}->{'ind2'})) {
                    my $ok = $self->_checkIndicatorOnIndex(2, $field, $indices->{$tag}->{'ind2'});
                    next unless ($ok);
                }
                next if (!$field->subfield('0') || $field->subfield('0') != $itemnumber);
                if (exists($indices->{$tag}->{'subf'})) {
                    for $code (@{$indices->{$tag}->{'subf'}}) {
                        if (defined($field->subfield($code))) {
                            my @subfields = $field->subfield($code);
                            next unless (@subfields);
                            for $data (@subfields) {
                                next unless ($data);
                                $codes{$code} = '' unless(exists($codes{$code}));
                                $codes{$code} .= $data . ' ';
                            }
                        }
                        $value = $codes{'a'} if ($code eq 'a' && !$value);
                    }
                }
                if ($additionalSubfields && @$additionalSubfields) {
                    for $code (@$additionalSubfields) {
                        my @subfields = $field->subfield($code);
                        next unless (@subfields);
                        for $data (@subfields) {
                            next unless ($data);
                            $codes{$code} = '' unless(exists($codes{$code}));
                            $codes{$code} .= $data . ' ';
                        }
                        $value = $codes{'a'} if ($code eq 'a' && !$value);
                    }
                }
                # Xercode
                #$rlin = $field->subfield('9') if (!$rlin && $field->subfield('9'));
                $rlin = $field->subfield('9') if ($field->subfield('9'));
                if ($rlin || $value) {
                    map { push @codes, {code => $_, value => $codes{$_}}; } sort keys %codes;
                    push @dataIndices, {tag => $tag, codes => \@codes, rlin => $rlin, value => $value};
                }
                $value = '';
            }
        }
    }
    my $dataIndices;
    $dataIndices = \@dataIndices if (@dataIndices);
    return $dataIndices;
}#getIndiceFromItem



1;
