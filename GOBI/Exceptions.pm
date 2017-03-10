package GOBI::Exceptions;

use Exception::Class (
    'GOBI::Exception',
    'GOBI::Exceptions::CustomerDetailNotFound' => {
        isa         => 'GOBI::Exception',
        description => 'Mandatory CustomerDetail not found'
    },
    'GOBI::Exceptions::NoXML' => {
        isa         => 'GOBI::Exception',
        description => 'XML missing in constructor'
    },
    'GOBI::Exceptions::OrderDetailNotFound' => {
        isa         => 'GOBI::Exception',
        description => 'Mandatory OrderDetail not found'
    }
);

1;
