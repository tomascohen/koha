#!/usr/bin/env perl

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

use Test::More tests => 5;
use Test::Mojo;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;

use C4::Auth;
use Koha::Cities;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# FIXME: sessionStorage defaults to mysql, but it seems to break transaction handling
# this affects the other REST api tests
t::lib::Mocks::mock_preference( 'SessionStorage', 'tmp' );

my $remote_address = '127.0.0.1';
my $t              = Test::Mojo->new('Koha::REST::V1');

subtest 'list() tests' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    unauthorized_access_tests('GET', undef, undef);

    subtest 'librarian access tests' => sub {
        plan tests => 8;

        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 1 });
        my $patron = Koha::Patrons->find($borrowernumber);
        Koha::Patrons->search({
            borrowernumber => { '!=' => $borrowernumber},
            cardnumber => { LIKE => $patron->cardnumber . "%" }
        })->delete;
        Koha::Patrons->search({
            borrowernumber => { '!=' => $borrowernumber},
            address2 => { LIKE => $patron->address2 . "%" }
        })->delete;

        my $tx = $t->ua->build_tx(GET => '/api/v1/patrons');
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $tx->req->env({REMOTE_ADDR => '127.0.0.1'});
        $t->request_ok($tx)
          ->status_is(200);

        $tx = $t->ua->build_tx(GET => '/api/v1/patrons?cardnumber='.
                                  $patron->cardnumber);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $tx->req->env({REMOTE_ADDR => '127.0.0.1'});
        $t->request_ok($tx)
          ->status_is(200)
          ->json_is('/0/cardnumber' => $patron->cardnumber);

        $tx = $t->ua->build_tx(GET => '/api/v1/patrons?address2='.
                                  $patron->address2);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $tx->req->env({REMOTE_ADDR => '127.0.0.1'});
        $t->request_ok($tx)
          ->status_is(200)
          ->json_is('/0/address2' => $patron->address2);
    };

    $schema->storage->txn_rollback;
};

subtest 'get() tests' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    unauthorized_access_tests('GET', -1, undef);

    subtest 'access own object tests' => sub {
        plan tests => 4;

        my ($patronid, $patronsessionid) = create_user_and_session({
            authorized => 0 });

        # Access patron's own data even though they have no borrowers flag
        my $tx = $t->ua->build_tx(GET => "/api/v1/patrons/$patronid");
        $tx->req->cookies({name => 'CGISESSID', value => $patronsessionid});
        $tx->req->env({REMOTE_ADDR => '127.0.0.1'});
        $t->request_ok($tx)
          ->status_is(200);

        my $guarantee = $builder->build({
            source => 'Borrower',
            value  => {
                guarantorid => $patronid,
            }
        });

        # Access guarantee's data even though guarantor has no borrowers flag
        my $guaranteenumber = $guarantee->{borrowernumber};
        $tx = $t->ua->build_tx(GET => "/api/v1/patrons/$guaranteenumber");
        $tx->req->cookies({name => 'CGISESSID', value => $patronsessionid});
        $tx->req->env({REMOTE_ADDR => '127.0.0.1'});
        $t->request_ok($tx)
          ->status_is(200);
    };

    subtest 'librarian access tests' => sub {
        plan tests => 5;

        my ($patron_id) = create_user_and_session({
            authorized => 0 });
        my $patron = Koha::Patrons->find($patron_id);
        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 1 });
        my $tx = $t->ua->build_tx(GET => "/api/v1/patrons/$patron_id");
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(200)
          ->json_is('/borrowernumber' => $patron_id)
          ->json_is('/surname' => $patron->surname)
          ->json_is('/lost' => Mojo::JSON->false );
    };

    $schema->storage->txn_rollback;
};

