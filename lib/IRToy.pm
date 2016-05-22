package IRToy;
use warnings;
use strict;
#
# Support library for the IRtoy;
#

use Device::SerialPort;

# bleargh, boilerplate
#
sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    #$self->_handle_args(@_);
    return $self;
}

sub open {
    my $self = shift;
    my $port = shift;
    my $sp = Device::SerialPort->new($port);

    if (!defined($sp)) {
        return undef;
    }

    # this is deliberately assuming a POSIX environment where stty can set
    # most of the serial port config before we open the port.
    # TODO
    # - confirm that the remaining settings are actually useful

    $sp->read_char_time(10);
    $sp->read_const_time(20);
    $sp->write_settings() || return undef;

    $self->{serialport} = $sp;
    return $self;
}

# Send the reset command to the toy
sub reset {
    my $self = shift;
    my $reset = chr(0)x5;
    my $count = $self->{serialport}->write($reset);
    if (!$count) {
        return undef;
    }
    if ($count != length($reset)) {
        warn("Short write");
    }
    # TODO
    # - is this short write ever encountered?
    # - should we wait for write_done() here?
    return $count;
}

sub mode_s {
    my $self = shift;
    DIG HERE
    $self->{serialport}->write('s');
}

1;
