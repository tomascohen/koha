package Koha::REST::V1::Acquisitions::Orders;

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

use Koha::Acquisition::Orders;

use Try::Tiny;

sub list_orders {

    my $c = shift->openapi->valid_input or return;

    return try {
        my $orders = Koha::Acquisition::Orders->search_for_api($c);

        return $c->render(
            status  => 200,
            openapi => $orders
        );
    }
    catch {
        if ( $_->isa('DBIx::Class::Exception') ) {
            return $c->render(
                status  => 500,
                openapi => { error => $_->{msg} }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check the logs." }
            );
        }
    };
}

sub get_order {
    my $c = shift->openapi->valid_input or return;

    my $order = Koha::Acquisition::Orders->find( $c->validation->param('ordernumber') );
    unless ($order) {
        return $c->render(
            status  => 404,
            openapi => { error => "Order not found" }
        );
    }

    return $c->render(
        status  => 200,
        openapi => $order
    );
}

sub add_order {
    my $c = shift->openapi->valid_input or return;

    my $order = Koha::Acquisition::Order->new( $c->validation->param('body') );

    return try {
        $order->store;
        return $c->render(
            status  => 200,
            openapi => $order
        );
    }
    catch {
        if ( $_->isa('DBIx::Class::Exception') ) {
            return $c->render(
                status  => 500,
                openapi => { error => $_->msg }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check the logs." }
            );
        }
    };
}

sub update_order {
    my $c = shift->openapi->valid_input or return;

    my $order;

    return try {
        $order = Koha::Acquisition::Orders->find( $c->validation->param('ordernumber') );
        $order->set( $c->validation->param('body') );
        $order->store();
        return $c->render(
            status  => 200,
            openapi => $order
        );
    }
    catch {
        if ( not defined $order ) {
            return $c->render(
                status  => 404,
                openapi => { error => "Object not found" }
            );
        }
        elsif ( $_->isa('Koha::Exceptions::Object') ) {
            return $c->render(
                status  => 500,
                openapi => { error => $_->message }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check the logs." }
            );
        }
    };
}

sub delete_order {
    my $c = shift->openapi->valid_input or return;

    my $order;

    return try {
        $order = Koha::Acquisition::Orders->find( $c->validation->param('ordernumber') );
        $order->delete;
        return $c->render(
            status  => 200,
            openapi => q{}
        );
    }
    catch {
        if ( not defined $order ) {
            return $c->render(
                status  => 404,
                openapi => { error => "Object not found" }
            );
        }
        elsif ( $_->isa('DBIx::Class::Exception') ) {
            return $c->render(
                status  => 500,
                openapi => { error => $_->msg }
            );
        }
        else {
            return $c->render(
                status  => 500,
                openapi => { error => "Something went wrong, check the logs." }
            );
        }
    };
}

1;
