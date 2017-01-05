use utf8;
package Koha::Schema::Result::BorrowerAttributeType;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::BorrowerAttributeType

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<borrower_attribute_types>

=cut

__PACKAGE__->table("borrower_attribute_types");

=head1 ACCESSORS

=head2 code

  data_type: 'varchar'
  is_nullable: 0
  size: 10

=head2 description

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 repeatable

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 unique_id

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 opac_display

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 opac_editable

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 staff_searchable

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 authorised_value_category

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 display_checkout

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 category_code

  data_type: 'varchar'
  is_nullable: 1
  size: 10

=head2 class

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "code",
  { data_type => "varchar", is_nullable => 0, size => 10 },
  "description",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "repeatable",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "unique_id",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "opac_display",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "opac_editable",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "staff_searchable",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "authorised_value_category",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "display_checkout",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "category_code",
  { data_type => "varchar", is_nullable => 1, size => 10 },
  "class",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</code>

=back

=cut

__PACKAGE__->set_primary_key("code");

=head1 RELATIONS

=head2 borrower_attribute_types_branches

Type: has_many

Related object: L<Koha::Schema::Result::BorrowerAttributeTypesBranch>

=cut

__PACKAGE__->has_many(
  "borrower_attribute_types_branches",
  "Koha::Schema::Result::BorrowerAttributeTypesBranch",
  { "foreign.bat_code" => "self.code" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 borrower_attributes

Type: has_many

Related object: L<Koha::Schema::Result::BorrowerAttribute>

=cut

__PACKAGE__->has_many(
  "borrower_attributes",
  "Koha::Schema::Result::BorrowerAttribute",
  { "foreign.code" => "self.code" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2016-10-25 20:32:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gsPR8PuUUZHFUkr3MIbTpw

__PACKAGE__->add_columns(
    "+code" => {
        koha_description => "Unique key used to identify the attribute type"
    },
    "+description" =>
        { koha_description => "Description for the attribute type" },
    "+repeatable" => {
        koha_description =>
            "Defines if a patron can have multiple values for the attribute type"
    },
    "+unique_id" => {
        koha_description => "Defines if the assinged value need to be unique"
    },
    "+opac_display" => {
        koha_description =>
            "Defines if the attribute is visible to patrons on their account in the OPAC or not"
    },
    "+opac_editable" => {
        koha_description =>
            "Defines if the attribute is editable by patrons on their account in the OPAC or not"
    },
    "+staff_searchable" => {
        koha_description =>
            "Defines if the attribute is searchable via the patron search in the staff client"
    },
    "+authorised_value_category" => {
        koha_description =>
            "Foreign key from authorised_values that links this attribute to an authorized value category"
    },
    "+display_checkout" => {
        koha_description =>
            "Defines if the attribute  is displayed in checkout screens"
    },
    "+category_code" => {
        koha_description =>
            "Defines a constraint on a patron category for the attribute type"
    },
    "+class" =>
        { koha_description => "Defines a class for grouping attributes" }
);

# You can replace this text with custom content, and it will be preserved on regeneration
1;
