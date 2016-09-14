#!/usr/bin/perl

# This file is part of Koha.
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

use Test::More;
use Test::MockModule;

use MARC::Record;

use Module::Load::Conditional qw/check_install/;

BEGIN {
    if ( check_install( module => 'Test::DBIx::Class' ) ) {
        plan tests => 12;
    } else {
        plan skip_all => "Need Test::DBIx::Class"
    }
}

use_ok('C4::Matcher');

use Test::DBIx::Class {
    schema_class => 'Koha::Schema',
    connect_info => ['dbi:SQLite:dbname=:memory:','',''],
    connect_opts => { name_sep => '.', quote_char => '`', },
    fixture_class => '::Populate',
}, 'MarcMatcher' ;

fixtures_ok [
    MarcMatcher => [
        [ 'matcher_id', 'code', 'description', 'record_type', 'threshold' ],
        [ 1,            'ISBN', 'ISBN',        'red',         1 ],
        [ 2,            'ISSN', 'ISSN',        'blue',        0 ]
    ],
], 'add fixtures';

my $db = Test::MockModule->new('Koha::Database');
$db->mock( _new_schema => sub { return Schema(); } );

my @matchers = C4::Matcher::GetMatcherList();

is( $matchers[0]->{'matcher_id'}, 1, 'First matcher_id value is 1' );

is( $matchers[1]->{'matcher_id'}, 2, 'Second matcher_id value is 2' );

my $matcher_id = C4::Matcher::GetMatcherId('ISBN');

is( $matcher_id, 1, 'testing getmatcherid' );

my $testmatcher;

ok( $testmatcher = C4::Matcher->new( 'red', 1 ), 'testing matcher new' );

ok( $testmatcher = C4::Matcher->new( 'blue', 0 ), 'testing matcher new' );

$testmatcher->threshold(1000);

is( $testmatcher->threshold(), 1000, 'testing threshhold accessor method' );

$testmatcher->_id(53);

is( $testmatcher->_id(), 53, 'testing _id accessor' );

$testmatcher->code('match on ISBN');

is( $testmatcher->code(), 'match on ISBN', 'testing code accessor' );

$testmatcher->description('match on ISSN');

is( $testmatcher->description(), 'match on ISSN', 'testing code accessor' );

subtest '_get_match_keys() tests' => sub {

    plan tests => 3;

    use Data::Printer colored => 1;

    my $matchpoint = get_matchpoint({
        length => 0,
        norms  => [],
        offset => 0
    });

    my $record = MARC::Record->new();
    $record->append_fields(
        MARC::Field->new('100', ' ', ' ', a => 'King, Stephen'),
        MARC::Field->new('245', ' ', ' ', a => '  .; inSO[]:,mn(i)/A\'"' )
    );

    my @keys = C4::Matcher::_get_match_keys( $record, $matchpoint );

    is( $keys[0], 'INSOMNIA', 'Match key correctly calculated with no $norms');

    $matchpoint = get_matchpoint({
        length => 9,
        norms  => [],
        offset => 0
    });
    @keys = C4::Matcher::_get_match_keys( $record, $matchpoint );
    is( $keys[0], 'INS', 'Match key correctly calculated with length 9');

    $matchpoint = get_matchpoint({
        length => 9,
        norms  => [],
        offset => 1
    });
    @keys = C4::Matcher::_get_match_keys( $record, $matchpoint );
    is( $keys[0], 'INSO', 'Match key correctly calculated with length 9 and offset 1');
};

sub get_matchpoint {

    my $params = shift;

    my $length = $params->{length} // 0;
    my $norms  = $params->{norms}  // [];
    my $offset = $params->{offset} // 0;

    my $matchpoint = {
        components =>  [
            {
                length    => $length,
                norms     => $norms,
                offset    => $offset,
                subfields =>
                    {
                        a => 1
                    },
                tag => '245'
            }
        ],
        index => "title",
        score => 1000
    };

    return $matchpoint;
}

1;
