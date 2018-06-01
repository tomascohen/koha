package Koha::REST::V1::Patrons::Account;

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

use Try::Tiny;

=head1 NAME

Koha::REST::V1::Patrons::Account

=head1 API

=head2 Methods

=head3 get

Controller function that handles retrieving a patron's account balance

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    my $patron_id = $c->validation->param('patron_id');
    my $patron    = Koha::Patrons->find($patron_id);

    unless ($patron) {
        return $c->render( status => 404, openapi => { error => "Patron not found." } );
    }

    my $balance;

    $balance->{balance} = $patron->account->balance;

    my @outstanding_fines = Koha::Account::Lines->search(
        {   borrowernumber    => $self->{patron_id},
            amountoutstanding => { '>' => 0 }
        }
    );
    $balance->{standing_lines} = map { $self->_to_api($_) } @outstanding_fines
        if scalar @outstanding_fines > 0;

    return $c->render( status => 200, openapi => $balance );
}

=head3 add_credit

Controller function that handles adding a credit to a patron's account

=cut

sub add_credit {
    my $c = shift->openapi->valid_input or return;

    return try {

        my $body = _to_model( $c->validation->param('body') );

        # TODO: Use AddMember until it has been moved to Koha-namespace
        my $patron_id = AddMember( %{ _to_model($body) } );
        my $patron    = _to_api( Koha::Patrons->find($patron_id)->TO_JSON );

        return $c->render( status => 201, openapi => $patron );
    }
    catch {
        unless ( blessed $_ && $_->can('rethrow') ) {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check Koha logs for details." }
            );
        }
        if ( $_->isa('Koha::Exceptions::Object::DuplicateID') ) {
            return $c->render(
                status  => 409,
                openapi => { error => $_->error, conflict => $_->duplicate_id }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Object::FKConstraint') ) {
            return $c->render(
                status  => 400,
                openapi => {
                          error => "Given "
                        . $Koha::REST::V1::Patrons::to_api_mapping->{ $_->broken_fk }
                        . " does not exist"
                }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::BadParameter') ) {
            return $c->render(
                status  => 400,
                openapi => {
                          error => "Given "
                        . $Koha::REST::V1::Patrons::to_api_mapping->{ $_->parameter }
                        . " does not exist"
                }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check Koha logs for details." }
            );
        }
    };
}

=head3 add_debit

Controller function that handles adding a debit to a patron's account

=cut

sub add_debit {
    my $c = shift->openapi->valid_input or return;

    return try {

        my $body = _to_model( $c->validation->param('body') );

        # TODO: Use AddMember until it has been moved to Koha-namespace
        my $patron_id = AddMember( %{ _to_model($body) } );
        my $patron    = _to_api( Koha::Patrons->find($patron_id)->TO_JSON );

        return $c->render( status => 201, openapi => $patron );
    }
    catch {
        unless ( blessed $_ && $_->can('rethrow') ) {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check Koha logs for details." }
            );
        }
        if ( $_->isa('Koha::Exceptions::Object::DuplicateID') ) {
            return $c->render(
                status  => 409,
                openapi => { error => $_->error, conflict => $_->duplicate_id }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Object::FKConstraint') ) {
            return $c->render(
                status  => 400,
                openapi => {
                          error => "Given "
                        . $Koha::REST::V1::Patrons::to_api_mapping->{ $_->broken_fk }
                        . " does not exist"
                }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::BadParameter') ) {
            return $c->render(
                status  => 400,
                openapi => {
                          error => "Given "
                        . $Koha::REST::V1::Patrons::to_api_mapping->{ $_->parameter }
                        . " does not exist"
                }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check Koha logs for details." }
            );
        }
    };
}

1;
