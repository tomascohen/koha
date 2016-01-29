#!/usr/bin/perl

# Copyright 2000-2002 Katipo Communications
# Copyright 2010 BibLibre
# Copyright 2011 KohaAloha, NZ
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
use warnings;

use CGI;
use C4::Auth qw(:DEFAULT get_session);
use C4::Branch;
use C4::Koha;
use C4::Serials;    #uses getsubscriptionfrom biblionumber
use C4::Output;
use C4::Biblio;
use C4::Items;
use C4::Circulation;
use C4::Tags qw(get_tags);
use C4::XISBN qw(get_xisbns get_biblionumber_from_isbn);
use C4::External::Amazon;
use C4::External::Syndetics qw(get_syndetics_index get_syndetics_summary get_syndetics_toc get_syndetics_excerpt get_syndetics_reviews get_syndetics_anotes );
use C4::Review;
use C4::Ratings;
use C4::Members;
use C4::VirtualShelves;
use C4::XSLT;
use C4::ShelfBrowser;
use C4::Reserves;
use C4::Charset;
use C4::IndicesItems;
use MARC::Record;
use MARC::Field;
use List::MoreUtils qw/any none/;
use C4::Images;
use Koha::DateUtils;

BEGIN {
	if (C4::Context->preference('BakerTaylorEnabled')) {
		require C4::External::BakerTaylor;
		import C4::External::BakerTaylor qw(&image_url &link_url);
	}
}

my $query = new CGI;
my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-detail.tmpl",
        query           => $query,
        type            => "opac",
        authnotrequired => ( C4::Context->preference("OpacPublic") ? 1 : 0 ),
        flagsrequired   => { borrow => 1 },
    }
);

my $biblionumber = $query->param('biblionumber') || $query->param('bib');
$biblionumber = int($biblionumber);

my $record       = GetMarcBiblio($biblionumber, 1);
if ( ! $record ) {
    print $query->redirect("/cgi-bin/koha/errors/404.pl"); # escape early
    exit;
}
$template->param( biblionumber => $biblionumber );

# get biblionumbers stored in the cart
my @cart_list;

