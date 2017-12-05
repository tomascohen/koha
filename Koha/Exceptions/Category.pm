package Koha::Exceptions::Category;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Exception::Class (

    'Koha::Exceptions::Category' => {
        description => 'Something went wrong!',
    },
    'Koha::Exceptions::Category::CategorycodeNotFound' => {
        isa => 'Koha::Exceptions::Category',
        description => "Category does not exist",
        fields => ["categorycode"],
    },
);

=head1 NAME

Koha::Exceptions::Category - Base class for patron categories exceptions

=head1 Exceptions

=head2 Koha::Exceptions::Category

Generic patron category exception

=head2 Koha::Exceptions::Category::CategorycodeNotFound

Exception to be used when the required patron category code is not found.

=cut

1;
