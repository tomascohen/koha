package Koha::REST::V1::Patron;

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

use Mojo::Base 'Mojolicious::Controller';

use C4::Members qw( AddMember ModMember );
use Koha::Patrons;

use Scalar::Util qw(blessed);
use Try::Tiny;

sub list {
    my $c = shift->openapi->valid_input or return;

    my $args   = $c->req->params->to_hash;
    my $filter = {};
    for my $filter_param ( keys %$args ) {
        $filter->{$filter_param} = { LIKE => $args->{$filter_param} . "%" };
    }

    return try {
        my $patrons = Koha::Patrons->search($filter);
        return $c->render(status => 200, openapi => $patrons);
    }
    catch {
        if ( $_->isa('DBIx::Class::Exception') ) {
            return $c->render( status => 500, openapi => { error => $_->{msg} } );
        }
        else {
            return $c->render( status => 500, openapi => { error => "Something went wrong, check the logs." } );
        }
    };
}

sub get {
    my $c = shift->openapi->valid_input or return;

    my $borrowernumber = $c->validation->param('borrowernumber');
    my $patron = Koha::Patrons->find($borrowernumber);

    unless ($patron) {
        return $c->render(status => 404, openapi => { error => "Patron not found." });
    }

    return $c->render(status => 200, openapi => $patron);
}

sub add {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $body = $c->validation->param('body');

        Koha::Patron->new($body)->_validate;

        # TODO: Use AddMember until it has been moved to Koha-namespace
        my $borrowernumber = AddMember(%$body);
        my $patron         = Koha::Patrons->find($borrowernumber);

        return $c->render( status => 201, openapi => $patron );
    }
    catch {
        unless ( blessed $_ && $_->can('rethrow') ) {
            return $c->render(
                status  => 500,
                openapi => {
                    error =>
                      "Something went wrong, check Koha logs for details."
                }
            );
        }
        if ( $_->isa('Koha::Exceptions::Patron::DuplicateObject') ) {
            return $c->render(
                status  => 409,
                openapi => { error => $_->error, conflict => $_->conflict }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Library::BranchcodeNotFound') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "Given branchcode does not exist" }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Category::CategorycodeNotFound') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "Given categorycode does not exist" }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => {
                    error =>
                      "Something went wrong, check Koha logs for details."
                }
            );
        }
    };
}

sub update {
    my $c = shift->openapi->valid_input or return;

    my $patron = Koha::Patrons->find($c->validation->param('borrowernumber'));

    return try {
        my $body = $c->validation->param('body');

        $patron->set(_to_model($body))->_validate;

        # TODO: Use ModMember until it has been moved to Koha-namespace
        if ( ModMember( %$body ) ) {
            return $c->render( status => 200, openapi => $patron );
        }
        else {
            return $c->render( status => 500, openapi => { error => 'Something went wrong, check Koha logs for details.' } );
        }
    }
    catch {
        unless ($patron) {
            return $c->render(
                status  => 404,
                openapi => { error => "Patron not found" }
            );
        }
        unless ( blessed $_ && $_->can('rethrow') ) {
            return $c->render(
                status  => 500,
                openapi => {
                    error =>
                      "Something went wrong, check Koha logs for details."
                }
            );
        }
        if ( $_->isa('Koha::Exceptions::Patron::DuplicateObject') ) {
            return $c->render(
                status  => 409,
                openapi => { error => $_->error, conflict => $_->conflict }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Library::BranchcodeNotFound') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "Given branchcode does not exist" }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Category::CategorycodeNotFound') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "Given categorycode does not exist" }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::MissingParameter') ) {
            return $c->render(
                status  => 400,
                openapi => {
                    error      => "Missing mandatory parameter(s)",
                    parameters => $_->parameter
                }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::BadParameter') ) {
            return $c->render(
                status  => 400,
                openapi => {
                    error      => "Invalid parameter(s)",
                    parameters => $_->parameter
                }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::NoChanges') ) {
            return $c->render(
                status  => 204,
                openapi => { error => "No changes have been made" }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => {
                    error =>
                      "Something went wrong, check Koha logs for details."
                }
            );
        }
    };
}

sub delete {
    my $c = shift->openapi->valid_input or return;

    my $patron;

    return try {
        $patron = Koha::Patrons->find( $c->validation->param('borrowernumber') );

        # check if loans, reservations, debarrment, etc. before deletion!
        my $res = $patron->delete;
        return $c->render( status => 200, openapi => {} );
    }
    catch {
        unless ($patron) {
            return $c->render(
                status  => 404,
                openapi => { error => "Patron not found" }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => {
                    error =>
                      "Something went wrong, check Koha logs for details."
                }
            );
        }
    };
}

sub _delete_unmodifiable_parameters {
    my ($body) = @_;

    my %columns = map { $_ => 1 } Koha::Patron::Modifications->columns;
    foreach my $param (keys %$body) {
        unless (exists $columns{$param}) {
            delete $body->{$param};
        }
    }
    return $body;
}

sub _to_model {
    my $params = shift;

    $params->{lost} = ($params->{lost}) ? 1 : 0;
    $params->{gonenoaddress} = ($params->{gonenoaddress}) ? 1 : 0;

    return $params;
}

1;