subtest 'add() tests' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $categorycode = $builder->build({ source => 'Category' })->{categorycode};
    my $branchcode = $builder->build({ source => 'Branch' })->{branchcode};
    my $newpatron = {
        address      => 'Street',
        branchcode   => $branchcode,
        cardnumber   => $branchcode.$categorycode,
        categorycode => $categorycode,
        city         => 'Joenzoo',
        surname      => "TestUser",
        userid       => $branchcode.$categorycode,
    };

    unauthorized_access_tests('POST', undef, $newpatron);

    subtest 'librarian access tests' => sub {
        plan tests => 18;

        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 1 });

        $newpatron->{branchcode} = "nonexistent"; # Test invalid branchcode
        my $tx = $t->ua->build_tx(POST => "/api/v1/patrons" =>json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(400)
          ->json_is('/error' => "Given branchcode does not exist");
        $newpatron->{branchcode} = $branchcode;

        $newpatron->{categorycode} = "nonexistent"; # Test invalid patron category
        $tx = $t->ua->build_tx(POST => "/api/v1/patrons" => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(400)
          ->json_is('/error' => "Given categorycode does not exist");
        $newpatron->{categorycode} = $categorycode;

        $newpatron->{falseproperty} = "Non existent property";
        $tx = $t->ua->build_tx(POST => "/api/v1/patrons" => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(400);
        delete $newpatron->{falseproperty};

        $tx = $t->ua->build_tx(POST => "/api/v1/patrons" => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(201, 'Patron created successfully')
          ->json_has('/borrowernumber', 'got a borrowernumber')
          ->json_is('/cardnumber', $newpatron->{ cardnumber })
          ->json_is('/surname' => $newpatron->{ surname })
          ->json_is('/firstname' => $newpatron->{ firstname });
        $newpatron->{borrowernumber} = $tx->res->json->{borrowernumber};

        $tx = $t->ua->build_tx(POST => "/api/v1/patrons" => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(409)
          ->json_has('/error', 'Fails when trying to POST duplicate'.
                     ' cardnumber or userid')
          ->json_has('/conflict', {
                        userid => $newpatron->{ userid },
                        cardnumber => $newpatron->{ cardnumber }
                    }
            );
    };

    $schema->storage->txn_rollback;
};

subtest 'edit() tests' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    unauthorized_access_tests('PUT', 123, {email => 'nobody@example.com'});

    subtest 'patron modifying own data' => sub {
        plan tests => 7;

        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 0 });
        my $patron = Koha::Patrons->find($borrowernumber)->TO_JSON;

        t::lib::Mocks::mock_preference("OPACPatronDetails", 0);
        my $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                            $patron->{borrowernumber} => json => $patron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(403, 'OPACPatronDetails off - modifications not allowed.');

        t::lib::Mocks::mock_preference("OPACPatronDetails", 1);
        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                            $patron->{borrowernumber} => json => $patron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(204, 'Updating myself with my current data');

        $patron->{'firstname'} = "noob";
        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                            $patron->{borrowernumber} => json => $patron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(202, 'Updating myself with my current data');

        # Approve changes
        Koha::Patron::Modifications->find({
            borrowernumber => $patron->{borrowernumber},
            firstname => "noob"
        })->approve;
        is(Koha::Patrons->find({
            borrowernumber => $patron->{borrowernumber}})->firstname,
           "noob", "Changes approved");
    };

    subtest 'librarian access tests' => sub {
        plan tests => 20;

        t::lib::Mocks::mock_preference('minPasswordLength', 1);
        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 1 });
        my ($borrowernumber2, undef) = create_user_and_session({
            authorized => 0 });
        my $patron    = Koha::Patrons->find($borrowernumber2);
        my $newpatron = Koha::Patrons->find($borrowernumber2)->TO_JSON;

        my $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/-1" =>
                                  json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(404)
          ->json_has('/error', 'Fails when trying to PUT nonexistent patron');

        $newpatron->{categorycode} = 'nonexistent';
        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                    $newpatron->{borrowernumber} => json => $newpatron
        );
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(400)
          ->json_is('/error' => "Given categorycode does not exist");
        $newpatron->{categorycode} = $patron->categorycode;

        $newpatron->{branchcode} = 'nonexistent';
        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                    $newpatron->{borrowernumber} => json => $newpatron
        );
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(400)
          ->json_is('/error' => "Given branchcode does not exist");
        $newpatron->{branchcode} = $patron->branchcode;

        $newpatron->{falseproperty} = "Non existent property";
        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                    $newpatron->{borrowernumber} => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(400)
          ->json_is('/errors/0/message' =>
                    'Properties not allowed: falseproperty.');
        delete $newpatron->{falseproperty};

        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                    $borrowernumber => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(409)
          ->json_has('/error' => "Fails when trying to update to an existing"
                     ."cardnumber or userid")
          ->json_has('/conflict', {
                cardnumber => $newpatron->{ cardnumber },
                userid => $newpatron->{ userid }
                }
            );

        $newpatron->{ cardnumber } = $borrowernumber.$borrowernumber2;
        $newpatron->{ userid } = "user".$borrowernumber.$borrowernumber2;
        $newpatron->{ surname } = "user".$borrowernumber.$borrowernumber2;

        $tx = $t->ua->build_tx(PUT => "/api/v1/patrons/" .
                    $newpatron->{borrowernumber} => json => $newpatron);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(200, 'Patron updated successfully')
          ->json_has($newpatron);
        is(Koha::Patrons->find($newpatron->{borrowernumber})->cardnumber,
           $newpatron->{ cardnumber }, 'Patron is really updated!');
    };

    $schema->storage->txn_rollback;
};

