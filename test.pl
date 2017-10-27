#!/usr/bin/perl

use Modern::Perl;

use Data::Printer colored => 1;

use Koha::Database;
use Koha::SearchEngine::Elasticsearch;

use Search::Elasticsearch;

my $biblio_es_params = Koha::SearchEngine::Elasticsearch->new({ index => 'biblios' })->get_elasticsearch_params;
#p($biblio_es_params);

my $es = Search::Elasticsearch->new($biblio_es_params);
#p($es->indices->stats( index => $biblio_es_params->{index_name} ));

my $authorities_es_params = Koha::SearchEngine::Elasticsearch->new({ index => 'authorities' })->get_elasticsearch_params;
my $authorities_index = $authorities_es_params->{index_name};
$es = Search::Elasticsearch->new($authorities_es_params);
my $authorities_count = $es->indices->stats( index => $authorities_es_params->{index_name} )->{_all}{primaries}{docs}{count};
p($authorities_count);


my $status = Koha::SearchEngine::Elasticsearch->status;
p($status);


1;

