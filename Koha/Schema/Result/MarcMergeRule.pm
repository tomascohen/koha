use utf8;
package Koha::Schema::Result::MarcMergeRule;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::MarcMergeRule

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<marc_merge_rules>

=cut

__PACKAGE__->table("marc_merge_rules");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 24

=head2 description

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 24 },
  "description",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 marc_merge_tag_rules

Type: has_many

Related object: L<Koha::Schema::Result::MarcMergeTagRule>

=cut

__PACKAGE__->has_many(
  "marc_merge_tag_rules",
  "Koha::Schema::Result::MarcMergeTagRule",
  { "foreign.marc_merge_rule_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2018-03-12 18:08:03
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:fEWdGfi8FtOZQ4glHOi1lA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
