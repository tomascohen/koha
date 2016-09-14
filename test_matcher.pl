#!/usr/bin/perl

use Modern::Perl;

use Data::Printer colored => 1;

use C4::Context;
use C4::Matcher;

my $matcher = C4::Matcher->fetch(1);
p($matcher);

1;

