#!/usr/bin/perl

# This file is part of Koha
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

use Test::More tests => 1;

use Koha::Database;
use Koha::MARC::MergeRules;

my $schema  = Koha::Database->new->schema;

subtest 'new() tests' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    Koha::MARC::MergeRules->search->delete;

    my $merge_rule = Koha::MARC::MergeRule->new({
                        name => 'Rule name',
                        description => 'Rule description' });

    is( Koha::MARC::MergeRules->search->count, 0, 'No rules stored' );
    $merge_rule->store;

    is( Koha::MARC::MergeRules->search->count, 1, 'Rule stored');

    $schema->storage->txn_rollback;
}

