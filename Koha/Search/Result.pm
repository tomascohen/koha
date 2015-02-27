package Koha::Search::Result;

# Copyright 2015 Theke Solutions

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

Koha::Search::Result

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use Modern::Perl;
use Carp;

# Class definition
use base qw(Class::Accessor);

__PACKAGE__->mk_ro_accessors(qw/ name version /);
__PACKAGE__->mk_accessors(qw/ id schema record /);

our $NAME = 'Koha::Search::Result';
our $VERSION = '0.1';

sub new {
    
    my $class  = shift;
    my $params = shift;

    croak "id is mandatory" if ! defined $params->{ id };
    croak "No record passed on creation" if ! defined $params->{ record };

    my $schema = $params->{ schema } // 'MARCXML';
    my $id     = $params->{ id };
    my $record = $params->{ record };

    my $self = $class->SUPER::new({
        schema => $schema,
        id     => $id,
        record => $record
    });

    bless $self, $class;
    return $self;
}

1;

=head1 AUTHOR

Tomas Cohen Arazi <tomascohen@gmail.com>

Koha Development Team <http://koha-community.org/>

=cut
