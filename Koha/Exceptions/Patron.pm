package Koha::Exceptions::Patron;

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

    'Koha::Exceptions::Patron' => {
        description => 'Something went wrong!',
    },
    'Koha::Exceptions::Patron::DuplicateObject' => {
        isa => 'Koha::Exceptions::Patron',
        description => "Patron cardnumber and userid must be unique",
        fields => ["conflict"],
    },
);

=head1 NAME

Koha::Exceptions::Patron - Base class for patrons exceptions

=head1 Exceptions

=head2 Koha::Exceptions::Patron

Generic patron exception

=head2 Koha::Exceptions::Patron::DuplicateObject

Exception to be used when trying to add duplicated data to the patrons DB.

=cut

1;
