use strict;
use warnings;
use strict;
use Test::More;
use Plack::Test;
use Plack::Util;
use HTTP::Request;
use File::Temp;

my $datadir = File::Temp->newdir;
$ENV{TEST_DATADIR} = $datadir;
$ENV{PLACK_ENV} = 'test';

ok my $app = Plack::Util::load_psgi('app.psgi');

test_psgi $app, sub {
    my $cb = shift;
    ok my $res = $cb->(HTTP::Request->new(GET => '/'));
    is $res->code, 404 or note explain $res;
};

done_testing;
