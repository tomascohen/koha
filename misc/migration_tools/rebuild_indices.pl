#!/usr/bin/perl

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

# zebraidx -c etc/zebradb/indices/zebra-indices.cfg -d indices init
# bin/migration_tools/rebuild_indices.pl -a 1 -u 1 -d 0 -v -g &> kk.txt
# xsltproc -o indices.xml etc/zebradb/indices/indices2index.xsl tempL8Kh0.xml
# zebraidx -c etc/zebradb/indices/zebra-indices.cfg -g marcxml -d indices update tempL8Kh0.xml
# zebraidx -c etc/zebradb/indices/zebra-indices.cfg -g marcxml -d indices commit


use strict;
use C4::Context;
use ZOOM;
use MARC::Record;
use MARC::File::USMARC;
use MARC::File::XML;
use XML::Simple;
use DBI;
use Data::Dumper;
use Getopt::Long;
use File::Temp;
use C4::IndicesItems;

binmode(STDOUT, ":encoding(UTF-8)");

use constant LIMIT_FIX => 100;
use constant BUFFER_LIMIT_FIX => 500;

my $all_records = 0;
my $backup_indices = 0;
my $commit_all = 0;
my $delete_tmp = 1;
my $config_file;
my $init = 0;
my $zoom_update = 0;
my $biblionumber;
my $debug = 0;
my $utf8_active = 0;
my $verbose;
my $result = GetOptions(
    'a|all_records=i' => \$all_records,
    'b|backup_indices=i' => \$backup_indices,
    'c|config_file=s' => \$config_file,
    'd|delete_tmp=i' => \$delete_tmp,
    'g|debug' => \$debug,
    'i|init=i' => \$init,
    'm|commit_all=s' => \$commit_all,
    'n|biblionumber=i' => \$biblionumber,
    'u|utf8_active=i' => \$utf8_active,
    'v|verbose' => \$verbose,
    'z|zoom_update=i' => \$zoom_update,
);

if ($backup_indices) {
    $delete_tmp = 0;
    $commit_all = 0;
    $init = 0;
}
$config_file = $ENV{'KOHA_CONF'} unless ($config_file);

die "No se ha suministrado un fichero de configuración\n" unless ($config_file);
die "No existe o no tiene permisos adecuados para $config_file\n" unless (-f $config_file && -r $config_file);

my $conf = read_config_file();

#print Dumper $conf;


sub _format_zoom_error_message
{
    my $err = shift;

    my $message = "";
    if (ref($err) eq 'ZOOM::Connection') {
        $message = $err->errmsg() . " (" . $err->diagset . " " . $err->errcode() . ") " . $err->addinfo();
    } elsif (ref($err) eq 'ZOOM::Exception') {
        $message = $err->message() . " (" . $err->diagset . " " .  $err->code() . ") " . $err->addinfo();
    }
    return $message; 
}#_format_zoom_error_message


sub read_config_file 
{
    my $koha = XMLin($config_file, keyattr => ['id'], forcearray => ['listen', 'server', 'serverinfo']);
    return $koha;
}#read_config_file


sub conectZebra
{
    my ($server, $format) = @_;

    $conf = read_config_file() unless ($conf);
    my $Zconn;
    my $host = $conf->{'listen'}->{$server}->{'content'};
    my $servername = $conf->{'config'}->{$server};
    my $user = $conf->{'serverinfo'}->{$server}->{'user'};
    my $password = $conf->{'serverinfo'}->{$server}->{'password'};
    eval {
        my $o = new ZOOM::Options();
        $o->option(user=>$user);
        $o->option(password=>$password);
        $o->option(async => 0);
        $o->option(cqlfile=> $conf->{"server"}->{$server}->{"cql2rpn"});
        $o->option(cclfile=> $conf->{"serverinfo"}->{$server}->{"ccl2rpn"});
        $o->option(preferredRecordSyntax => ($format)?$format:'xml');
        $o->option(elementSetName => "F");
        $o->option(databaseName => $conf->{'config'}->{$server});

        $Zconn= create ZOOM::Connection($o);

        $Zconn->connect($host, 0);
        if ($Zconn->errcode() !=0) {
            warn $Zconn->errmsg();
        }
    };
    print 'ERROR: No se pudo conectar con zebra' . $@ . chr(10) if ($@);
    return $Zconn;
}#conectZebra

