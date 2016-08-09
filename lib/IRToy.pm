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

sub debug {
    my $self = shift;
    my $debug = shift;
    if (defined($debug)) {
        $self->{debug} = $debug;
    }
    return $self->{debug};
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

# write some bytes to the port
sub write {
    my $self = shift;
    my $buf = shift;

    if ($self->debug()) {
        print("DEBUG: write: ",unpack('H*',$buf),"\n");
    }

    return $self->{serialport}->write($buf);
}

# read some bytes from the port
sub read {
    my $self = shift;
    my $wanted = shift;

    my ($count,$buf) = $self->{serialport}->read($wanted);

    if ($self->debug()) {
        print("DEBUG: read() = ",$count,",",unpack('H*',$buf),"\n");
    }

    return ($count,$buf);
}

# Send the reset command to the toy
sub reset {
    my $self = shift;
    my $reset = chr(0)x5;
    my $count = $self->write($reset);
    if (!$count) {
        return undef;
    }
    if ($count != length($reset)) {
        warn("Short write");
    }
    # TODO
    # - is this short write ever encountered?
    # - should we wait for write_done() here?

    # Slirp up any data in the buffer
    # TODO - this could just make it slower?
    $self->read(255);

    return $count;
}

# IR sampling mode
sub mode_s {
    my $self = shift;
    $self->write('s');
    my ($count,$buf) = $self->read(3); # slirp up expected response data
    if ($buf eq 'S01') {
        return $self;
    }
    return undef;
}

sub mode_selftest {
    my $self = shift;
    $self->write('t');
    my ($count,$buf) = $self->read(4); # slirp up expected response data
    if ($buf eq 'V222') {
        return $self;
    }
    # FA20
    return undef;
}

# List of commands:
# SUMP mode
# "r" responds with OK
# "s" enter IR Sampling (done)
# "t" run selftest (done)
# "v" show version - responds with "V1xx"
# "u" enter serial port bridge mode
# "$" enter bootloader

1;
