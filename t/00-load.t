#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'iControl' ) || print "Bail out!
";
}

diag( "Testing iControl $iControl::VERSION, Perl $], $^X" );
