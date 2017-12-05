package Koha::Exceptions::Library;

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

    'Koha::Exceptions::Library' => {
        description => 'Something went wrong!',
    },
    'Koha::Exceptions::Library::BranchcodeNotFound' => {
        isa => 'Koha::Exceptions::Library',
        description => "Library does not exist",
        fields => ["branchcode"],
    },
);

=head1 NAME

Koha::Exceptions::Library - Base class for libraries exceptions

=head1 Exceptions

=head2 Koha::Exceptions::Library

Generic library exception

=head2 Koha::Exceptions::Library::BranchcodeNotFound

Exception to be used when the required library code is not found.

=cut

1;
