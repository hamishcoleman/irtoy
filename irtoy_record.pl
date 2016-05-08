#! /usr/bin/env perl
use warnings;
use strict;
#
#
# Anton Todorov
# CC BY (http://creativecommons.org/licenses/by/3.0/)

use File::Spec;

# allow the libs to be in the bin dir
use FindBin;
use lib File::Spec->catdir($FindBin::RealBin,"lib");
use lib File::Spec->catdir($ENV{HOME},"s/bin/lib");

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Quotekeys = 0;

use HC::Common;

unless ( eval {require USBIRToy} )
{
    die "USBIRToy.pm is missing!\n";
}

my $option = {
};
my @option_list = (
    "port=s",
    "prefix=s",
    "debug",
);

sub main() {
    HC::Common::do_options($option,@option_list);
    return if (defined($option->{help}));

    my $prefix = $option->{prefix} || $$ . "test";

    my %cfg;
    if ($option->{port}) {
        $cfg{port} = $option->{port};
    }

    my $ctrl;
    if ($option->{debug}) {
        $ctrl = 1<<0; # FIXME: DEBUG
    }

    # init RS232 ...
    my $rs = rs232init(%cfg);
    # set mode to 's'
    if ( !irtoy_mode_s( $rs, $ctrl ) )
    {
            die "Can't enter SAMPLING mode!\n";
    }

    # set prescaler
    my $mul = irtoy_setPrescaler( $rs, 7 );
    my $res;
    my $data = '';
    my $f_prefix;
    my $min;
    my $sum;
    my $arr_ref;
    my $i = 0;

    print "Press key on remote or CTRL+C to terminate\n";
    while (1)
    {
            $res = rsRx( $rs, $ctrl );
            if ($res)
            {
                    $data .= $res;
                    if ( irtoy_chkEnd( $res, $ctrl ) )
                    {
                            $f_prefix = sprintf "%s%03d", $prefix, $i++;
                            ( $min, $sum, $arr_ref ) =
                              irtoy_process( $mul, $f_prefix . ".bin", $ctrl, $data );
                            printf "Processed: '$f_prefix.bin' min=%d(%.4fus),"
                              . " sum=%.4fus, multiply=%.4f, len=%d\n",
                              $min, ( $min * $mul ), $sum * $mul, $mul, length($data);
                            if ( -f "irtoy.dump" )
                            {
                                    printf "prescaler=%.4f\n", $mul;
                                    foreach $res (@$arr_ref)
                                    {
                                            printf "0x%02x %.4f\n", $res, $res * $mul;
                                    }
                            }
                            $data = '';
                    } ## end if ( irtoy_chkEnd( $res...
            } ## end if ($res)
            else
            {
                    print "Press key on remote or CTRL+C to terminate\n";
            }
    } ## end while (1)

    $rs->close();
}

main();

