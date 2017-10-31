package Koha::Exceptions::Ill;

use Modern::Perl;

use Exception::Class (

    'Koha::Exceptions::Ill' => {
        description => 'Something went wrong!',
    },
    'Koha::Exceptions::Ill::InvalidBackendId' => {
        isa => 'Koha::Exceptions::Ill',
        description => "Invalid backend name required",
    }
);

1;