if($query->cookie("bib_list")){
    my $cart_list = $query->cookie("bib_list");
    @cart_list = split(/\//, $cart_list);
    if ( grep {$_ eq $biblionumber} @cart_list) {
        $template->param( incart => 1 );
    }
}


SetUTF8Flag($record);
my $marcflavour      = C4::Context->preference("marcflavour");
my $ean = GetNormalizedEAN( $record, $marcflavour );

# XSLT processing of some stuff
if (C4::Context->preference("OPACXSLTDetailsDisplay") ) {
    $template->param( 'XSLTBloc' => XSLTParse4Display($biblionumber, $record, "OPACXSLTDetailsDisplay" ) );
}

my $OpacBrowseResults = C4::Context->preference("OpacBrowseResults");
$template->{VARS}->{'OpacBrowseResults'} = $OpacBrowseResults;

# We look for the busc param to build the simple paging from the search
if ($OpacBrowseResults) {
my $session = get_session($query->cookie("CGISESSID"));
my %paging = (previous => {}, next => {});
if ($session->param('busc')) {
    use C4::Search;

    # Rebuild the string to store on session
    sub rebuildBuscParam
    {
        my $arrParamsBusc = shift;

        my $pasarParams = '';
        my $j = 0;
        for (keys %$arrParamsBusc) {
            if ($_ =~ /^(?:query|listBiblios|newlistBiblios|query_type|simple_query|total|offset|offsetSearch|next|previous|count|expand|scan)/) {
                if (defined($arrParamsBusc->{$_})) {
                    $pasarParams .= '&amp;' if ($j);
                    $pasarParams .= $_ . '=' . $arrParamsBusc->{$_};
                    $j++;
                }
            } else {
                for my $value (@{$arrParamsBusc->{$_}}) {
                    $pasarParams .= '&amp;' if ($j);
                    $pasarParams .= $_ . '=' . $value;
                    $j++;
                }
            }
        }
        return $pasarParams;
    }#rebuildBuscParam

    # Search given the current values from the busc param
    sub searchAgain
    {
        my ($arrParamsBusc, $offset, $results_per_page) = @_;

        my $expanded_facet = $arrParamsBusc->{'expand'};
        my $branches = GetBranches();
        my @servers;
        @servers = @{$arrParamsBusc->{'server'}} if $arrParamsBusc->{'server'};
        @servers = ("biblioserver") unless (@servers);

        my ($default_sort_by, @sort_by);
        $default_sort_by = C4::Context->preference('OPACdefaultSortField')."_".C4::Context->preference('OPACdefaultSortOrder') if (C4::Context->preference('OPACdefaultSortField') && C4::Context->preference('OPACdefaultSortOrder'));
        @sort_by = @{$arrParamsBusc->{'sort_by'}} if $arrParamsBusc->{'sort_by'};
        $sort_by[0] = $default_sort_by if !$sort_by[0] && defined($default_sort_by);
        my ($error, $results_hashref, $facets);
        eval {
            ($error, $results_hashref, $facets) = getRecords($arrParamsBusc->{'query'},$arrParamsBusc->{'simple_query'},\@sort_by,\@servers,$results_per_page,$offset,$expanded_facet,$branches,$arrParamsBusc->{'query_type'},$arrParamsBusc->{'scan'});
        };
        my $hits;
        my @newresults;
        for (my $i=0;$i<@servers;$i++) {
            my $server = $servers[$i];
            $hits = $results_hashref->{$server}->{"hits"};
            @newresults = searchResults('opac', '', $hits, $results_per_page, $offset, $arrParamsBusc->{'scan'}, $results_hashref->{$server}->{"RECORDS"});
        }
        return \@newresults;
    }#searchAgain

    # Build the current list of biblionumbers in this search
    sub buildListBiblios
    {
        my ($newresultsRef, $results_per_page) = @_;

        my $listBiblios = '';
        my $j = 0;
        foreach (@$newresultsRef) {
            my $bibnum = ($_->{biblionumber})?$_->{biblionumber}:0;
            $listBiblios .= $bibnum . ',';
            $j++;
            last if ($j == $results_per_page);
        }
        chop $listBiblios if ($listBiblios =~ /,$/);
        return $listBiblios;
    }#buildListBiblios

    my $busc = $session->param("busc");
    my @arrBusc = split(/\&(?:amp;)?/, $busc);
    my ($key, $value);
    my %arrParamsBusc = ();
    for (@arrBusc) {
        ($key, $value) = split(/=/, $_, 2);
        if ($key =~ /^(?:query|listBiblios|newlistBiblios|query_type|simple_query|next|previous|total|offset|offsetSearch|count|expand|scan)/) {
            $arrParamsBusc{$key} = $value;
        } else {
            unless (exists($arrParamsBusc{$key})) {
                $arrParamsBusc{$key} = [];
            }
            push @{$arrParamsBusc{$key}}, $value;
        }
    }
    my $searchAgain = 0;
    my $count = C4::Context->preference('OPACnumSearchResults') || 20;
    my $results_per_page = ($arrParamsBusc{'count'} && $arrParamsBusc{'count'} =~ /^[0-9]+?/)?$arrParamsBusc{'count'}:$count;
    $arrParamsBusc{'count'} = $results_per_page;
    my $offset = ($arrParamsBusc{'offset'} && $arrParamsBusc{'offset'} =~ /^[0-9]+?/)?$arrParamsBusc{'offset'}:0;
    # The value OPACnumSearchResults has changed and the search has to be rebuild
    if ($count != $results_per_page) {
        if (exists($arrParamsBusc{'listBiblios'}) && $arrParamsBusc{'listBiblios'} =~ /^[0-9]+(?:,[0-9]+)*$/) {
            my $indexBiblio = 0;
            my @arrBibliosAux = split(',', $arrParamsBusc{'listBiblios'});
            for (@arrBibliosAux) {
                last if ($_ == $biblionumber);
                $indexBiblio++;
            }
            $indexBiblio += $offset;
            $offset = int($indexBiblio / $count) * $count;
            $arrParamsBusc{'offset'} = $offset;
        }
        $arrParamsBusc{'count'} = $count;
        $results_per_page = $count;
        my $newresultsRef = searchAgain(\%arrParamsBusc, $offset, $results_per_page);
        $arrParamsBusc{'listBiblios'} = buildListBiblios($newresultsRef, $results_per_page);
        delete $arrParamsBusc{'previous'} if (exists($arrParamsBusc{'previous'}));
        delete $arrParamsBusc{'next'} if (exists($arrParamsBusc{'next'}));
        delete $arrParamsBusc{'offsetSearch'} if (exists($arrParamsBusc{'offsetSearch'}));
        delete $arrParamsBusc{'newlistBiblios'} if (exists($arrParamsBusc{'newlistBiblios'}));
        my $newbusc = rebuildBuscParam(\%arrParamsBusc);
        $session->param("busc" => $newbusc);
        @arrBusc = split(/\&(?:amp;)?/, $newbusc);
    } else {
        my $modifyListBiblios = 0;
        # We come from a previous click
        if (exists($arrParamsBusc{'previous'})) {
            $modifyListBiblios = 1 if ($biblionumber == $arrParamsBusc{'previous'});
            delete $arrParamsBusc{'previous'};
        } elsif (exists($arrParamsBusc{'next'})) { # We come from a next click
            $modifyListBiblios = 2 if ($biblionumber == $arrParamsBusc{'next'});
            delete $arrParamsBusc{'next'};
        }
        if ($modifyListBiblios) {
            if (exists($arrParamsBusc{'newlistBiblios'})) {
                my $listBibliosAux = $arrParamsBusc{'listBiblios'};
                $arrParamsBusc{'listBiblios'} = $arrParamsBusc{'newlistBiblios'};
                my @arrAux = split(',', $listBibliosAux);
                $arrParamsBusc{'newlistBiblios'} = $listBibliosAux;
                if ($modifyListBiblios == 1) {
                    $arrParamsBusc{'next'} = $arrAux[0];
                    $paging{'next'}->{biblionumber} = $arrAux[0];
                }else {
                    $arrParamsBusc{'previous'} = $arrAux[$#arrAux];
                    $paging{'previous'}->{biblionumber} = $arrAux[$#arrAux];
                }
            } else {
                delete $arrParamsBusc{'listBiblios'};
            }
            my $offsetAux = $arrParamsBusc{'offset'};
            $arrParamsBusc{'offset'} = $arrParamsBusc{'offsetSearch'};
            $arrParamsBusc{'offsetSearch'} = $offsetAux;
            $offset = $arrParamsBusc{'offset'};
            my $newbusc = rebuildBuscParam(\%arrParamsBusc);
            $session->param("busc" => $newbusc);
            @arrBusc = split(/\&(?:amp;)?/, $newbusc);
        }
    }
    my $buscParam = '';
    my $j = 0;
    # Rebuild the query for the button "back to results"
    for (@arrBusc) {
        unless ($_ =~ /^(?:query|listBiblios|newlistBiblios|query_type|simple_query|next|previous|total|count|offsetSearch)/) {
            $buscParam .= '&amp;' unless ($j == 0);
            $buscParam .= $_;
            $j++;
        }
    }
    $template->param('busc' => $buscParam);
    my $offsetSearch;
    my @arrBiblios;
    # We are inside the list of biblios and we don't have to search
    if (exists($arrParamsBusc{'listBiblios'}) && $arrParamsBusc{'listBiblios'} =~ /^[0-9]+(?:,[0-9]+)*$/) {
        @arrBiblios = split(',', $arrParamsBusc{'listBiblios'});
        if (@arrBiblios) {
            # We are at the first item of the list
            if ($arrBiblios[0] == $biblionumber) {
                if (@arrBiblios > 1) {
                    for (my $j = 1; $j < @arrBiblios; $j++) {
                        next unless ($arrBiblios[$j]);
                        $paging{'next'}->{biblionumber} = $arrBiblios[$j];
                        last;
                    }
                }
                # search again if we are not at the first searching list
                if ($offset && !$arrParamsBusc{'previous'}) {
                    $searchAgain = 1;
                    $offsetSearch = $offset - $results_per_page;
                }
            # we are at the last item of the list
            } elsif ($arrBiblios[$#arrBiblios] == $biblionumber) {
                for (my $j = $#arrBiblios - 1; $j >= 0; $j--) {
                    next unless ($arrBiblios[$j]);
                    $paging{'previous'}->{biblionumber} = $arrBiblios[$j];
                    last;
                }
                if (!$offset) {
                    # search again if we are at the first list and there is more results
                    $searchAgain = 1 if (!$arrParamsBusc{'next'} && $arrParamsBusc{'total'} != @arrBiblios);
                } else {
                    # search again if we aren't at the first list and there is more results
                    $searchAgain = 1 if (!$arrParamsBusc{'next'} && $arrParamsBusc{'total'} > ($offset + @arrBiblios));
                }
                $offsetSearch = $offset + $results_per_page if ($searchAgain);
            } else {
                for (my $j = 1; $j < $#arrBiblios; $j++) {
                    if ($arrBiblios[$j] == $biblionumber) {
                        for (my $z = $j - 1; $z >= 0; $z--) {
                            next unless ($arrBiblios[$z]);
                            $paging{'previous'}->{biblionumber} = $arrBiblios[$z];
                            last;
                        }
                        for (my $z = $j + 1; $z < @arrBiblios; $z++) {
                            next unless ($arrBiblios[$z]);
                            $paging{'next'}->{biblionumber} = $arrBiblios[$z];
                            last;
                        }
                        last;
                    }
                }
            }
        }
        $offsetSearch = 0 if (defined($offsetSearch) && $offsetSearch < 0);
    }
    if ($searchAgain) {
        my $newresultsRef = searchAgain(\%arrParamsBusc, $offsetSearch, $results_per_page);
        my @newresults = @$newresultsRef;
        # build the new listBiblios
        my $listBiblios = buildListBiblios(\@newresults, $results_per_page);
        unless (exists($arrParamsBusc{'listBiblios'})) {
            $arrParamsBusc{'listBiblios'} = $listBiblios;
            @arrBiblios = split(',', $arrParamsBusc{'listBiblios'});
        } else {
            $arrParamsBusc{'newlistBiblios'} = $listBiblios;
        }
        # From the new list we build again the next and previous result
        if (@arrBiblios) {
            if ($arrBiblios[0] == $biblionumber) {
                for (my $j = $#newresults; $j >= 0; $j--) {
                    next unless ($newresults[$j]);
                    $paging{'previous'}->{biblionumber} = $newresults[$j]->{biblionumber};
                    $arrParamsBusc{'previous'} = $paging{'previous'}->{biblionumber};
                    $arrParamsBusc{'offsetSearch'} = $offsetSearch;
                   last;
                }
            } elsif ($arrBiblios[$#arrBiblios] == $biblionumber) {
                for (my $j = 0; $j < @newresults; $j++) {
                    next unless ($newresults[$j]);
                    $paging{'next'}->{biblionumber} = $newresults[$j]->{biblionumber};
                    $arrParamsBusc{'next'} = $paging{'next'}->{biblionumber};
                    $arrParamsBusc{'offsetSearch'} = $offsetSearch;
                    last;
                }
            }
        }
        # build new busc param
        my $newbusc = rebuildBuscParam(\%arrParamsBusc);
        $session->param("busc" => $newbusc);
    }
    my ($previous, $next, $dataBiblioPaging);
    # Previous biblio
    if ($paging{'previous'}->{biblionumber}) {
        $previous = 'opac-detail.pl?biblionumber=' . $paging{'previous'}->{biblionumber};
        $dataBiblioPaging = GetBiblioData($paging{'previous'}->{biblionumber});
        $template->param('previousTitle' => $dataBiblioPaging->{'title'}) if ($dataBiblioPaging);
    }
    # Next biblio
    if ($paging{'next'}->{biblionumber}) {
        $next = 'opac-detail.pl?biblionumber=' . $paging{'next'}->{biblionumber};
        $dataBiblioPaging = GetBiblioData($paging{'next'}->{biblionumber});
        $template->param('nextTitle' => $dataBiblioPaging->{'title'}) if ($dataBiblioPaging);
    }
    $template->param('previous' => $previous, 'next' => $next);
    # Partial list of biblio results
    my @listResults;
    for (my $j = 0; $j < @arrBiblios; $j++) {
        next unless ($arrBiblios[$j]);
        $dataBiblioPaging = GetBiblioData($arrBiblios[$j]) if ($arrBiblios[$j] != $biblionumber);
        push @listResults, {index => $j + 1 + $offset, biblionumber => $arrBiblios[$j], title => ($arrBiblios[$j] == $biblionumber)?'':$dataBiblioPaging->{title}, author => ($arrBiblios[$j] != $biblionumber && $dataBiblioPaging->{author})?$dataBiblioPaging->{author}:'', url => ($arrBiblios[$j] == $biblionumber)?'':'opac-detail.pl?biblionumber=' . $arrBiblios[$j]};
    }
    $template->param('listResults' => \@listResults) if (@listResults);
    $template->param('indexPag' => 1 + $offset, 'totalPag' => $arrParamsBusc{'total'}, 'indexPagEnd' => scalar(@arrBiblios) + $offset);
}
}



$template->param( 'AllowOnShelfHolds' => C4::Context->preference('AllowOnShelfHolds') );
$template->param( 'ItemsIssued' => CountItemsIssued( $biblionumber ) );

my $recordNoItems       = GetMarcBiblio($biblionumber);

$template->param('OPACShowCheckoutName' => C4::Context->preference("OPACShowCheckoutName") );
$template->param('OPACShowBarcode' => C4::Context->preference("OPACShowBarcode") );
# change back when ive fixed request.pl
my @all_items = GetItemsInfo( $biblionumber );

# adding items linked via host biblios

my $analyticfield = '773';
if ($marcflavour eq 'MARC21' || $marcflavour eq 'NORMARC'){
    $analyticfield = '773';
} elsif ($marcflavour eq 'UNIMARC') {
    $analyticfield = '461';
}
foreach my $hostfield ( $record->field($analyticfield)) {
    my $hostbiblionumber = $hostfield->subfield("0");
    my $linkeditemnumber = $hostfield->subfield("9");
    my @hostitemInfos = GetItemsInfo($hostbiblionumber);
    foreach my $hostitemInfo (@hostitemInfos){
        if ($hostitemInfo->{itemnumber} eq $linkeditemnumber){
            push(@all_items, $hostitemInfo);
        }
    }
}

my @items;

# Getting items to be hidden
my @hiddenitems = GetHiddenItemnumbers(@all_items);

# Are there items to hide?
my $hideitems;
$hideitems = 1 if C4::Context->preference('hidelostitems') or scalar(@hiddenitems) > 0;

# Hide items
if ($hideitems) {
    for my $itm (@all_items) {
	if  ( C4::Context->preference('hidelostitems') ) {
	    push @items, $itm unless $itm->{itemlost} or any { $itm->{'itemnumber'} eq $_ } @hiddenitems;
	} else {
	    push @items, $itm unless any { $itm->{'itemnumber'} eq $_ } @hiddenitems;
    }
}
} else {
    # Or not
    @items = @all_items;
}

my $dat = &GetBiblioData($biblionumber);

my $indicesObj = new C4::IndicesItems();

my $itemtypes = GetItemTypes();
# imageurl:
my $itemtype = $dat->{'itemtype'};
if ( $itemtype ) {
    $dat->{'imageurl'}    = getitemtypeimagelocation( 'opac', $itemtypes->{$itemtype}->{'imageurl'} );
    $dat->{'description'} = $itemtypes->{$itemtype}->{'description'};
}
my $shelflocations =GetKohaAuthorisedValues('items.location',$dat->{'frameworkcode'}, 'opac');
my $collections =  GetKohaAuthorisedValues('items.ccode',$dat->{'frameworkcode'}, 'opac');
my $copynumbers = GetKohaAuthorisedValues('items.copynumber',$dat->{'frameworkcode'}, 'opac');

#coping with subscriptions
my $subscriptionsnumber = CountSubscriptionFromBiblionumber($biblionumber);
my @subscriptions       = GetSubscriptions($dat->{'title'}, $dat->{'issn'}, $ean, $biblionumber );

my @subs;
$dat->{'serial'}=1 if $subscriptionsnumber;
foreach my $subscription (@subscriptions) {
    my $serials_to_display;
    my %cell;
    $cell{subscriptionid}    = $subscription->{subscriptionid};
    $cell{subscriptionnotes} = $subscription->{notes};
    $cell{missinglist}       = $subscription->{missinglist};
    $cell{opacnote}          = $subscription->{opacnote};
    $cell{histstartdate}     = $subscription->{histstartdate};
    $cell{histenddate}       = $subscription->{histenddate};
    $cell{branchcode}        = $subscription->{branchcode};
    $cell{branchname}        = GetBranchName($subscription->{branchcode});
    $cell{hasalert}          = $subscription->{hasalert};
    #get the three latest serials.
    $serials_to_display = $subscription->{opacdisplaycount};
    $serials_to_display = C4::Context->preference('OPACSerialIssueDisplayCount') unless $serials_to_display;
	$cell{opacdisplaycount} = $serials_to_display;
    $cell{latestserials} =
      GetLatestSerials( $subscription->{subscriptionid}, $serials_to_display );
    push @subs, \%cell;
}

$dat->{'count'} = scalar(@items);

# If there is a lot of items, and the user has not decided
# to view them all yet, we first warn him
# TODO: The limit of 50 could be a syspref
my $viewallitems = $query->param('viewallitems');
if ($dat->{'count'} >= 50 && !$viewallitems) {
    $template->param('lotsofitems' => 1);
}

my $biblio_authorised_value_images = C4::Items::get_authorised_value_images( C4::Biblio::get_biblio_authorised_values( $biblionumber, $record ) );

my (%item_reserves, %priority);
my ($show_holds_count, $show_priority);
for ( C4::Context->preference("OPACShowHoldQueueDetails") ) {
    m/holds/o and $show_holds_count = 1;
    m/priority/ and $show_priority = 1;
}
my $has_hold;
if ( $show_holds_count || $show_priority) {
    my ($reserve_count,$reserves) = GetReservesFromBiblionumber($biblionumber);
    $template->param( holds_count  => $reserve_count ) if $show_holds_count;
    foreach (@$reserves) {
        $item_reserves{ $_->{itemnumber} }++ if $_->{itemnumber};
        if ($show_priority && $_->{borrowernumber} == $borrowernumber) {
            $has_hold = 1;
            $_->{itemnumber}
                ? ($priority{ $_->{itemnumber} } = $_->{priority})
                : ($template->param( priority => $_->{priority} ));
        }
    }
}
$template->param( show_priority => $has_hold ) ;

my $norequests = 1;
my $branches = GetBranches();
my %itemfields;
for my $itm (@items) {
    $itm->{holds_count} = $item_reserves{ $itm->{itemnumber} };
    $itm->{priority} = $priority{ $itm->{itemnumber} };
    $norequests = 0
       if ( (not $itm->{'wthdrawn'} )
         && (not $itm->{'itemlost'} )
         && ($itm->{'itemnotforloan'}<0 || not $itm->{'itemnotforloan'} )
		 && (not $itemtypes->{$itm->{'itype'}}->{notforloan} )
         && ($itm->{'itemnumber'} ) );

    # get collection code description, too
    my $ccode = $itm->{'ccode'};
    $itm->{'ccode'} = $collections->{$ccode} if ( defined($collections) && exists( $collections->{$ccode} ) );
    my $copynumber = $itm->{'copynumber'};
    $itm->{'copynumber'} = $copynumbers->{$copynumber} if ( defined($copynumbers) && defined($copynumber) && exists( $copynumbers->{$copynumber} ) );
    if ( defined $itm->{'location'} || defined $itm->{'homebranch'} || defined $itm->{'holdingbranch'}) {
        if (defined $itm->{'location'}) {
            $itm->{'location_description'} = $shelflocations->{ $itm->{'location'} };
        } elsif (defined $itm->{'homebranch'}) {
            $itm->{'location_description'} = GetBranchName($itm->{'homebranch'})
        } else {
            $itm->{'location_description'} = GetBranchName($itm->{'holdingbranch'});
        }
    }
    if (exists $itm->{itype} && defined($itm->{itype}) && exists $itemtypes->{ $itm->{itype} }) {
        $itm->{'imageurl'}    = getitemtypeimagelocation( 'opac', $itemtypes->{ $itm->{itype} }->{'imageurl'} );
        $itm->{'description'} = $itemtypes->{ $itm->{itype} }->{'description'};
    }
    foreach (qw(ccode enumchron copynumber itemnotes uri)) {
        $itemfields{$_} = 1 if ($itm->{$_});
    }

     # walk through the item-level authorised values and populate some images
     my $item_authorised_value_images = C4::Items::get_authorised_value_images( C4::Items::get_item_authorised_values( $itm->{'itemnumber'} ) );
     # warn( Data::Dumper->Dump( [ $item_authorised_value_images ], [ 'item_authorised_value_images' ] ) );

     if ( $itm->{'itemlost'} ) {
         my $lostimageinfo = List::Util::first { $_->{'category'} eq 'LOST' } @$item_authorised_value_images;
         $itm->{'lostimageurl'}   = $lostimageinfo->{ 'imageurl' };
         $itm->{'lostimagelabel'} = $lostimageinfo->{ 'label' };
     }
     my ($reserve_status) = C4::Reserves::CheckReserves($itm->{itemnumber});
      if( $reserve_status eq "Waiting"){ $itm->{'waiting'} = 1; }
      if( $reserve_status eq "Reserved"){ $itm->{'onhold'} = 1; }
    
     my ( $transfertwhen, $transfertfrom, $transfertto ) = GetTransfers($itm->{itemnumber});
     if ( defined( $transfertwhen ) && $transfertwhen ne '' ) {
        $itm->{transfertwhen} = $transfertwhen;
        $itm->{transfertfrom} = $branches->{$transfertfrom}{branchname};
        $itm->{transfertto}   = $branches->{$transfertto}{branchname};
     }

    # Modificación MASmedios --> obtener el campo Posesor 901*
    $itm->{posesor} = $indicesObj->getIndiceFromItem($record, $itm->{itemnumber}, 'Posesor', ['b', 'c']);

    # Modificación MASmedios --> obtener el campo Encuadernador 902*
    $itm->{encuadernador} = $indicesObj->getIndiceFromItem($record, $itm->{itemnumber}, 'Encuadernador', ['b', 'c']);

    # Modificación MASmedios -->
=cut
    if ($recordNoItems && $recordNoItems->field('952')) {
        for my $field ( $recordNoItems->field('952') ) {
            if($field->subfield('9') eq $itm->{itemnumber}){
                $itm->{datosejemplar} = $itm->{paidfor} || $field->subfield('k');
                $itm->{itemcallnumber} = $field->subfield('o') unless($itm->{itemcallnumber});
                $itm->{enumchron} = $field->subfield('h') unless($itm->{enumchron});
                last;
            }
        }
    } 
=cut
# TEMPORAL XERCODE Mantis 0000306
    if ($record && $record->field('952')) {
        for my $field ( $record->field('952') ) {
            if($field->subfield('9') eq $itm->{itemnumber}){
                $itm->{datosejemplar} = $itm->{paidfor} || $field->subfield('k');
                $itm->{itemcallnumber} = $field->subfield('o') unless($itm->{itemcallnumber});
                $itm->{enumchron} = $field->subfield('h') unless($itm->{enumchron});
                last;
            }
        }
    } elsif ($itm->{paidfor}) {
        $itm->{datosejemplar} = $itm->{paidfor};
    }
}

## get notes and subjects from MARC record
my $dbh              = C4::Context->dbh;
my $marcnotesarray   = GetMarcNotes   ($record,$marcflavour);
my $marcisbnsarray   = GetMarcISBN    ($record,$marcflavour);
my $marcauthorsarray = GetMarcAuthors ($record,$marcflavour);
my $marcsubjctsarray = GetMarcSubjects($record,$marcflavour);
my $marcseriesarray  = GetMarcSeries  ($record,$marcflavour);
my $marcurlsarray    = GetMarcUrls    ($record,$marcflavour);
my $marchostsarray  = GetMarcHosts($record,$marcflavour);
my $subtitle         = GetRecordValue('subtitle', $record, GetFrameworkCode($biblionumber));

    $template->param(
                     MARCNOTES               => $marcnotesarray,
                     MARCSUBJCTS             => $marcsubjctsarray,
                     MARCAUTHORS             => $marcauthorsarray,
                     MARCSERIES              => $marcseriesarray,
                     MARCURLS                => $marcurlsarray,
                     MARCISBNS               => $marcisbnsarray,
                     MARCHOSTS               => $marchostsarray,
                     norequests              => $norequests,
                     RequestOnOpac           => C4::Context->preference("RequestOnOpac"),
                     itemdata_ccode          => $itemfields{ccode},
                     itemdata_enumchron      => $itemfields{enumchron},
                     itemdata_uri            => $itemfields{uri},
                     itemdata_copynumber     => $itemfields{copynumber},
                     itemdata_itemnotes          => $itemfields{itemnotes},
                     authorised_value_images => $biblio_authorised_value_images,
                     subtitle                => $subtitle,
                     OpacStarRatings         => C4::Context->preference("OpacStarRatings"),
    );

if (C4::Context->preference("AlternateHoldingsField") && scalar @items == 0) {
    my $fieldspec = C4::Context->preference("AlternateHoldingsField");
    my $subfields = substr $fieldspec, 3;
    my $holdingsep = C4::Context->preference("AlternateHoldingsSeparator") || ' ';
    my @alternateholdingsinfo = ();
    my @holdingsfields = $record->field(substr $fieldspec, 0, 3);

    for my $field (@holdingsfields) {
        my %holding = ( holding => '' );
        my $havesubfield = 0;
        for my $subfield ($field->subfields()) {
            if ((index $subfields, $$subfield[0]) >= 0) {
                $holding{'holding'} .= $holdingsep if (length $holding{'holding'} > 0);
                $holding{'holding'} .= $$subfield[1];
                $havesubfield++;
            }
        }
        if ($havesubfield) {
            push(@alternateholdingsinfo, \%holding);
        }
    }

    $template->param(
        ALTERNATEHOLDINGS   => \@alternateholdingsinfo,
        );
}


# Modificación MASmedios --> recoger los subcampos no numéricos de un campo determinado
sub getDataNaNFromField
{
    my ($record, $tag, $multiple, $blank, $type) = @_;
    
    my $data;
    if ($record && $record->field($tag)) {
        $blank = '<br/>' unless ($blank);
        $type = '' unless ($type);
        $data = [] if ($type eq 'array');
        foreach my $field ( $record->field($tag) ) {
            my @subfields = $field->subfields();
            my @subfieldsData = ();
            foreach my $subfield (@subfields) {
                if($subfield->[0] =~ /\D/ ) {
                    if ($type eq 'array') {
                        push @subfieldsData, {'code' => $subfield->[0], 'value' => $subfield->[1]};
                    } else {
                        $data .= $subfield->[1] . ' ';
                    }
                }
            }
            if ($type eq 'array' && @subfieldsData) {
                push @$data, {subf => \@subfieldsData};
            }
            last unless ($multiple);
            $data .= $blank if ($type ne 'array' && @subfields);
        }
    }
    return $data;
}#getDataNaNFromField

# Modificación MASmedios --> recoger los subcampos a de un campo determinado
sub getDataAFromField
{
    my ($record, $tag, $type, $fieldsAdditional) = @_;
    
    my $data;
    if ($record && $record->field($tag)) {
        $type = '' unless ($type);
        $data = [] if ($type eq 'array');
        foreach my $field ( $record->field($tag) ) {
            if ($type && $type eq 'array') {
                push @$data, {'value' => $field->subfield('a')};
            } else {
                $data .= $field->subfield('a') . '<br/>' if ($field->subfield('a'));
                if ($fieldsAdditional && @$fieldsAdditional) {
                    for my $subf (@$fieldsAdditional) {
                        for my $subfield ($field->subfield($subf)) {
                            $data .= $field->subfield($subf) . '<br/>' if ($field->subfield($subf));
                        }
                    }
                }
            }
        }
    }
    return $data;
}#getDataAFromField

# Modificación MASmedios --> recoger los subcampos dterminados o no numéricos de unos campos que son auth determinados
sub getAuthFromFields
{
    my ($record, $tags, $multiple) = @_;
    
    my @data = ();
    if ($record) {
        my ($tag, $ind, $code, $value);
        TAG:
        for $tag (sort keys %$tags) {
            if ($record->field($tag)) {
                FIELD:
                foreach my $field ( $record->field($tag) ) {
                    # filtro de indicadores
                    if (exists($tags->{$tag}->{ind})) {
                        for $ind (sort keys %{$tags->{$tag}->{ind}}) {
                            if (defined($field->indicator($ind))) {
                                my $okInd = 0;
                                for (@{$tags->{$tag}->{ind}->{$ind}}) {
                                    if ($field->indicator($ind) eq $_) {
                                        $okInd = 1;
                                        last;
                                    }
                                }
                                next FIELD unless ($okInd);
                            } else {
                                next FIELD;
                            }
                        }
                    }
                    my @data_subfields = ();
                    my @subfields = $field->subfields();
                    my $link = '';
                    if (@subfields) {
                        if ($field->subfield('9')) {
                            $link = $field->subfield('9');
                        }
                        foreach my $subfield (@subfields) {
                            $code = $subfield->[0];
                            # filtro de subcampos
                            if (exists($tags->{$tag}->{subf})) {
                                next unless (exists($tags->{$tag}->{subf}->{'A'}) || exists($tags->{$tag}->{subf}->{$code}));
                            }
                            $value = $subfield->[1];
                            push @data_subfields, {code => $code, value => $value} if($code =~ /\D/ ); #todos las subcampos menos los numéricos
                        }
                    }
                    last unless ($multiple);
                    push @data, {tag => $tag, subf => \@data_subfields, link => $link};
                }
            }
        }
    }
    return \@data;
}#getAuthFromFields


#print "Content-type: text/html\n\n";
#print $record->fields()->[0];
foreach ( keys %{$dat} ) {
        # Modificación MASmedios --> cogemos todos los subcampos del 100 y en caso de no estar el 100, cogemos el 110 ó el 111
        my ($author, $author_no_a);
        #print $_; print "----     ";
        #print $dat->{$_};
        #print "<br>";
        #if(($_ eq "author") && !$dat->{$_}) {
        if(($_ eq "author")) {
            $author = getDataAFromField($record, '100');
            unless (defined($author)) {
                $author = getDataAFromField($record, '110');
                unless (defined($author)) {
                    $author = getDataAFromField($record, '111');
                    $author_no_a = getDataNaNFromField($record, '111') if (defined($author));
                } else {
                    $author_no_a = getDataNaNFromField($record, '110');
                }
            } else {
                $author_no_a = getDataNaNFromField($record, '100');
            }
            if (defined($author)) {
                $author =~ s/<br\/>//g;
                $author_no_a =~ s/^\s*$author//;
                $template->param(author => $author, author_no_a => $author_no_a);
            }
        } elsif ($_ =~ /^(title|unititle)$/) {
            my $strTitle = $dat->{$_};
            my $fieldTitle;
            if ($_ eq 'title') {
                $fieldTitle = $record->field('245');
            } else {
                $fieldTitle = $record->field('240');
            }
            if ($fieldTitle) {
                for my $subfieldTitle ($fieldTitle->subfields()) {
                    if ($subfieldTitle->[0] ne 'a') {
                        $strTitle .= ' ' . $subfieldTitle->[1];
                    }
                }
            }
            $template->param( "$_" => defined $strTitle ? $strTitle : '' );
        } else {
            $template->param( "$_" => defined $dat->{$_} ? $dat->{$_} : '' );
        }

}

# Modificación MASmedios --> obtener el campo titulo uniforme 130 (encabezamiento principal)
my $titulouniforme = getDataNaNFromField($record, '130');
$template->param(titulouniforme => $titulouniforme) if (defined($titulouniforme));

# Modificación MASmedios --> obtener el campo Notas: titulo anterior 247
my $tit_anterior = getDataNaNFromField($record, '247', 1);
$template->param(tit_anterior => $tit_anterior) if (defined($tit_anterior));

# Modificación MASmedios --> obtener el campo Edición 250
my $edicion = getDataNaNFromField($record, '250');
$template->param(edicion => $edicion) if (defined($edicion));

# Modificación MASmedios --> obtener el campo escala 255
my $escala = getDataNaNFromField($record, '255');
$template->param(escala => $escala) if (defined($escala));

# Modificación MASmedios --> obtener el campo publicacion 260
my $publicacion = getDataNaNFromField($record, '260');
$template->param(publicacion => $publicacion) if (defined($publicacion));

# Modificación MASmedios --> obtener el campo descripcion 300
my $descripcion = getDataNaNFromField($record, '300');
$template->param(descripcion => $descripcion) if (defined($descripcion));

# Modificación MASmedios --> obtener el campo fecuencia 310
my $frec = getDataNaNFromField($record, '310');
$template->param(frec => $frec) if (defined($frec));

# Modificación MASmedios --> obtener el campo fecuencia anterior 321
my $frec_ant = getDataNaNFromField($record, '321');
$template->param(frec_ant => $frec_ant) if (defined($frec_ant));

# Modificación MASmedios --> obtener el campo Nota general 500
my $nota_general = getDataAFromField($record, '500');
$template->param(nota_general => $nota_general) if (defined($nota_general));

# Modificación MASmedios --> obtener el campo Nota "con" 501
my $nota_con = getDataAFromField($record, '501');
$template->param(nota_con => $nota_con) if (defined($nota_con));

# Modificación MASmedios --> obtener el campo Nota de bibliografia 504
my $nota_bibl = getDataAFromField($record, '504');
$template->param(nota_bibl => $nota_bibl) if (defined($nota_bibl));

# Modificación MASmedios --> obtener el campo Notas: contenido 505
my $cont_format = '';
my @data505 = ();
foreach my $field505 ( $record->field('505') ) {
    if ($field505->indicator(1) == 7) {
        my $refH505 = {};
        $refH505->{'titulo'} = $field505->subfield('t') if ($field505->subfield('t'));
        if ($field505->subfield('c')) {
            $refH505->{'autor'} = $field505->subfield('c');
        } elsif ($field505->subfield('r')) {
            $refH505->{'autor'} = $field505->subfield('r');
        }
        $refH505->{'autorlink'} = ($field505->subfield('f'))?$field505->subfield('f'):$refH505->{'autor'};
        $refH505->{'paginas'} = $field505->subfield('p') if (defined($field505->subfield('p')));
        push @data505, $refH505;
    } else {
        my @subfields = $field505->subfields();
        foreach my $subfield (@subfields) {
            if($subfield->[0] =~ /\D/ ) {
                $cont_format .= $subfield->[1] . ' ';
            }
        }
        $cont_format .= '<br/>' if (@subfields);
    }
}
$template->param(cont_format => $cont_format) if (defined($cont_format));
$template->param(data505 => \@data505) if (@data505);

# Modificación MASmedios --> obtener el campo Nota a la escala 507
my $nota_escala = getDataAFromField($record, '507');
$template->param(nota_escala => $nota_escala) if (defined($nota_escala));

# Modificación MASmedios --> obtener el campo Notas: Bibl 510
my $ref_bibl = getDataNaNFromField($record, '510', 1);
$template->param(ref_bibl => $ref_bibl) if (defined($ref_bibl));

# Modificación MASmedios --> obtener el campo Notas: sumario 520
my $sumario = getDataNaNFromField($record, '520', 1);
$template->param(sumario => $sumario) if (defined($sumario));

# Modificación MASmedios --> obtener el campo Notas: sumario geografico 522
my $sum_geo = getDataAFromField($record, '522');
$template->param(sum_geo => $sum_geo) if (defined($sum_geo));

# Modificación MASmedios --> obtener el campo Suplemento: suplemento 525
my $suplemento = getDataAFromField($record, '525');
$template->param(suplemento => $suplemento) if (defined($suplemento));

# Modificación MASmedios --> obtener el campo Notas: Letra/lengua 546
my $lengua = getDataNaNFromField($record, '546', 1);
$template->param(lengua => $lengua) if (defined($lengua));

# Modificación MASmedios --> obtener el campo Notas: indices 555
my $indices = getDataNaNFromField($record, '555', 1);
$template->param(indices => $indices) if (defined($indices));

# Modificación MASmedios --> obtener el campo Notas: Procedencia 561
my $procedencia = getDataAFromField($record, '561');
$template->param(procedencia => $procedencia) if (defined($procedencia));

# Modificación MASmedios --> obtener el campo Notas: editado en 580
my $nota_compleja = getDataAFromField($record, '580', undef, ['6']);
$template->param(nota_compleja => $nota_compleja) if (defined($nota_compleja));

# Modificación MASmedios --> obtener el campo Notas: editado en 581
my $editado_en = getDataAFromField($record, '581');
$template->param(editado_en => $editado_en) if (defined($editado_en));

# Modificación MASmedios --> obtener el campo Notas: incipit 592
my $incipit = getDataNaNFromField($record, '592', 1);
$template->param(incipit => $incipit) if (defined($incipit));

# Modificación MASmedios --> obtener el campo Nota autor/título 594
my $nota_autor = getDataAFromField($record, '594');
$template->param(nota_autor => $nota_autor) if (defined($nota_autor));

# Modificación MASmedios --> obtener el campo Nota historia editorial 595
my $historia_edi = getDataAFromField($record, '595');
$template->param(historia_edi => $historia_edi) if (defined($historia_edi));

# Modificación MASmedios --> obtener el campo Notas: fecha/imprenta 596
my $nota_fecha = getDataAFromField($record, '596');
$template->param(nota_fecha => $nota_fecha) if (defined($nota_fecha));

# Modificación MASmedios --> obtener el campo Notas: descripción física 597
my $desc_fisica = getDataAFromField($record, '597');
$template->param(desc_fisica => $desc_fisica) if (defined($desc_fisica));

# Modificación MASmedios --> obtener el campo Notas: ilustracion 599
my $ilustracion = getDataAFromField($record, '599');
$template->param(ilustracion => $ilustracion) if (defined($ilustracion));

# Modificación MASmedios --> obtener el campo Formas: formas 655
my $formas = getAuthFromFields($record, {'655' => {subf => {'a' => 1}}}, 1);
$template->param(formas => $formas) if (defined($formas));

# Modificación MASmedios --> obtener el campo Onomastico: onomastico 700,710 con indicador 2 valores 1,2,3
my $onomastico = getAuthFromFields($record, {'700' => {ind => {'1' => [1,2,3]}, subf => {'A' => 1, 'b' => 1, 'c' => 1, 'd' => 1, 'e' => 1, 'f' => 1, 'g' => 1, 'h' => 1, 'i' => 1, 'j' => 1, 'k' => 1, 'l' => 1, 'm' => 1, 'n' => 1, 'o' => 1, 'p' => 1, 'q' => 1, 'r' => 1, 's' => 1, 't' => 1, 'u' => 1, 'v' => 1, 'w' => 1, 'x' => 1, 'y' => 1, 'z' => 1}}, '710' => {ind => {'1' => [1,2,3]}, subf => {'a' => 1, 'b' => 1, 'c' => 1, 'd' => 1, 'e' => 1, 'f' => 1, 'g' => 1, 'h' => 1, 'i' => 1, 'j' => 1, 'k' => 1, 'l' => 1, 'm' => 1, 'n' => 1, 'o' => 1, 'p' => 1, 'q' => 1, 'r' => 1, 's' => 1, 't' => 1, 'u' => 1, 'v' => 1, 'w' => 1, 'x' => 1, 'y' => 1, 'z' => 1}}}, 1);
$template->param(onomastico => $onomastico) if (defined($onomastico));

# Modificación MASmedios --> obtener el campo Impresor/editor: impresores 700,710 con indicador 2 valores 4
my $impresores = getAuthFromFields($record, {'700' => {ind => {'1' => [4]}, subf => {'A' => 1, 'b' => 1, 'c' => 1, 'd' => 1, 'e' => 1, 'f' => 1, 'g' => 1, 'h' => 1, 'i' => 1, 'j' => 1, 'k' => 1, 'l' => 1, 'm' => 1, 'n' => 1, 'o' => 1, 'p' => 1, 'q' => 1, 'r' => 1, 's' => 1, 't' => 1, 'u' => 1, 'v' => 1, 'w' => 1, 'x' => 1, 'y' => 1, 'z' => 1}}, '710' => {ind => {'1' => [4]}, subf => {'a' => 1, 'b' => 1, 'c' => 1, 'd' => 1, 'e' => 1, 'f' => 1, 'g' => 1, 'h' => 1, 'i' => 1, 'j' => 1, 'k' => 1, 'l' => 1, 'm' => 1, 'n' => 1, 'o' => 1, 'p' => 1, 'q' => 1, 'r' => 1, 's' => 1, 't' => 1, 'u' => 1, 'v' => 1, 'w' => 1, 'x' => 1, 'y' => 1, 'z' => 1}}}, 1);
$template->param(impresores => $impresores) if (defined($impresores));

# Modificación MASmedios --> Eliminar de autores los onomásticos e impresores mediante comparación del link $9
my @autores = ();
for my $hashRA (@$marcauthorsarray) {
    my $found = 0;
    for (@{$hashRA->{MARCAUTHOR_SUBFIELDS_LOOP}}) {
        next unless (@{$_->{link_loop}});
        my $link = $_->{link_loop}->[0]->{link};
        if ($link =~ /^[0-9]+$/) {
            for my $impresor (@$impresores) {
                if ($impresor->{link} == $link) {
                    $found = 1;
                    last;
                }
            }
            last if ($found);
            for my $onomastic (@$onomastico) {
                if ($onomastic->{link} == $link) {
                    $found = 1;
                    last;
                }
            }
            last if ($found);
        }
    }
    push @autores, $hashRA unless ($found);
}
$template->param(MARCAUTHORS => \@autores);

# Modificación MASmedios --> obtener el campo titulo uniforme 730 (encabezamientos secundario)
my $uniformtitle = getDataNaNFromField($record, '730', 1, ' | ', 'array');
$template->param(uniformtitle => $uniformtitle) if (defined($uniformtitle));

# Modificación MASmedios --> obtener el campo Notas: titulo alternativo 740
my $titul_alt = getDataAFromField($record, '740', 'array');
$template->param(titul_alt => $titul_alt) if (defined($titul_alt));

# Modificación MASmedios --> obtener el campo Lugar de impresión 752
my $lugar_imp = getDataNaNFromField($record, '752', 1);
$template->param(lugar_imp => $lugar_imp) if (defined($lugar_imp));

# Modificación MASmedios --> obtener el campo analíticas 773
my @analytics773 = ();
for my $field773 ($record->field('773')) {
    my $ref773 = {};
    for my $subfield773 ($field773->subfields()) {
        if ($subfield773->[0] =~ /^[adgt]$/) {
            $subfield773->[1] =~ s/-+$//g;
            $ref773->{$subfield773->[0]} = $subfield773->[1];
        }
    }
    push @analytics773, $ref773;
}
$template->param(analytics773 => \@analytics773) if (@analytics773);

# Modificación MASmedios --> obtener el campo ejemplares 852
my @ejemplares852 = ();
my $numejemplar = 1;
for my $field852 ($record->field('852')) {
    my @arr852 = ();
    for my $subfield852 ($field852->subfields()) {
        if ($subfield852->[0] =~ /^[acipqrtuvwxz389]$/) {
            my $ref852 = {};
            $ref852->{'code'} = $subfield852->[0];
            $ref852->{'data'} = $subfield852->[1];
            push @arr852, $ref852;
        }
    }
    my @ejemplar852 = map {$_->[0]} sort { $a->[1] cmp $b->[1] } map { [ $_, $_->{'code'} ] } @arr852;
    push @ejemplares852, {'ejemplar' => \@ejemplar852, 'num' => $numejemplar++};
}
$template->param(ejemplares852 => \@ejemplares852) if (@ejemplares852);


# Modificación MASmedios --> obtener el campo recursos electronicos 856
my @electronic_location = ();
for my $field856 ($record->field('856')) {
    my $hashRef = {};
    if ($field856->subfield('u')) {
        $hashRef->{electronic_location} = $field856->subfield('u');
        my $electronic_location_note = '';
        if ($field856->subfield('y')) {
            $electronic_location_note = $field856->subfield('y');
        } elsif ($field856->subfield('z') && $field856->subfield('z') !~ /.+img\s+src/) {
            $electronic_location_note = $field856->subfield('z');
        } else {
            $electronic_location_note = 'Acceso electr&oacute;nico';
        }
        $hashRef->{electronic_location_note} = $electronic_location_note;
    }
    if ($field856->subfield('z') && $field856->subfield('z') =~ /.+img\s+src\s*=\s*['"](http.+?)['"]/is) {
        $hashRef->{electronic_location_img} = $1;
    }
    push @electronic_location, $hashRef;
}
$template->param('electronic_location' => \@electronic_location);


# some useful variables for enhanced content;
# in each case, we're grabbing the first value we find in
# the record and normalizing it
my $upc = GetNormalizedUPC($record,$marcflavour);
my $oclc = GetNormalizedOCLCNumber($record,$marcflavour);
my $isbn = GetNormalizedISBN(undef,$record,$marcflavour);
my $content_identifier_exists;
if ( $isbn or $ean or $oclc or $upc ) {
    $content_identifier_exists = 1;
}
$template->param(
	normalized_upc => $upc,
	normalized_ean => $ean,
	normalized_oclc => $oclc,
	normalized_isbn => $isbn,
	content_identifier_exists =>  $content_identifier_exists,
);

# COinS format FIXME: for books Only
$template->param(
    ocoins => GetCOinSBiblio($record),
);

my $libravatar_enabled = 0;
if ( C4::Context->preference('ShowReviewer') and C4::Context->preference('ShowReviewerPhoto')) {
    eval {
        require Libravatar::URL;
        Libravatar::URL->import();
    };
    if (!$@ ) {
        $libravatar_enabled = 1;
    }
}

my $reviews = getreviews( $biblionumber, 1 );
my $loggedincommenter;




foreach ( @$reviews ) {
    my $borrowerData   = GetMember('borrowernumber' => $_->{borrowernumber});
    # setting some borrower info into this hash
    $_->{title}     = $borrowerData->{'title'};
    $_->{surname}   = $borrowerData->{'surname'};
    $_->{firstname} = $borrowerData->{'firstname'};
    if ($libravatar_enabled and $borrowerData->{'email'}) {
        $_->{avatarurl} = libravatar_url(email => $borrowerData->{'email'}, https => $ENV{HTTPS});
    }
    $_->{userid}    = $borrowerData->{'userid'};
    $_->{cardnumber}    = $borrowerData->{'cardnumber'};

    if ($borrowerData->{'borrowernumber'} eq $borrowernumber) {
		$_->{your_comment} = 1;
		$loggedincommenter = 1;
	}
}

# Modificación MASmedios --> comprobar que la vista ISBD está a off
if(C4::Context->preference("ISBD") && C4::Context->preference("viewISBD")) {
    $template->param(ISBD => 1);
}

$template->param(
    ITEM_RESULTS        => \@items,
    subscriptionsnumber => $subscriptionsnumber,
    biblionumber        => $biblionumber,
    subscriptions       => \@subs,
    subscriptionsnumber => $subscriptionsnumber,
    reviews             => $reviews,
    loggedincommenter   => $loggedincommenter
);

# Lists

if (C4::Context->preference("virtualshelves") ) {
   $template->param( 'GetShelves' => GetBibliosShelves( $biblionumber ) );
}


# XISBN Stuff
if (C4::Context->preference("OPACFRBRizeEditions")==1) {
    eval {
        $template->param(
            XISBNS => get_xisbns($isbn)
        );
    };
    if ($@) { warn "XISBN Failed $@"; }
}

# Serial Collection
my @sc_fields = $record->field(955);
my @lc_fields = $marcflavour eq 'UNIMARC'
    ? $record->field(930)
    : $record->field(852);
my @serialcollections = ();

foreach my $sc_field (@sc_fields) {
    my %row_data;

    $row_data{text}    = $sc_field->subfield('r');
    $row_data{branch}  = $sc_field->subfield('9');
    foreach my $lc_field (@lc_fields) {
        $row_data{itemcallnumber} = $marcflavour eq 'UNIMARC'
            ? $lc_field->subfield('a') # 930$a
            : $lc_field->subfield('h') # 852$h
            if ($sc_field->subfield('5') eq $lc_field->subfield('5'));
    }

    if ($row_data{text} && $row_data{branch}) { 
        push (@serialcollections, \%row_data);
    }
}

if (scalar(@serialcollections) > 0) {
    $template->param(
	serialcollection  => 1,
	serialcollections => \@serialcollections);
}

# Local cover Images stuff
if (C4::Context->preference("OPACLocalCoverImages")){
		$template->param(OPACLocalCoverImages => 1);
}

my $syndetics_elements;

if ( C4::Context->preference("SyndeticsEnabled") ) {
    $template->param("SyndeticsEnabled" => 1);
    $template->param("SyndeticsClientCode" => C4::Context->preference("SyndeticsClientCode"));
	eval {
	    $syndetics_elements = &get_syndetics_index($isbn,$upc,$oclc);
	    for my $element (values %$syndetics_elements) {
		$template->param("Syndetics$element"."Exists" => 1 );
		#warn "Exists: "."Syndetics$element"."Exists";
	}
    };
    warn $@ if $@;
}

if ( C4::Context->preference("SyndeticsEnabled")
        && C4::Context->preference("SyndeticsSummary")
        && ( exists($syndetics_elements->{'SUMMARY'}) || exists($syndetics_elements->{'AVSUMMARY'}) ) ) {
	eval {
	    my $syndetics_summary = &get_syndetics_summary($isbn,$upc,$oclc, $syndetics_elements);
	    $template->param( SYNDETICS_SUMMARY => $syndetics_summary );
	};
	warn $@ if $@;

}

if ( C4::Context->preference("SyndeticsEnabled")
        && C4::Context->preference("SyndeticsTOC")
        && exists($syndetics_elements->{'TOC'}) ) {
	eval {
    my $syndetics_toc = &get_syndetics_toc($isbn,$upc,$oclc);
    $template->param( SYNDETICS_TOC => $syndetics_toc );
	};
	warn $@ if $@;
}

if ( C4::Context->preference("SyndeticsEnabled")
    && C4::Context->preference("SyndeticsExcerpt")
    && exists($syndetics_elements->{'DBCHAPTER'}) ) {
    eval {
    my $syndetics_excerpt = &get_syndetics_excerpt($isbn,$upc,$oclc);
    $template->param( SYNDETICS_EXCERPT => $syndetics_excerpt );
    };
	warn $@ if $@;
}

if ( C4::Context->preference("SyndeticsEnabled")
    && C4::Context->preference("SyndeticsReviews")) {
    eval {
    my $syndetics_reviews = &get_syndetics_reviews($isbn,$upc,$oclc,$syndetics_elements);
    $template->param( SYNDETICS_REVIEWS => $syndetics_reviews );
    };
	warn $@ if $@;
}

if ( C4::Context->preference("SyndeticsEnabled")
    && C4::Context->preference("SyndeticsAuthorNotes")
	&& exists($syndetics_elements->{'ANOTES'}) ) {
    eval {
    my $syndetics_anotes = &get_syndetics_anotes($isbn,$upc,$oclc);
    $template->param( SYNDETICS_ANOTES => $syndetics_anotes );
    };
    warn $@ if $@;
}

# LibraryThingForLibraries ID Code and Tabbed View Option
if( C4::Context->preference('LibraryThingForLibrariesEnabled') ) 
{ 
$template->param(LibraryThingForLibrariesID =>
C4::Context->preference('LibraryThingForLibrariesID') ); 
$template->param(LibraryThingForLibrariesTabbedView =>
C4::Context->preference('LibraryThingForLibrariesTabbedView') );
} 

# Novelist Select
if( C4::Context->preference('NovelistSelectEnabled') ) 
{ 
$template->param(NovelistSelectProfile => C4::Context->preference('NovelistSelectProfile') ); 
$template->param(NovelistSelectPassword => C4::Context->preference('NovelistSelectPassword') ); 
$template->param(NovelistSelectView => C4::Context->preference('NovelistSelectView') ); 
} 


# Babelthèque
if ( C4::Context->preference("Babeltheque") ) {
    $template->param( 
        Babeltheque => 1,
        Babeltheque_url_js => C4::Context->preference("Babeltheque_url_js"),
    );
}

# Social Networks
if ( C4::Context->preference( "SocialNetworks" ) ) {
    $template->param( current_url => C4::Context->preference('OPACBaseURL') . "/cgi-bin/koha/opac-detail.pl?biblionumber=$biblionumber" );
    $template->param( SocialNetworks => 1 );
}

# Shelf Browser Stuff
if (C4::Context->preference("OPACShelfBrowser")) {
    # pick the first itemnumber unless one was selected by the user
    my $starting_itemnumber = $query->param('shelfbrowse_itemnumber'); # || $items[0]->{itemnumber};
    if (defined($starting_itemnumber)) {
        $template->param( OpenOPACShelfBrowser => 1) if $starting_itemnumber;
        my $nearby = GetNearbyItems($starting_itemnumber,3);

        $template->param(
            starting_homebranch => $nearby->{starting_homebranch}->{description},
            starting_location => $nearby->{starting_location}->{description},
            starting_ccode => $nearby->{starting_ccode}->{description},
            starting_itemnumber => $nearby->{starting_itemnumber},
            shelfbrowser_prev_itemnumber => $nearby->{prev_itemnumber},
            shelfbrowser_next_itemnumber => $nearby->{next_itemnumber},
            shelfbrowser_prev_biblionumber => $nearby->{prev_biblionumber},
            shelfbrowser_next_biblionumber => $nearby->{next_biblionumber},
            PREVIOUS_SHELF_BROWSE => $nearby->{prev},
            NEXT_SHELF_BROWSE => $nearby->{next},
        );
    }
}

$template->param( AmazonTld => get_amazon_tld() ) if ( C4::Context->preference("OPACAmazonCoverImages"));

if (C4::Context->preference("BakerTaylorEnabled")) {
	$template->param(
		BakerTaylorEnabled  => 1,
		BakerTaylorImageURL => &image_url(),
		BakerTaylorLinkURL  => &link_url(),
		BakerTaylorBookstoreURL => C4::Context->preference('BakerTaylorBookstoreURL'),
	);
	my ($bt_user, $bt_pass);
	if ($isbn and
		$bt_user = C4::Context->preference('BakerTaylorUsername') and
		$bt_pass = C4::Context->preference('BakerTaylorPassword')    )
	{
		$template->param(
		BakerTaylorContentURL   =>
		sprintf("http://contentcafe2.btol.com/ContentCafeClient/ContentCafe.aspx?UserID=%s&Password=%s&ItemKey=%s&Options=Y",
				$bt_user,$bt_pass,$isbn)
		);
	}
}

my $tag_quantity;
if (C4::Context->preference('TagsEnabled') and $tag_quantity = C4::Context->preference('TagsShowOnDetail')) {
	$template->param(
		TagsEnabled => 1,
		TagsShowOnDetail => $tag_quantity,
		TagsInputOnDetail => C4::Context->preference('TagsInputOnDetail')
	);
	$template->param(TagLoop => get_tags({biblionumber=>$biblionumber, approved=>1,
								'sort'=>'-weight', limit=>$tag_quantity}));
}

if (C4::Context->preference("OPACURLOpenInNewWindow")) {
    # These values are going to be read by Javascript, at least in the case
    # of the google covers
    $template->param(covernewwindow => 'true');
} else {
    $template->param(covernewwindow => 'false');
}

#Export options
my $OpacExportOptions=C4::Context->preference("OpacExportOptions");
my @export_options = split(/\|/,$OpacExportOptions);
$template->{VARS}->{'export_options'} = \@export_options;

if ( C4::Context->preference('OpacStarRatings') !~ /disable/ ) {
    my $rating = GetRating( $biblionumber, $borrowernumber );
    $template->param(
        rating_value   => $rating->{'rating_value'},
        rating_total   => $rating->{'rating_total'},
        rating_avg     => $rating->{'rating_avg'},
        rating_avg_int => $rating->{'rating_avg_int'},
        borrowernumber => $borrowernumber
    );
}

#Search for title in links
my $marccontrolnumber   = GetMarcControlnumber ($record, $marcflavour);
my $marcissns = GetMarcISSN ( $record, $marcflavour );
my $issn = $marcissns->[0] || '';

if (my $search_for_title = C4::Context->preference('OPACSearchForTitleIn')){
    $dat->{author} ? $search_for_title =~ s/{AUTHOR}/$dat->{author}/g : $search_for_title =~ s/{AUTHOR}//g;
    $dat->{title} =~ s/\/+$//; # remove trailing slash
    $dat->{title} =~ s/\s+$//; # remove trailing space
    $dat->{title} ? $search_for_title =~ s/{TITLE}/$dat->{title}/g : $search_for_title =~ s/{TITLE}//g;
    $isbn ? $search_for_title =~ s/{ISBN}/$isbn/g : $search_for_title =~ s/{ISBN}//g;
    $issn ? $search_for_title =~ s/{ISSN}/$issn/g : $search_for_title =~ s/{ISSN}//g;
    $marccontrolnumber ? $search_for_title =~ s/{CONTROLNUMBER}/$marccontrolnumber/g : $search_for_title =~ s/{CONTROLNUMBER}//g;
    $search_for_title =~ s/{BIBLIONUMBER}/$biblionumber/g;
    $template->param('OPACSearchForTitleIn' => $search_for_title);
}

# We try to select the best default tab to show, according to what
# the user wants, and what's available for display
my $opac_serial_default = C4::Context->preference('opacSerialDefaultTab');
my $defaulttab = 
    $opac_serial_default eq 'subscriptions' && $subscriptionsnumber
        ? 'subscriptions' :
    $opac_serial_default eq 'serialcollection' && @serialcollections > 0
        ? 'serialcollection' :
    $opac_serial_default eq 'holdings' && $dat->{'count'} > 0
        ? 'holdings' :
    $subscriptionsnumber
        ? 'subscriptions' :
    @serialcollections > 0 
        ? 'serialcollection' : 'subscriptions';
$template->param('defaulttab' => $defaulttab);

if (C4::Context->preference('OPACLocalCoverImages') == 1) {
    my @images = ListImagesForBiblio($biblionumber);
    $template->{VARS}->{localimages} = \@images;
}

if (C4::Context->preference('OpacHighlightedWords')) {
    $template->{VARS}->{query_desc} = $query->param('query_desc');
}

output_html_with_http_headers $query, $cookie, $template->output;
