use utf8;
package Koha::Schema::Result::MarcMergeTagRule;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::MarcMergeTagRule

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<marc_merge_tag_rules>

=cut

__PACKAGE__->table("marc_merge_tag_rules");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 tag_filter

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 action

  data_type: 'enum'
  default_value: 'skip'
  extra: {list => ["skip","overwrite","append"]}
  is_nullable: 0

=head2 overwrite_indicators

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 1

=head2 marc_merge_rule_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "tag_filter",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "action",
  {
    data_type => "enum",
    default_value => "skip",
    extra => { list => ["skip", "overwrite", "append"] },
    is_nullable => 0,
  },
  "overwrite_indicators",
  { data_type => "tinyint", default_value => 0, is_nullable => 1 },
  "marc_merge_rule_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 marc_merge_rule

Type: belongs_to

Related object: L<Koha::Schema::Result::MarcMergeRule>

=cut

__PACKAGE__->belongs_to(
  "marc_merge_rule",
  "Koha::Schema::Result::MarcMergeRule",
  { id => "marc_merge_rule_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "RESTRICT",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2018-03-12 18:17:20
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cTRZJBwaE/MItSDozbyiwQ

__PACKAGE__->add_columns( '+overwrite_indicators' => { is_boolean => 1 } );

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
