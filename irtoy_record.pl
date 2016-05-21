#! /usr/bin/env perl
use warnings;
use strict;
#
#
# Anton Todorov
# Hamish Coleman
# CC BY (http://creativecommons.org/licenses/by/3.0/)

use File::Spec;

# allow the libs to be in the bin dir
use FindBin;
use lib File::Spec->catdir($FindBin::RealBin,"lib");

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Quotekeys = 0;

use Getopt::Long 2.33 qw(:config gnu_getopt no_auto_abbrev);

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

sub do_options {
    my $option = shift || die "no option!";
    my @option_list = grep {$_} @_;
    GetOptions($option,@option_list,'man','help|?') or pod2usage(2);
    if ($option->{help} && @option_list) {
        print("List of options:\n");
        print("\t");
        foreach(sort @option_list) {
            $_="--".$_;
        }
        print join(", ",@option_list);
        print("\n");
    }
    pod2usage(-exitstatus => 0, -verbose => 2) if $option->{man};

    if ($option->{quiet}) {
        delete $option->{verbose};
    }
}

sub main() {
    do_options($option,@option_list);
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