subtest 'delete() tests' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    unauthorized_access_tests('DELETE', 123, undef);

    subtest 'librarian access test' => sub {
        plan tests => 4;

        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 1 });
        my ($borrowernumber2, $sessionid2) = create_user_and_session({
            authorized => 0 });

        my $tx = $t->ua->build_tx(DELETE => "/api/v1/patrons/-1");
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(404, 'Patron not found');

        $tx = $t->ua->build_tx(DELETE => "/api/v1/patrons/$borrowernumber2");
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(200, 'Patron deleted successfully');
    };

    $schema->storage->txn_rollback;
};

# Centralized tests for 401s and 403s assuming the endpoint requires
# borrowers flag for access
sub unauthorized_access_tests {
    my ($verb, $patronid, $json) = @_;

    my $endpoint = '/api/v1/patrons';
    $endpoint .= ($patronid) ? "/$patronid" : '';

    subtest 'unauthorized access tests' => sub {
        plan tests => 5;

        my $tx = $t->ua->build_tx($verb => $endpoint => json => $json);
        $t->request_ok($tx)
          ->status_is(401);

        my ($borrowernumber, $sessionid) = create_user_and_session({
            authorized => 0 });

        $tx = $t->ua->build_tx($verb => $endpoint => json => $json);
        $tx->req->cookies({name => 'CGISESSID', value => $sessionid});
        $t->request_ok($tx)
          ->status_is(403)
          ->json_is('/required_permissions', {"borrowers" => "1"});
    };
}

sub create_user_and_session {

    my $args  = shift;
    my $flags = ( $args->{authorized} ) ? 16 : 0;
    my $dbh   = C4::Context->dbh;

    my $user = $builder->build(
        {
            source => 'Borrower',
            value  => {
                flags => $flags,
                gonenoaddress => 0,
                lost => 0,
                email => 'nobody@example.com',
                emailpro => 'nobody@example.com',
                B_email => 'nobody@example.com',
            }
        }
    );

    # Create a session for the authorized user
    my $session = C4::Auth::get_session('');
    $session->param( 'number',   $user->{borrowernumber} );
    $session->param( 'id',       $user->{userid} );
    $session->param( 'ip',       '127.0.0.1' );
    $session->param( 'lasttime', time() );
    $session->flush;

    return ( $user->{borrowernumber}, $session->id );
}
