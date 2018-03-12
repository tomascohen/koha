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
use t::lib::TestBuilder;

use Koha::Database;
use Koha::MARC::MergeRules;
use Koha::MARC::MergeTagRules;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'new() tests' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    Koha::MARC::MergeTagRules->search->delete;

    my $merge_rule_1 = $builder->build_object({ class => 'Koha::MARC::MergeRules' });
    my $merge_rule_2 = $builder->build_object({ class => 'Koha::MARC::MergeRules' });

    my $merge_tag_rule_1 = Koha::MARC::MergeTagRule->new({
        tag_filter          => '650',
        action             => 'skip',
        marc_merge_rule_id => $merge_rule_1->id
    })->store;

    my $merge_tag_rule_2 = Koha::MARC::MergeTagRule->new({
        tag_filter          => '650',
        action             => 'skip',
        marc_merge_rule_id => $merge_rule_2->id
    })->store;

    is( Koha::MARC::MergeTagRules->search->count, 2, 'Two tag rules added' );
    my $tag_rules = Koha::MARC::MergeTagRules->search({ marc_merge_rule_id => $merge_rule_1->id });
    is( $tag_rules->count, 1, 'Only one rule matches the merge rule id' );
    is( ref($tag_rules->next), 'Koha::MARC::MergeTagRule', 'Class is correct' );

    $schema->storage->txn_rollback;
}