sub searchZebra
{
    my ($Zconn, $server, $query) = @_;

    my ($results, $hits);
    $Zconn = conectZebra($server) unless ($Zconn);
    eval {
        if ($Zconn && $Zconn->errcode() == 0) {
            print $query ."\n";
            $results = $Zconn->search_pqf($query);
            $hits = $results->size();
            print "hits: $hits\n";
        }
    };
    if ($@) {
        print "Error: $@\n";
        if ($@->code() eq 13) {
        } else {
            my $error = _format_zoom_error_message($@);
            warn "ERROR: $error";
        }
    }
    return ($Zconn, $results, $hits);
}#searchZebra

sub updateZebra
{
    my ($Zconn, $server, $record, $op) = @_;

    my $message = '';
    #$Zconn = C4::Context->_new_Zconn($server, 0, 1, '', 'xml');
    $Zconn = conectZebra($server) unless ($Zconn);
    if ($Zconn && $Zconn->errcode() == 0) {
        my $Zpackage = $Zconn->package();
        $Zpackage->option(action => $op);
        $Zpackage->option(record => $record);
        eval { $Zpackage->send("update") };
        if ($@ && $@->isa("ZOOM::Exception")) {
            $message = _format_zoom_error_message($@);
            $Zpackage->destroy();
            print $message;
        }
        eval { $Zpackage->send('commit'); };
        if ($@) {
            $message = _format_zoom_error_message($@);
            print $message;
        } else {
            $Zconn->destroy();
            return 1;
        }
        $Zconn->destroy();
    } else {
        print 'ERROR: No se pudo conectar al servidor ' . $server . ' para actualizar.' . chr(10);
    }
    return undef;
}#updateZebra



