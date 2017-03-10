#!/usr/bin/perl

use Modern::Perl;

use Data::Printer colored => 1;
use File::Slurp;
use MARC::File::XML;
use MARC::Record;
use Try::Tiny;
use XML::LibXML;
use GOBI::PurchaseOrder;



my $file = 'ybp/GobiAPIRequestAndResponseExamples/1_ListedElectronicMonograph.xml';
#my $file = 'ybp/GobiAPIRequestAndResponseExamples/6_UnlistedPrintSerial.xml';
my $xml_string = read_file($file);

my $ybp_order;
try {
    $ybp_order = GOBI::PurchaseOrder->new($xml_string);
    p($ybp_order);
}
catch {
    if ( blessed $_ && $_->isa('GOBI::Exception') ) {
        p( $_->error );
    }
    else {
        die $_;
    }
};

1;