my $Zconn = ($backup_indices)?conectZebra('indicesserver', 'xml'):conectZebra('biblioserver', 'usmarc');
if ($Zconn) {
    my $results;
    my $hits = 0;
    my $query = ($biblionumber)?'@attr 1=12 ' . $biblionumber:'@attr 1=_ALLRECORDS @attr 2=103 ""';
    ($Zconn, $results, $hits) = searchZebra($Zconn, ($backup_indices)?'indicesserver':'biblioserver', $query);
    if ($hits && $results) {
        my $zebra_config  = C4::Context->zebraconfig('indicesserver')->{'config'};
        qx(zebraidx -c $zebra_config -g marcxml -d indices init) if ($init);
        my $tmpAll;
        if ($all_records || $backup_indices) {
            $tmpAll = File::Temp->new( TEMPLATE => 'tempXXXXX', UNLINK => $delete_tmp, SUFFIX => '.xml');
            if ($utf8_active) {
                open(FH, '>:utf8', $tmpAll) or die "Error: Fallo al abrir $tmpAll\n";
            } else {
                open(FH, '>', $tmpAll) or die "Error: Fallo al abrir $tmpAll\n";
            }
            print(FH '<?xml version="1.0" encoding="UTF-8"?>' . chr(10));
            print(FH '<INDICES>' . chr(10));
        }
        my $indicesObj = new C4::IndicesItems();
        #print Dumper $indicesObj->{'indexes'};
        my $bibliosProcessed = 0;
        my $strBuffer = '';
        my $offset = 0;
        my $j = 0;
        my $z = 0;
        my $limit = ($hits < LIMIT_FIX)?$hits:LIMIT_FIX;
        my $limit_rec = $limit;
        #for (my $z=0; $z < $hits; $z++) {
        while ($offset < $hits) {
            #$results->records($offset, $limit, 0);
            $results->records($offset, $limit_rec, 0);
            for ($j = $offset, $z = 0; $j < $limit; $j++, $z++) {
                last if ($bibliosProcessed >= $hits);
                my $recordRaw = $results->record($j)->raw();
                $bibliosProcessed++;
                if ($backup_indices) {
                    my ($type, $data, $idIndice) = $indicesObj->getDataFromIndiceRecord($recordRaw);
                    #my $strIndice = '<indice tipo="' . $type . '">' . $indicesObj->_parseContent2Xml($data) . '</indice>' . chr(10);
                    $idIndice = '' if ($idIndice ne $indicesObj->getShaIndice($type, $data));
                    $strBuffer .= $indicesObj->buildIndice($idIndice, $type, $data) . chr(10);
                    if ($bibliosProcessed % BUFFER_LIMIT_FIX == 0) {
                        #print(FH $strIndice);
                        print(FH $strBuffer);
                        $strBuffer = '';
                    }
                    next;
                }
                my $marcRecord;
                eval {
                    $marcRecord = MARC::Record->new_from_usmarc($recordRaw);
                    #$marcRecord = new_record_from_zebra( 'biblioserver', $recordRaw );
                };
                unless ($@) {
                    #print Dumper $marcRecord if ($debug);
                    my $indicesXml = $indicesObj->processIndicesOnRecord($marcRecord, $zoom_update, 'update', $all_records, undef, $debug);
                    next unless ($indicesXml);
                    unless ($all_records) {
                        unless ($zoom_update) {
                            $indicesXml = '<INDICES>' . chr(10) . $indicesXml . '</INDICES>' . chr(10);
                            my $tmp = File::Temp->new( TEMPLATE => 'tempXXXXX', UNLINK => $delete_tmp, SUFFIX => '.xml');
                            if ($tmp && -w $tmp) {
                                if (($utf8_active && open(FH, '>:utf8', $tmp)) || (!$utf8_active && open(FH, '>', $tmp))) {
                                    print(FH $indicesXml);
                                    close(FH);
                                }
                                qx(zebraidx -c $zebra_config -g marcxml -d indices update $tmp);
                                qx(zebraidx -c $zebra_config -g marcxml -d indices commit);
                            }
                        }
                    } else {
                        my $indicesXmlAux = '<?xml version="1.0" encoding="UTF-8"?>' . chr(10) . '<INDICES>' . $indicesXml . '</INDICES>' . chr(10);
                        eval {
                            XMLin($indicesXmlAux);
                        };
                        if ($@) {
                            print "$@\n";
                        } else {
                            print(FH $indicesXml) if (utf8::valid($indicesXml));
                        }
                        $indicesXml = undef;
                    }
                }
                $recordRaw = undef;
                $marcRecord = undef;
            }
            $offset += $z;
            $limit_rec = ($offset + LIMIT_FIX > $hits)?$hits - $offset:LIMIT_FIX;
            $limit = ($offset + LIMIT_FIX > $hits)?$hits:$offset + LIMIT_FIX;
            print "hits: $hits , recordsProcessed: $bibliosProcessed , limit: $limit , limit_rec: $limit_rec , j: $j , offset: $offset\n" if ($verbose);
        }
        print "\nRegistros biblio procesados: $bibliosProcessed\n";
        if ($all_records || $backup_indices) {
            print(FH $strBuffer) if ($strBuffer);
            print(FH '</INDICES>' . chr(10));
            close(FH);
            if ($commit_all) {
                qx(zebraidx -c $zebra_config -g marcxml -d indices update $tmpAll);
                qx(zebraidx -c $zebra_config -g marcxml -d indices commit);
            }
        }
    } else {
        print "Warning: sin registros bibliográficos\n";
    }
} else {
    print "Error: sin conexión a Zebra\n";
}
